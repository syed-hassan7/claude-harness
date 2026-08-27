#!/usr/bin/env node
'use strict';
// Mechanical backstop for skipped pre-commit review (review-loop/security-audit
// trigger-gated but not enforced). Design rationale, rejected alternatives,
// and state shape live in memory/SPEC.md's "Review-gate memory" section --
// not duplicated here, see design-lane-gate-check.js's header for why.
//
// Structural detection, not a transcript text scan (same fix class as
// design-lane-gate-check.js -- see its header). The original version tested
// a marker regex against raw transcript text, which Claude Code's own
// injected agent-listing boilerplate (and the user's own prose mentioning
// "review-loop") satisfied before any real review ran -- a dead gate on any
// setup with the coderabbit plugin installed. This version only trusts the
// tool_name/tool_input of the PostToolUse call that actually fired the hook:
// a Skill invocation naming one of the review skills, an Agent invocation
// naming the coderabbit reviewer subagent, or a Bash command that actually
// runs the coderabbit CLI -- never free text.

const lib = require('./_lib');

const SKILL_MARKER_RE = /^(review-loop|security-audit|security-review|security-spec|red-team-desk|coderabbit)\b/i;
const SUBAGENT_MARKER_RE = /coderabbit/i;
const CLI_MARKER_RE = /\bcoderabbit\s+(review|autofix)\b/i;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

// PostToolUse (Bash|Skill|Agent): check whether THIS tool call is itself
// real review evidence, update the sticky reviewSeen flag, and -- if this is
// a git commit with reviewSeen still false -- log a MISS and set pending.
function handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath) {
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};

  if (toolName === 'Skill' && SKILL_MARKER_RE.test(toolInput.skill || '')) {
    sessState.reviewSeen = true;
  } else if (toolName === 'Agent' && SUBAGENT_MARKER_RE.test(toolInput.subagent_type || '')) {
    sessState.reviewSeen = true;
  } else if (toolName === 'Bash' && CLI_MARKER_RE.test(toolInput.command || '')) {
    sessState.reviewSeen = true;
  }

  if (toolName !== 'Bash') return; // only a Bash call can be the commit trigger
  const command = toolInput.command || '';
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

lib.runGateHook({
  gateName: 'review-gate',
  defaultSessionState: { reviewSeen: false, pending: null },
  ttlMs: SESSION_TTL_MS,
  pendingFields: ['pending'],
  describeExpired: (id) => `EXPIRED | ${lib.nowISO()} | session ${id} | commit MISS never surfaced, pruned after 30d idle`,
  handle: (input, { sessState, sessionId, dir, logPath, lockPath }) => {
    if (input.tool_name) {
      handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath);
      return null;
    }
    return handleUserPromptSubmit(sessState);
  },
});
process.exit(0);
