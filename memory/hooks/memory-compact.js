#!/usr/bin/env node
'use strict';
// PreCompact — archive the live checkpoint before Claude Code compacts, then
// leave a compressed summary in place. Trim policy per memory/SPEC.md:
// project keeps last 10 / 7 days, global keeps only the archive entry just
// written (last-session-only design).

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const PROJECT_KEEP_COUNT = 10;
const PROJECT_KEEP_DAYS = 7;
const MAX_FILES_IN_SUMMARY = 20;

function trimProjectArchive(archiveDir) {
  const files = fs
    .readdirSync(archiveDir)
    .filter((f) => f.endsWith('.md'))
    .map((f) => ({ f, full: path.join(archiveDir, f), mtime: fs.statSync(path.join(archiveDir, f)).mtimeMs }))
    // Filename tiebreak keeps eviction deterministic when mtimes collide at
    // millisecond precision -- archive names are ISO timestamps, so
    // lexicographic order matches chronological order.
    .sort((a, b) => b.mtime - a.mtime || b.f.localeCompare(a.f));

  const cutoff = Date.now() - PROJECT_KEEP_DAYS * 24 * 60 * 60 * 1000;
  files.forEach((entry, i) => {
    const tooOld = entry.mtime < cutoff;
    const tooMany = i >= PROJECT_KEEP_COUNT;
    if (tooOld || tooMany) {
      try {
        fs.unlinkSync(entry.full);
      } catch (_) {
        /* best-effort trim */
      }
    }
  });
}

function trimGlobalArchive(archiveDir, justWritten) {
  const files = fs.readdirSync(archiveDir).filter((f) => f.endsWith('.md') && f !== justWritten);
  for (const f of files) {
    try {
      fs.unlinkSync(path.join(archiveDir, f));
    } catch (_) {
      /* best-effort trim */
    }
  }
}

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const { scope, base } = lib.resolveScope(cwd);

  const sessionDir = path.join(base, 'session');
  const cpPath = path.join(sessionDir, 'checkpoint.md');
  if (!fs.existsSync(cpPath)) return;

  const archiveDir = path.join(sessionDir, 'archive');
  const lockPath = path.join(sessionDir, '.checkpoint.lock');
  lib.ensureDir(archiveDir);

  lib.withLock(lockPath, () => {
    const raw = fs.readFileSync(cpPath, 'utf8');
    const ts = lib.nowISO().replace(/[:.]/g, '-');
    const archiveName = `${ts}.md`;
    fs.writeFileSync(path.join(archiveDir, archiveName), raw, 'utf8');

    if (scope === 'project') trimProjectArchive(archiveDir);
    else trimGlobalArchive(archiveDir, archiveName);

    const cp = lib.parseCheckpoint(raw);
    cp.updated = lib.nowISO();
    if (cp.files.length > MAX_FILES_IN_SUMMARY) {
      cp.files = cp.files.slice(cp.files.length - MAX_FILES_IN_SUMMARY);
    }
    lib.atomicWrite(cpPath, lib.serializeCheckpoint(cp));
  });
}

try {
  main();
} catch (_) {
  // Fail open — a broken archive pass must never block Claude Code's compact.
}
process.exit(0);
