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
    } catch (_) {
      return; // plan file vanished/unreadable -- fail open
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

function main() {
  const input = lib.readHookInput();
  if (input.tool_name && !isRelevantPostToolUse(input)) return;

  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || 'unknown';
  const { base } = lib.resolveScope(cwd);
  const { dir, statePath, logPath, lockPath } = lib.gatePaths(base, 'visual-plan-gate');

  const state = lib.readGateState(statePath);
  const sessState = state[sessionId] || { planFilePath: null, artifactPublished: false, pending: null };

  let output = null;
  if (input.tool_name) {
    handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath);
  } else {
    output = handleUserPromptSubmit(sessState);
  }

  sessState.lastSeen = lib.nowISO();
  state[sessionId] = sessState;
  lib.pruneIdleGateSessions(state, dir, logPath, lockPath, {
    ttlMs: SESSION_TTL_MS,
    pendingFields: ['pending'],
    describeExpired: (id) => `EXPIRED | ${lib.nowISO()} | session ${id} | visual-plan MISS never surfaced, pruned after 30d idle`,
  });

  lib.writeGateState(dir, statePath, lockPath, state);

  if (output) process.stdout.write(JSON.stringify(output));
}

try {
  main();
} catch (_) {
  // Fail open -- a broken visual-plan gate check must never block a real tool call.
}
process.exit(0);
