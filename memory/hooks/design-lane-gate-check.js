#!/usr/bin/env node
'use strict';
// Dual-registered: PostToolUse (matcher: Edit|Write|Read|Bash|mcp__playwright.*)
// AND UserPromptSubmit -- same file, branches on whether `tool_name` is
// present in the stdin payload. Mechanical backstop for a second gap of the
// same shape as review-gate-check.js: rules/design-lane.md's
// render-before-judging step is called "hard, not optional" but nothing
// mechanically checks whether it actually happened before UI work shipped.
//
// Detection is almost entirely structural, not a transcript text scan --
// deliberately different from canary-check.js/review-gate-check.js. The
// obvious first design (scan transcript text for "done"/"looks good"/
// "verified") was rejected during planning: caveman-ultra style uses those
// words constantly for unrelated work in the same session, so it would
// false-positive far more than it would catch. Instead:
//   - uiTouched sets from Edit/Write on a UI-extension file (tsx/jsx/vue/
//     svelte/css/scss/less/html) -- tool_input.file_path is an exact field,
//     no proxy-text-matching needed.
//   - screenshotSeen sets from Read on an image file, any mcp__playwright.*
//     tool call, or (one narrow exception) a Bash command mentioning
//     "playwright" specifically -- this IS a proxy-text match, same limited
//     class as review-gate-check.js's marker scan, kept deliberately narrow
//     (playwright only, not a bare "screenshot" word -- that alone showed up
//     in ordinary commit messages like "fix screenshot upload" during
//     review, which would have satisfied evidence for reasons unrelated to
//     verification actually happening).
//   - The crisp trigger stays the commit event (lib.isGitCommitCommand,
//     shared with review-gate-check.js) -- reusing the one trigger already
//     proven low-noise rather than inventing a second, noisier one.
//
// Sticky per session, not per commit, same accepted trade-off as
// review-gate-check.js: one screenshot anywhere satisfies every later
// commit; one UI-file edit anywhere primes every later commit for the
// check. Never blocks -- same posture as every hook in this pack.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const UI_FILE_RE = /\.(tsx|jsx|vue|svelte|css|scss|less|html)$/i;
const IMAGE_FILE_RE = /\.(png|jpe?g|webp|gif)$/i;
const SCREENSHOT_MARKER_RE = /\bplaywright\b/i;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

function readJSON(p, fallback) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function paths(base) {
  const dir = path.join(base, 'design-lane-gate');
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
        expired.push(`EXPIRED | ${lib.nowISO()} | session ${id} | design-lane MISS never surfaced, pruned after 30d idle`);
      }
      delete state[id];
    }
  }
  appendLog(dir, logPath, lockPath, expired);
}

// Cheap pre-check, before any disk I/O -- mirrors memory-architecture.js's
// own early-return-before-touching-state pattern. An Edit/Write on a non-UI
// file or a Read of a non-image file can never change either sticky flag,
// so it's not worth a readJSON+pruneIdle+atomicWrite round-trip on every
// single tool call the broad matcher receives.
function isRelevantPostToolUse(input) {
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};
  if (toolName === 'Edit' || toolName === 'Write') return UI_FILE_RE.test(toolInput.file_path || '');
  if (toolName === 'Read') return IMAGE_FILE_RE.test(toolInput.file_path || '');
  if (toolName === 'Bash') return true; // could be the commit trigger or a playwright marker
  return /^mcp__playwright/i.test(toolName);
}

// PostToolUse: update the two sticky flags per tool type, and -- on a git
// commit with uiTouched true and screenshotSeen still false -- log a MISS.
function handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath) {
  const toolName = input.tool_name || '';
  const toolInput = input.tool_input || {};

  if (toolName === 'Edit' || toolName === 'Write') {
    if (UI_FILE_RE.test(toolInput.file_path || '')) sessState.uiTouched = true;
    return;
  }
  if (toolName === 'Read') {
    if (IMAGE_FILE_RE.test(toolInput.file_path || '')) sessState.screenshotSeen = true;
    return;
  }
  if (/^mcp__playwright/i.test(toolName)) {
    sessState.screenshotSeen = true;
    return;
  }
  if (toolName === 'Bash') {
    const command = toolInput.command || '';
    // Snapshot evidence from BEFORE this command, not after -- a single
    // chained command that mentions both a commit and playwright (e.g.
    // `git commit -m x && npx playwright test`) must not let verification
    // text appearing AFTER the commit in the same string retroactively
    // satisfy a check about what happened before shipping.
    const hadScreenshotEvidence = sessState.screenshotSeen;
    if (SCREENSHOT_MARKER_RE.test(command)) sessState.screenshotSeen = true;
    if (lib.isGitCommitCommand(command) && sessState.uiTouched && !hadScreenshotEvidence) {
      sessState.pending = { at: lib.nowISO() };
      appendLog(dir, logPath, lockPath, [
        `MISS | ${lib.nowISO()} | session ${sessionId} | commit ran, UI file touched this session, no screenshot/Playwright evidence found`,
      ]);
    }
  }
}

// UserPromptSubmit: surface a pending miss exactly once, then clear it --
// same one-shot acknowledgment pattern as review-gate-check.js.
function handleUserPromptSubmit(sessState) {
  if (!sessState.pending) return null;
  sessState.pending = null;
  return {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext:
        `## Claude Harness -- design-lane gate miss\n\n` +
        `A commit ran earlier that touched a UI file, with no screenshot/Playwright evidence found in this session. ` +
        `Logged, not blocking -- rules/design-lane.md's render-before-judging gate applies if UI/visual work is still in flight.`,
    },
  };
}

function main() {
  const input = lib.readHookInput();
  if (input.tool_name && !isRelevantPostToolUse(input)) return; // nothing this call could change -- skip all state I/O

  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || 'unknown';
  const { base } = lib.resolveScope(cwd);
  const { dir, statePath, logPath, lockPath } = paths(base);

  const state = readJSON(statePath, {});
  const sessState = state[sessionId] || { uiTouched: false, screenshotSeen: false, pending: null };

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
  // Fail open -- a broken design-lane gate check must never block a real tool call.
}
process.exit(0);
