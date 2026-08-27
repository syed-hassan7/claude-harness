#!/usr/bin/env node
'use strict';
// Mechanical backstop for rules/design-lane.md's render-before-judging gate
// (screenshot/Playwright evidence before UI work ships) and its native-form-
// control blind spot. Design rationale, rejected alternatives, and the
// native-control addition's incident writeup live in memory/SPEC.md's
// "Design-lane gate memory" section -- not duplicated here per
// rules/engineering.md's context-economy section (push detail to the doc
// that already owns it, don't re-derive it in a header comment on every hook
// this shape gets applied to).

const lib = require('./_lib');

const UI_FILE_RE = /\.(tsx|jsx|vue|svelte|css|scss|less|html)$/i;
const IMAGE_FILE_RE = /\.(png|jpe?g|webp|gif)$/i;
const SCREENSHOT_MARKER_RE = /\bplaywright\b/i;
// Case-sensitive: lowercase-only avoids matching a custom capitalized
// <Select> component (React/Vue convention reserves PascalCase for those).
const NATIVE_SELECT_RE = /<select[\s/>]/;
// Case-sensitive too, same reason as NATIVE_SELECT_RE above -- an /i flag
// here would also match a custom PascalCase <Input> component (shadcn/ui,
// MUI, Chakra, Radix, Ant Design all ship <Input type="date">), the more
// common wrapped pattern in practice. Caught at review, not shipped as-is.
const NATIVE_INPUT_RE = /<input\s+[^>]*type=["'](?:date|time|color|range|month|week)["']/;
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // prune state entries idle > 30 days

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
    const filePath = toolInput.file_path || '';
    if (UI_FILE_RE.test(filePath)) {
      sessState.uiTouched = true;
      const addedText = toolName === 'Edit' ? (toolInput.new_string || '') : (toolInput.content || '');
      if (NATIVE_SELECT_RE.test(addedText) || NATIVE_INPUT_RE.test(addedText)) {
        sessState.pendingNativeControl = { at: lib.nowISO(), file: filePath };
        lib.appendGateLog(dir, logPath, lockPath, [
          `NATIVE | ${lib.nowISO()} | session ${sessionId} | native form control added in ${filePath} -- screenshot verification has a blind spot for this component class (see rules/design-lane.md anti-patterns)`,
        ]);
      }
    }
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
      lib.appendGateLog(dir, logPath, lockPath, [
        `MISS | ${lib.nowISO()} | session ${sessionId} | commit ran, UI file touched this session, no screenshot/Playwright evidence found`,
      ]);
    }
  }
}

// UserPromptSubmit: surface a pending miss exactly once, then clear it --
// same one-shot acknowledgment pattern as review-gate-check.js.
function handleUserPromptSubmit(sessState) {
  const blocks = [];
  if (sessState.pending) {
    sessState.pending = null;
    blocks.push(
      `## Claude Harness -- design-lane gate miss\n\n` +
      `A commit ran earlier that touched a UI file, with no screenshot/Playwright evidence found in this session. ` +
      `Logged, not blocking -- rules/design-lane.md's render-before-judging gate applies if UI/visual work is still in flight.`
    );
  }
  if (sessState.pendingNativeControl) {
    const file = sessState.pendingNativeControl.file || 'a UI file';
    sessState.pendingNativeControl = null;
    blocks.push(
      `## Claude Harness -- native-control blind spot\n\n` +
      `A native form control (<select>/<input type="date"> etc.) was added in ${file}. ` +
      `Its OS-rendered popup chrome is invisible to screenshot verification by construction -- see rules/design-lane.md's anti-patterns list. Logged, not blocking.`
    );
  }
  if (!blocks.length) return null;
  return {
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: blocks.join('\n\n'),
    },
  };
}

lib.runGateHook({
  gateName: 'design-lane-gate',
  defaultSessionState: { uiTouched: false, screenshotSeen: false, pending: null, pendingNativeControl: null },
  ttlMs: SESSION_TTL_MS,
  pendingFields: ['pending', 'pendingNativeControl'],
  describeExpired: (id, field) =>
    field === 'pendingNativeControl'
      ? `EXPIRED | ${lib.nowISO()} | session ${id} | native-control nudge never surfaced, pruned after 30d idle`
      : `EXPIRED | ${lib.nowISO()} | session ${id} | design-lane MISS never surfaced, pruned after 30d idle`,
  shouldProcess: (input) => !input.tool_name || isRelevantPostToolUse(input), // nothing a non-relevant call could change -- skip all state I/O
  handle: (input, { sessState, sessionId, dir, logPath, lockPath }) => {
    if (input.tool_name) {
      handlePostToolUse(input, sessState, sessionId, dir, logPath, lockPath);
      return null;
    }
    return handleUserPromptSubmit(sessState);
  },
});
process.exit(0);
