#!/usr/bin/env node
'use strict';
// SessionStart — inject the live checkpoint + lessons index, and (global
// scope only) rotate a checkpoint left behind by an already-ended session.
// See memory/SPEC.md "Automatic triggers" table for the design this follows.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const LESSONS_INDEX_CAP_BYTES = 8000; // pragmatic cap, see memory/SPEC.md's
// tiered-budget scheme for the fuller design this simplifies.

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || null;
  const { scope, base } = lib.resolveScope(cwd);

  const sessionDir = path.join(base, 'session');
  const archiveDir = path.join(sessionDir, 'archive');
  const lessonsIndexPath = path.join(base, 'lessons', 'index.md');
  const cpPath = path.join(sessionDir, 'checkpoint.md');

  // Read-only path: do NOT create sessionDir/.gitignore here. This hook runs
  // on every SessionStart in every repo it's wired into — unconditionally
  // creating a directory (even a gitignored one) as a side effect of a read
  // is a footprint on someone else's repo they never asked for. Only the
  // rotation branch below writes anything, and it ensureDir's its own target.
  const parts = [];

  if (fs.existsSync(cpPath)) {
    const raw = fs.readFileSync(cpPath, 'utf8');
    parts.push('## Claude Harness — previous session checkpoint\n\n' + raw.trim());

    if (scope === 'global') {
      const cp = lib.parseCheckpoint(raw);
      if (cp.session_id && sessionId && cp.session_id !== sessionId) {
        // Belongs to a session that has already ended. SessionEnd is not
        // reliable enough to rotate on (doesn't fire on /exit) — this is
        // the rotation point instead. Already injected above; retire it now
        // so this session's writes start a fresh live checkpoint.
        lib.ensureDir(archiveDir);
        const ts = lib.nowISO().replace(/[:.]/g, '-');
        try {
          fs.copyFileSync(cpPath, path.join(archiveDir, `${ts}.md`));
          fs.unlinkSync(cpPath);
        } catch (_) {
          /* best-effort rotation — a missed rotation just means one stale
             read next session, not data loss */
        }
      }
    }
  }

  if (fs.existsSync(archiveDir)) {
    const files = fs
      .readdirSync(archiveDir)
      .filter((f) => f.endsWith('.md'))
      .sort()
      .reverse()
      .slice(0, 10);
    if (files.length) {
      parts.push(`## Claude Harness — archive index (${archiveDir})\n` + files.map((f) => `- ${f}`).join('\n'));
    }
  }

  if (fs.existsSync(lessonsIndexPath)) {
    let idx = fs.readFileSync(lessonsIndexPath, 'utf8');
    if (Buffer.byteLength(idx, 'utf8') > LESSONS_INDEX_CAP_BYTES) {
      idx = idx.slice(0, LESSONS_INDEX_CAP_BYTES) + `\n... truncated, see ${lessonsIndexPath}`;
    }
    parts.push('## Claude Harness — lessons index\n\n' + idx.trim());
  }

  if (parts.length) {
    const additionalContext = parts.join('\n\n');
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'SessionStart',
          additionalContext,
        },
      })
    );
  }
}

try {
  main();
} catch (_) {
  // Never let a memory-hook failure surface to the user or block session start.
}
process.exit(0);
