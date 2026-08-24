#!/usr/bin/env node
'use strict';
// UserPromptSubmit -- mechanical drift-canary miss detector. WORKFLOW.md's
// drift canary ("name Zarak when actively applying a named pack rule/skill")
// had no external check: the same fallible judgment that might skip applying
// a rule also grades whether it named itself doing so, so a miss was
// invisible to the agent that made it. This hook makes the *proxy signal*
// (pack-file citation + name co-occurrence) mechanically checkable instead.
//
// Uses `transcript_path`, a common field on every hook event (confirmed
// against code.claude.com/docs/en/hooks.md, 2026-08-24) -- NOT
// `last_assistant_message` (Stop-only, and confirmed via search the same day
// to be only the FINAL of potentially several assistant messages in a
// multi-tool-call turn; earlier narration in that turn -- exactly where this
// session's real misses landed -- is invisible to it). Reading transcript_path
// from a UserPromptSubmit hook sidesteps the documented async-write lag: by
// the time the next prompt fires, real wall-clock time has passed (the user
// read the response and typed a reply), so the prior turn's lines have almost
// certainly flushed. A cursor (byte offset) picks up any still-unflushed tail
// on the following prompt instead of dropping it.
//
// Explicitly a detector, not a gate: never blocks, never grades rule
// SUBSTANCE (that needs semantic judgment no hook can do -- see
// memory/SPEC.md's "Canary-drift memory" section for the stated limit, and
// its revisit condition if this proxy turns out not to be worth the noise).

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const PACK_FILES = [
  'rules/engineering.md',
  'rules/security-invariants.md',
  'rules/design-lane.md',
  'WORKFLOW.md',
  'skills/manifest.yaml',
  'memory/SPEC.md',
];
const PACK_FILE_RE = new RegExp(PACK_FILES.map((f) => f.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|'), 'i');
const NAME_RE = /\bzarak\b/i;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

// Reads only the bytes appended since `sinceOffset`, stopping at the last
// complete line -- a transcript write mid-flush must never be parsed as a
// truncated JSON line. Returns the unchanged offset (not `size`) when no
// complete line is available yet, so the partial tail is retried next time.
function readNewLines(transcriptPath, sinceOffset) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return { lines: [], newOffset: sinceOffset };
  const size = fs.statSync(transcriptPath).size;
  if (size <= sinceOffset) return { lines: [], newOffset: size < sinceOffset ? 0 : sinceOffset };
  const fd = fs.openSync(transcriptPath, 'r');
  let chunk;
  try {
    const len = size - sinceOffset;
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, sinceOffset);
    chunk = buf.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
  const lastNewline = chunk.lastIndexOf('\n');
  if (lastNewline === -1) return { lines: [], newOffset: sinceOffset };
  const usable = chunk.slice(0, lastNewline + 1);
  const newOffset = sinceOffset + Buffer.byteLength(usable, 'utf8');
  return { lines: usable.split('\n').filter(Boolean), newOffset };
}

// Concatenates every text block from every assistant-typed transcript line in
// range -- deliberately cumulative across however many assistant messages the
// prior turn actually took (tool-call round-trips split one turn into several
// "assistant" lines; this is exactly the coverage last_assistant_message
// lacked).
function extractAssistantText(lines) {
  const chunks = [];
  for (const line of lines) {
    let obj;
    try {
      obj = JSON.parse(line);
    } catch (_) {
      continue;
    }
    if (!obj || obj.type !== 'assistant') continue;
    const content = obj.message && obj.message.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block && block.type === 'text' && typeof block.text === 'string') chunks.push(block.text);
    }
  }
  return chunks.join('\n');
}

function readJSON(p, fallback) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || 'unknown';
  const transcriptPath = input.transcript_path || '';
  const { base } = lib.resolveScope(cwd);

  const canaryDir = path.join(base, 'canary');
  const statePath = path.join(canaryDir, 'state.json');
  const logPath = path.join(canaryDir, 'log.md');
  const lockPath = path.join(canaryDir, '.lock');

  const state = readJSON(statePath, {});
  const sessState = state[sessionId] || { offset: 0, pending: null };

  const { lines, newOffset } = readNewLines(transcriptPath, sessState.offset);
  sessState.offset = newOffset;
  sessState.lastSeen = lib.nowISO();

  if (lines.length) {
    const text = extractAssistantText(lines);
    const citesPack = PACK_FILE_RE.test(text);
    const hasName = NAME_RE.test(text);
    const events = [];

    if (sessState.pending) {
      if (hasName) {
        events.push(`RESOLVED | ${lib.nowISO()} | session ${sessionId} | prior miss on ${sessState.pending.file} -- name reappeared`);
        sessState.pending = null;
      } else if (citesPack) {
        sessState.pending.escalations = (sessState.pending.escalations || 0) + 1;
        events.push(
          `ESCALATED (${sessState.pending.escalations}) | ${lib.nowISO()} | session ${sessionId} | still missing since citing ${sessState.pending.file}`
        );
      }
    }
    if (!sessState.pending && citesPack && !hasName) {
      const matchedFile = PACK_FILES.find((f) => text.toLowerCase().includes(f.toLowerCase())) || 'a pack file';
      const excerpt = text.replace(/\s+/g, ' ').trim().slice(0, 140);
      sessState.pending = { file: matchedFile, at: lib.nowISO() };
      events.push(`OPEN | ${lib.nowISO()} | session ${sessionId} | cited ${matchedFile}, no name -- "${excerpt}"`);
    }

    if (events.length) {
      lib.ensureDir(canaryDir);
      lib.ensureGitignore(canaryDir);
      lib.withLock(lockPath, () => {
        fs.appendFileSync(logPath, events.join('\n') + '\n');
      });
    }
  }

  // Prune idle sessions so state.json doesn't grow unbounded across months --
  // a known simplification, same "bound it, don't build eviction machinery
  // until it's a real problem" posture as this file's other size caps. A
  // session pruned with a still-open `pending` miss gets one EXPIRED line
  // first -- otherwise the audit trail just loses the miss silently instead
  // of closing it out.
  state[sessionId] = sessState;
  const cutoff = Date.now() - SESSION_TTL_MS;
  const expiredEvents = [];
  for (const id of Object.keys(state)) {
    const seen = state[id] && state[id].lastSeen ? Date.parse(state[id].lastSeen) : 0;
    if (!Number.isNaN(cutoff) && seen < cutoff) {
      if (state[id] && state[id].pending) {
        expiredEvents.push(
          `EXPIRED | ${lib.nowISO()} | session ${id} | miss on ${state[id].pending.file} never resolved, pruned after 30d idle`
        );
      }
      delete state[id];
    }
  }
  if (expiredEvents.length) {
    lib.ensureDir(canaryDir);
    lib.ensureGitignore(canaryDir);
    lib.withLock(lockPath, () => {
      fs.appendFileSync(logPath, expiredEvents.join('\n') + '\n');
    });
  }
  lib.ensureDir(canaryDir);
  lib.ensureGitignore(canaryDir);
  lib.withLock(lockPath, () => {
    lib.atomicWrite(statePath, JSON.stringify(state));
  });

  if (sessState.pending) {
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'UserPromptSubmit',
          additionalContext:
            `## Claude Harness -- drift canary miss\n\n` +
            `Cited ${sessState.pending.file} without naming Zarak last turn. ` +
            `WORKFLOW.md's drift canary applies -- resume it in this response if still discussing a pack rule.`,
        },
      })
    );
  }
}

try {
  main();
} catch (_) {
  // Fail open -- a broken canary check must never block the user's prompt.
}
process.exit(0);
