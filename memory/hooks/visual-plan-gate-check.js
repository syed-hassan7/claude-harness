#!/usr/bin/env node
'use strict';
// Dual-registered: PostToolUse (matcher: Write|Edit|ExitPlanMode|Artifact)
// AND UserPromptSubmit -- same file, branches on whether `tool_name` is
// present in the stdin payload. Mechanical backstop for a third gap of the
// same shape as review-gate-check.js/design-lane-gate-check.js:
// WORKFLOW.md:44 correctly names visual-plan-local as plan mode's default
// "Final Plan" output (structured doc + rendered Artifact companion) --
// but nothing checks it actually happens. Observed skipped for real in this
// session's own non-trivial plan before this hook existed (a 5-file,
// multi-step plan shipped as flat markdown, zero Artifact call) -- a
// well-written bullet getting skipped anyway is the stronger argument for a
// hook, not a weaker one.
//
// Detection:
//   - planFilePath (sticky, per session) -- last Write/Edit whose file_path
//     resolves under <home>/.claude/plans/*.md. This is a FIXED,
//     home-anchored location, not a lib.resolveScope project/global-split
//     store -- confirmed against a real plan-mode system reminder in this
//     same session (the plan path was home-anchored while cwd sat inside a
//     git repo). Only this hook's OWN state store (state.json/log.md) uses
//     resolveScope -- two separate concerns, don't conflate them.
//   - artifactPublished (sticky, per session) -- tool_name matches /artifact/i
//     (loose regex, not strict equality: the literal string "Artifact" was
//     confirmed empirically against a real transcript before relying on it,
//     but a loose match is cheap insurance against future renaming, same
//     precedent as design-lane-gate-check.js's /^mcp__playwright/i check).
//   - On tool_name === 'ExitPlanMode': read the tracked plan file's current
//     content, apply a cheap non-trivial heuristic (length, or 2+ file-path-
//     like backtick spans), and if non-trivial with no artifact published
//     this session, log a MISS and surface it once on the next prompt.
//
// Never blocks -- same posture as every hook in this pack. No planFilePath
// tracked yet (e.g. plan mode entered without editing the plan file through
// a visible Write/Edit) fails open -- no MISS is logged, since there is
// nothing to judge non-triviality against.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const ARTIFACT_MARKER_RE = /artifact/i;
const NONTRIVIAL_LENGTH = 1200;
const FILE_MENTION_RE = /`[^`\n]+\.[a-zA-Z0-9]+`/g;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

function readJSON(p, fallback) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function paths(base) {
  const dir = path.join(base, 'visual-plan-gate');
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
        expired.push(`EXPIRED | ${lib.nowISO()} | session ${id} | visual-plan MISS never surfaced, pruned after 30d idle`);
      }
      delete state[id];
    }
  }
  appendLog(dir, logPath, lockPath, expired);
}

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
      appendLog(dir, logPath, lockPath, [
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
  const { dir, statePath, logPath, lockPath } = paths(base);

  const state = readJSON(statePath, {});
  const sessState = state[sessionId] || { planFilePath: null, artifactPublished: false, pending: null };

  let output = null;
  if (input.tool_name) {
    handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath);
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
  // Fail open -- a broken visual-plan gate check must never block a real tool call.
}
process.exit(0);
