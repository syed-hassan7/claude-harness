#!/usr/bin/env node
'use strict';
// Mechanical backstop for WORKFLOW.md's drift canary (name-drop proxy for
// "a pack rule was actually applied"). Design rationale, rejected
// alternatives, and state shape live in memory/SPEC.md's "Canary-drift
// memory" section -- not duplicated here, see design-lane-gate-check.js's
// header for why.

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

// True turn boundary -- a real user-typed prompt, not a tool_result line fed
// back mid-turn (those are also `type: "user"` but carry no `text` block).
// Needed because a hook invocation can span MULTIPLE real turns when no user
// message arrives in between (e.g. an approved plan running straight through
// build+verify with no intervening prompt) -- found live: one early name-drop
// satisfied `hasName` for an entire multi-turn batch, silently masking eight
// later unnamed citations in the same session. See memory/SPEC.md's
// "Canary-drift memory" section for the incident this fixed.
function isRealUserTurnBoundary(line) {
  let obj;
  try {
    obj = JSON.parse(line);
  } catch (_) {
    return false;
  }
  if (!obj || obj.type !== 'user') return false;
  const content = obj.message && obj.message.content;
  if (!Array.isArray(content)) return false;
  return content.some((b) => b && b.type === 'text' && typeof b.text === 'string' && b.text.trim().length > 0);
}

// Splits a run of new transcript lines into one group per real turn, dropping
// the boundary line itself (a user prompt, never assistant text). Within a
// group, tool-call round-trips still concatenate as before -- only a REAL
// user message starts a new group.
function partitionIntoTurns(lines) {
  const turns = [];
  let current = [];
  for (const line of lines) {
    if (isRealUserTurnBoundary(line)) {
      if (current.length) turns.push(current);
      current = [];
      continue;
    }
    current.push(line);
  }
  if (current.length) turns.push(current);
  return turns;
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

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || 'unknown';
  const transcriptPath = input.transcript_path || '';
  const { base } = lib.resolveScope(cwd);

  const { dir: canaryDir, statePath, logPath, lockPath } = lib.gatePaths(base, 'canary');

  const state = lib.readGateState(statePath);
  const sessState = state[sessionId] || { offset: 0, pending: null };

  const { lines, newOffset } = lib.readTranscriptSince(transcriptPath, sessState.offset);
  sessState.offset = newOffset;
  sessState.lastSeen = lib.nowISO();

  if (lines.length) {
    const events = [];
    // One evaluation per real turn, not one over the whole batch -- a
    // name-drop in an earlier turn must not mask a citation in a later one
    // just because both landed in the same hook invocation.
    for (const turnLines of partitionIntoTurns(lines)) {
      const text = extractAssistantText(turnLines);
      if (!text) continue;
      const citesPack = PACK_FILE_RE.test(text);
      const hasName = NAME_RE.test(text);

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
    }

    if (events.length) lib.appendGateLog(canaryDir, logPath, lockPath, events);
  }

  // Prune idle sessions so state.json doesn't grow unbounded across months --
  // a known simplification, same "bound it, don't build eviction machinery
  // until it's a real problem" posture as this file's other size caps. A
  // session pruned with a still-open `pending` miss gets one EXPIRED line
  // first -- otherwise the audit trail just loses the miss silently instead
  // of closing it out.
  state[sessionId] = sessState;
  lib.pruneIdleGateSessions(state, canaryDir, logPath, lockPath, {
    ttlMs: SESSION_TTL_MS,
    pendingFields: ['pending'],
    describeExpired: (id, _field, s) =>
      `EXPIRED | ${lib.nowISO()} | session ${id} | miss on ${s.pending.file} never resolved, pruned after 30d idle`,
  });

  lib.writeGateState(canaryDir, statePath, lockPath, state);

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
