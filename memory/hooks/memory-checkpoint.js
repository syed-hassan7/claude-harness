#!/usr/bin/env node
'use strict';
// PostToolUse (matcher: Edit|Write) — cheap rolling update to the live
// checkpoint. Fires on EVERY Edit/Write, so this must stay fast and must
// never throw past main() — see _lib.js's header note on what this
// mechanically can and can't keep fresh.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const MAX_FILES = 50;

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || null;
  const toolInput = input.tool_input || {};
  const filePath = toolInput.file_path;
  if (!filePath) return; // nothing to record

  const { scope, base, repo } = lib.resolveScope(cwd);
  const sessionDir = path.join(base, 'session');
  lib.ensureDir(sessionDir);
  if (scope === 'project') lib.ensureGitignore(sessionDir);

  const cpPath = path.join(sessionDir, 'checkpoint.md');
  const lockPath = path.join(sessionDir, '.checkpoint.lock');

  const wrote = lib.withLock(lockPath, () => {
    const existing = fs.existsSync(cpPath) ? fs.readFileSync(cpPath, 'utf8') : '';
    const cp = lib.parseCheckpoint(existing);
    cp.scope = scope;
    cp.repo = repo || '';
    cp.session_id = sessionId || cp.session_id || '';
    cp.updated = lib.nowISO();

    const cleanPath = lib.stripSecrets(String(filePath));
    cp.files = cp.files.filter((f) => f !== cleanPath);
    cp.files.push(cleanPath);
    if (cp.files.length > MAX_FILES) cp.files = cp.files.slice(cp.files.length - MAX_FILES);

    lib.atomicWrite(cpPath, lib.serializeCheckpoint(cp));
  });
  // withLock returning false (lock contended) means we skip this cycle's
  // write rather than block the edit that just happened — by design. Still
  // worth a line: one skipped cycle is harmless (the next Edit rewrites it),
  // but a lock nothing ever releases makes the checkpoint quietly stop
  // tracking anything, which is indistinguishable from an idle session.
  if (!wrote) lib.recordHookError(new Error(`lock contended: ${lockPath}`), 'checkpoint write skipped');
}

try {
  main();
} catch (err) {
  // Fail open: a broken checkpoint write must never block an Edit/Write.
  // Recorded rather than swallowed -- a hook that throws on every Edit looks
  // exactly like one with nothing to do. See _lib.js's diagnostics note.
  lib.recordHookError(err, 'memory-checkpoint failed');
}
process.exit(0);
