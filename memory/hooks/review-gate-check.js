#!/usr/bin/env node
'use strict';
// Dual-registered: PostToolUse (matcher: Bash) AND UserPromptSubmit -- same
// file, branches on whether `tool_name` is present in the stdin payload.
// Mechanical backstop for a real gap: review-loop/security-audit are
// trigger-gated skills ("pre-merge") with no enforcement beyond agent
// judgment -- and a live incident in this repo shipped a commit with
// neither invoked despite matching triggers (see
// memory/project_skill_adoption_gap_evidence.md). This hook detects that
// pattern after the fact, the same non-blocking posture canary-check.js
// already uses for the drift canary -- it never blocks a commit, it only
// notices and logs when one shipped without evidence either skill ran
// anywhere earlier in the session.
//
// Detection window is sticky per session, not per commit: once
// review-loop/security-audit evidence is seen anywhere in the transcript,
// every later commit in that session is considered clean. This does not
// re-arm after a commit -- a session that reviews once early then ships a
// second large unreviewed round later won't be re-flagged. Accepted
// trade-off, not a bug; revisit only if that proves a real gap in practice.
//
// Commit detection is a text pattern against tool_input.command, not a
// tool_response exit-code check -- reading tool_response would cross a line
// audit-log/SECURITY_SPEC.md already draws deliberately for hook design
// (never consult tool_response) for a benefit that doesn't justify it here:
// a false MISS on a failed commit attempt costs one spurious log line, not
// a broken workflow. Best-effort classification, not reliable capture --
// same class of limitation SECURITY_SPEC.md already accepts for its own
// Bash coverage.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const COMMIT_RE = /\bgit\b[^&|;\n]*\bcommit\b/i;
const MARKER_RE = /\b(review-loop|security-audit|security-review|security-spec|red-team-desk|coderabbit)\b/i;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

function readJSON(p, fallback) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function paths(base) {
  const dir = path.join(base, 'review-gate');
  return {
    dir,
    statePath: path.join(dir, 'state.json'),
    logPath: path.join(dir, 'log.md'),
    lockPath: path.join(dir, '.lock'),
  };
}

function appendLog(dir, logPath, lockPath, lines) {
  if (!lines.length) return;
  lib.ensureDir(dir);
  lib.ensureGitignore(dir);
  lib.withLock(lockPath, () => {
    fs.appendFileSync(logPath, lines.join('\n') + '\n');
  });
}

function pruneIdle(state, dir, logPath, lockPath) {
  const cutoff = Date.now() - SESSION_TTL_MS;
  const expired = [];
  for (const id of Object.keys(state)) {
    const seen = state[id] && state[id].lastSeen ? Date.parse(state[id].lastSeen) : 0;
    if (!Number.isNaN(cutoff) && seen < cutoff) {
      if (state[id] && state[id].pending) {
        expired.push(`EXPIRED | ${lib.nowISO()} | session ${id} | commit MISS never surfaced, pruned after 30d idle`);
      }
      delete state[id];
    }
  }
  appendLog(dir, logPath, lockPath, expired);
}

// PostToolUse (Bash): scan new transcript text for review-marker evidence,
// update the sticky reviewSeen flag, and -- if this command matches a git
// commit with reviewSeen still false -- log a MISS and set pending.
function handlePostToolUse(input, sessState, transcriptPath, sessionId, dir, logPath, lockPath) {
  const { lines, newOffset } = lib.readTranscriptSince(transcriptPath, sessState.offset);
  sessState.offset = newOffset;
  if (lines.length) {
    const text = lines.join('\n');
    if (MARKER_RE.test(text)) sessState.reviewSeen = true;
  }

  const command = (input.tool_input && input.tool_input.command) || '';
  if (COMMIT_RE.test(command) && !sessState.reviewSeen) {
    sessState.pending = { at: lib.nowISO() };
    appendLog(dir, logPath, lockPath, [
      `MISS | ${lib.nowISO()} | session ${sessionId} | commit ran, no review-loop/security-audit evidence yet this session`,
    ]);
  }
}

// UserPromptSubmit: surface a pending miss exactly once, then clear it --
// there's no "fix" signal for a commit that already happened, only an
// acknowledgment that it was flagged.
function handleUserPromptSubmit(sessState) {
  if (!sessState.pending) return null;
  sessState.pending = null;
  return {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext:
        `## Claude Harness -- review-gate miss\n\n` +
        `A commit ran earlier with no review-loop/security-audit evidence found in this session. ` +
        `Logged, not blocking -- consider running one before further commits if the change is substantial.`,
    },
  };
}

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || 'unknown';
  const transcriptPath = input.transcript_path || '';
  const { base } = lib.resolveScope(cwd);
  const { dir, statePath, logPath, lockPath } = paths(base);

  const state = readJSON(statePath, {});
  const sessState = state[sessionId] || { offset: 0, reviewSeen: false, pending: null };

  let output = null;
  if (input.tool_name) {
    handlePostToolUse(input, sessState, transcriptPath, sessionId, dir, logPath, lockPath);
  } else {
    output = handleUserPromptSubmit(sessState);
  }

  sessState.lastSeen = lib.nowISO();
  state[sessionId] = sessState;
  pruneIdle(state, dir, logPath, lockPath);

  lib.ensureDir(dir);
  lib.ensureGitignore(dir);
  lib.withLock(lockPath, () => {
    lib.atomicWrite(statePath, JSON.stringify(state));
  });

  if (output) process.stdout.write(JSON.stringify(output));
}

try {
  main();
} catch (_) {
  // Fail open -- a broken review-gate check must never block a real tool call.
}
process.exit(0);
