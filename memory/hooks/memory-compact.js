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

function trimProjectArchive(archiveDir, justWritten) {
  const files = fs
    .readdirSync(archiveDir)
    .filter((f) => f.endsWith('.md'))
    .map((f) => ({ f, full: path.join(archiveDir, f), mtime: fs.statSync(path.join(archiveDir, f)).mtimeMs }))
    // Filename descending breaks mtime ties. Archive names are the ISO
    // timestamp they were written at, so they sort chronologically anyway --
    // and mtime alone is not enough to order them: entries written inside the
    // same filesystem timestamp granularity (or restored by a copy/sync that
    // rewrote mtimes) compared equal, making "which of these is the oldest"
    // depend on readdir order. The count stayed right; WHICH file got evicted
    // didn't.
    .sort((a, b) => b.mtime - a.mtime || b.f.localeCompare(a.f));

  const cutoff = Date.now() - PROJECT_KEEP_DAYS * 24 * 60 * 60 * 1000;
  files.forEach((entry, i) => {
    // The entry this compact just wrote is never a trim candidate -- it is the
    // whole point of the pass, and both rules can otherwise select it (a clock
    // skewed backwards puts it past the day cutoff; an mtime tie can rank it
    // last under the count cap). trimGlobalArchive already exempts it.
    if (entry.f === justWritten) return;
    const tooOld = entry.mtime < cutoff;
    const tooMany = i >= PROJECT_KEEP_COUNT;
    if (tooOld || tooMany) {
      try {
        fs.unlinkSync(entry.full);
      } catch (err) {
        // Best-effort per entry -- one undeletable file must not abort the rest
        // of the trim, and must not abort the compact this hook is riding on.
        // Recorded, because an archive that silently stops obeying its own
        // retention policy grows without bound.
        lib.recordHookError(err, `trimming archive entry ${entry.full}`);
      }
    }
  });
}

function trimGlobalArchive(archiveDir, justWritten) {
  const files = fs.readdirSync(archiveDir).filter((f) => f.endsWith('.md') && f !== justWritten);
  for (const f of files) {
    try {
      fs.unlinkSync(path.join(archiveDir, f));
    } catch (err) {
      lib.recordHookError(err, `trimming global archive entry ${f}`);
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

  const archived = lib.withLock(lockPath, () => {
    const raw = fs.readFileSync(cpPath, 'utf8');
    const ts = lib.nowISO().replace(/[:.]/g, '-');
    const archiveName = `${ts}.md`;
    fs.writeFileSync(path.join(archiveDir, archiveName), raw, 'utf8');

    if (scope === 'project') trimProjectArchive(archiveDir, archiveName);
    else trimGlobalArchive(archiveDir, archiveName);

    const cp = lib.parseCheckpoint(raw);
    cp.updated = lib.nowISO();
    if (cp.files.length > MAX_FILES_IN_SUMMARY) {
      cp.files = cp.files.slice(cp.files.length - MAX_FILES_IN_SUMMARY);
    }
    lib.atomicWrite(cpPath, lib.serializeCheckpoint(cp));
  });
  // Unlike memory-checkpoint.js's skipped cycle, there is no next chance here:
  // the compact proceeds and the pre-compact checkpoint this hook exists to
  // preserve is gone. Still don't block the compact -- just don't lose the fact.
  if (!archived) lib.recordHookError(new Error(`lock contended: ${lockPath}`), 'pre-compact archive skipped');
}

try {
  main();
} catch (err) {
  // Fail open — a broken archive pass must never block Claude Code's compact.
  lib.recordHookError(err, 'memory-compact failed');
}
process.exit(0);
