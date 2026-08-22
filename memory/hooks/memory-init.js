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

// Project-architecture memory index caps -- see memory/SPEC.md's "Recall"
// section. Project cap matches the lessons precedent; the global/cross-project
// cap is deliberately smaller because it's paid unconditionally in EVERY
// session, project or global, regardless of whether that task needs
// cross-project recall at all.
const PROJECT_ARCH_CAP_BYTES = 8000;
const GLOBAL_ARCH_CAP_BYTES = 2000;

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
      const kept = idx.slice(0, LESSONS_INDEX_CAP_BYTES);
      const droppedLines = idx
        .slice(LESSONS_INDEX_CAP_BYTES)
        .split('\n')
        .filter((l) => l.trim().length).length;
      // Loud, not silent (mined from NousResearch/hermes-agent's fail-on-
      // overflow memory tool, 2026-08-11) — say what got cut and how much,
      // don't just point at the file and let the agent discover the gap.
      idx = kept + `\n... truncated: ${droppedLines} older entr${droppedLines === 1 ? 'y' : 'ies'} cut, see ${lessonsIndexPath}`;
    }
    parts.push('## Claude Harness — lessons index\n\n' + idx.trim());
  }

  // Project-architecture memory: ambient index injection, see memory/SPEC.md's
  // "Recall" section. Full-note recall on a message/file match happens
  // separately in memory-recall.js (UserPromptSubmit) and
  // memory-architecture.js (PostToolUse) -- this block only injects the
  // compact one-line-per-note index so the agent knows what exists.
  function injectArchIndex(label, idxPath, capBytes) {
    if (!fs.existsSync(idxPath)) return;
    let idx = fs.readFileSync(idxPath, 'utf8');
    if (Buffer.byteLength(idx, 'utf8') > capBytes) {
      const kept = idx.slice(0, capBytes);
      const droppedLines = idx
        .slice(capBytes)
        .split('\n')
        .filter((l) => l.trim().length).length;
      idx = kept + `\n... truncated: ${droppedLines} older entr${droppedLines === 1 ? 'y' : 'ies'} cut, see ${idxPath}`;
    }
    parts.push(`## Claude Harness — ${label}\n\n${idx.trim()}`);
  }

  const archIndexPath = path.join(base, 'architecture', 'index.md');
  if (scope === 'project') {
    injectArchIndex('project architecture index', archIndexPath, PROJECT_ARCH_CAP_BYTES);
    const homeArchIndexPath = path.join(lib.homeDir(), '.claude', 'architecture', 'index.md');
    injectArchIndex('cross-project architecture index', homeArchIndexPath, GLOBAL_ARCH_CAP_BYTES);
  } else {
    // Global scope: base already IS the home dir -- one index, one injection,
    // larger cap since there's no separate project-scoped file to split cost with.
    injectArchIndex('architecture index', archIndexPath, PROJECT_ARCH_CAP_BYTES);
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
