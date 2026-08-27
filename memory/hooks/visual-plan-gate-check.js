#!/usr/bin/env node
'use strict';
// Mechanical backstop for WORKFLOW.md:44's plan-mode default (visual-plan-local
// Artifact companion on a non-trivial plan). Design rationale, rejected
// alternatives, and state shape live in memory/SPEC.md's "Visual-plan gate
// memory" section -- not duplicated here, see design-lane-gate-check.js's
// header for why.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const ARTIFACT_MARKER_RE = /artifact/i;
const NONTRIVIAL_LENGTH = 1200;
const FILE_MENTION_RE = /`[^`\n]+\.[a-zA-Z0-9]+`/g;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

function plansDir() {
  return path.join(lib.homeDir(), '.claude', 'plans');
}

function norm(p) {
  return (p || '').replace(/\\/g, '/').toLowerCase();
}

function isPlanFilePath(filePath) {
  if (!filePath || !/\.md$/i.test(filePath)) return false;
  return norm(filePath).startsWith(norm(plansDir()) + '/');
}

function isNonTrivial(planText) {
  if (!planText) return false;
  if (planText.length > NONTRIVIAL_LENGTH) return true;
  const mentions = planText.match(FILE_MENTION_RE) || [];
  return mentions.length >= 2;
}

// Cheap pre-check, before any disk I/O -- mirrors design-lane-gate-check.js's
// own early-return-before-touching-state pattern.
function isRelevantPostToolUse(input) {
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};
  if (toolName === 'Edit' || toolName === 'Write') return isPlanFilePath(toolInput.file_path || '');
  if (toolName === 'ExitPlanMode') return true;
  return ARTIFACT_MARKER_RE.test(toolName);
}

function handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath) {
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};

  if (toolName === 'Edit' || toolName === 'Write') {
    const filePath = toolInput.file_path || '';
    if (isPlanFilePath(filePath)) sessState.planFilePath = filePath;
    return;
  }
  if (ARTIFACT_MARKER_RE.test(toolName)) {
    sessState.artifactPublished = true;
    return;
  }
  if (toolName === 'ExitPlanMode') {
    if (!sessState.planFilePath) return; // nothing tracked to judge -- fail open, never a false MISS
    let planText = '';
    try {
      planText = fs.readFileSync(sessState.planFilePath, 'utf8');
    } catch (err) {
      // Fail open either way, but a plan file that vanished is the normal case
      // (scratch file, cleaned up) while an unreadable one means this gate is
      // silently off for the rest of the session -- not the same thing.
      if (err.code !== 'ENOENT') lib.recordHookError(err, `reading plan file ${sessState.planFilePath}`);
      return;
    }
    if (isNonTrivial(planText) && !sessState.artifactPublished) {
      sessState.pending = { at: lib.nowISO() };
      lib.appendGateLog(dir, logPath, lockPath, [
        `MISS | ${lib.nowISO()} | session ${sessionId} | ExitPlanMode on a non-trivial plan, no Artifact publish found this session`,
      ]);
    }
  }
}

// UserPromptSubmit: surface a pending miss exactly once, then clear it --
// same one-shot acknowledgment pattern as the other two gates.
function handleUserPromptSubmit(sessState) {
  if (!sessState.pending) return null;
  sessState.pending = null;
  return {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext:
        `## Claude Harness -- visual-plan gate miss\n\n` +
        `Plan mode exited on a non-trivial plan earlier this session, with no Artifact publish found. ` +
        `Logged, not blocking -- visual-plan-local (WORKFLOW.md's plan-mode default) applies if a rendered companion is still owed.`,
    },
  };
}

// Diagnostics on failure: runGateHook itself calls lib.recordHookError before
// swallowing -- not repeated per gate file, see _lib.js's runGateHook header.
lib.runGateHook({
  gateName: 'visual-plan-gate',
  defaultSessionState: { planFilePath: null, artifactPublished: false, pending: null },
  ttlMs: SESSION_TTL_MS,
  pendingFields: ['pending'],
  describeExpired: (id) => `EXPIRED | ${lib.nowISO()} | session ${id} | visual-plan MISS never surfaced, pruned after 30d idle`,
  shouldProcess: (input) => !input.tool_name || isRelevantPostToolUse(input),
  handle: (input, { sessState, sessionId, dir, logPath, lockPath }) => {
    if (input.tool_name) {
      handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath);
      return null;
    }
    return handleUserPromptSubmit(sessState);
  },
});
process.exit(0);
