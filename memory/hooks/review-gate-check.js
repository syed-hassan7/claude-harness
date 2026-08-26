#!/usr/bin/env node
'use strict';
// Mechanical backstop for skipped pre-commit review (review-loop/security-audit
// trigger-gated but not enforced). Design rationale, rejected alternatives,
// and state shape live in memory/SPEC.md's "Review-gate memory" section --
// not duplicated here, see design-lane-gate-check.js's header for why.

const lib = require('./_lib');

const MARKER_RE = /\b(review-loop|security-audit|security-review|security-spec|red-team-desk|coderabbit)\b/i;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

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
  if (lib.isGitCommitCommand(command) && !sessState.reviewSeen) {
    sessState.pending = { at: lib.nowISO() };
    lib.appendGateLog(dir, logPath, lockPath, [
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
  const { dir, statePath, logPath, lockPath } = lib.gatePaths(base, 'review-gate');

  const state = lib.readGateState(statePath);
  const sessState = state[sessionId] || { offset: 0, reviewSeen: false, pending: null };

  let output = null;
  if (input.tool_name) {
    handlePostToolUse(input, sessState, transcriptPath, sessionId, dir, logPath, lockPath);
  } else {
    output = handleUserPromptSubmit(sessState);
  }

  sessState.lastSeen = lib.nowISO();
  state[sessionId] = sessState;
  lib.pruneIdleGateSessions(state, dir, logPath, lockPath, {
    ttlMs: SESSION_TTL_MS,
    pendingFields: ['pending'],
    describeExpired: (id) => `EXPIRED | ${lib.nowISO()} | session ${id} | commit MISS never surfaced, pruned after 30d idle`,
  });

  lib.writeGateState(dir, statePath, lockPath, state);

  if (output) process.stdout.write(JSON.stringify(output));
}

try {
  main();
} catch (_) {
  // Fail open -- a broken review-gate check must never block a real tool call.
}
process.exit(0);
