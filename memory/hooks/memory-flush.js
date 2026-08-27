#!/usr/bin/env node
'use strict';
// SessionEnd — best-effort final touch only. Confirmed unreliable: does not
// fire on `/exit` (anthropics/claude-code#35892, closed not_planned). Nothing
// downstream depends on this running; SessionStart's rotation is load-bearing
// instead (see memory-init.js). This exists purely as a nice-to-have for the
// sessions where SessionEnd does fire.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const { base } = lib.resolveScope(cwd, input.session_id);
  const sessionDir = path.join(base, 'session');
  const cpPath = path.join(sessionDir, 'checkpoint.md');
  if (!fs.existsSync(cpPath)) return;

  const lockPath = path.join(sessionDir, '.checkpoint.lock');
  lib.withLock(lockPath, () => {
    const cp = lib.parseCheckpoint(fs.readFileSync(cpPath, 'utf8'));
    cp.updated = lib.nowISO();
    lib.atomicWrite(cpPath, lib.serializeCheckpoint(cp));
  });
}

try {
  main();
} catch (err) {
  // Best-effort by design, but recorded: this is the only hook whose failures
  // nothing downstream would ever notice. See _lib.js's diagnostics note.
  lib.recordHookError(err, 'memory-flush failed');
}
process.exit(0);
