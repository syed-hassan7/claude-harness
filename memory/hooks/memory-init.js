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

// Reads an index file, truncating to capBytes with a loud notice (mined from
// NousResearch/hermes-agent's fail-on-overflow memory tool, 2026-08-11) --
// say what got cut and how much, don't just point at the file and let the
// agent discover the gap.
function readIndexCapped(idxPath, capBytes) {
  let idx = fs.readFileSync(idxPath, 'utf8');
  if (Buffer.byteLength(idx, 'utf8') > capBytes) {
    const kept = idx.slice(0, capBytes);
    const droppedLines = idx
      .slice(capBytes)
      .split('\n')
      .filter((l) => l.trim().length).length;
    idx = kept + `\n... truncated: ${droppedLines} older entr${droppedLines === 1 ? 'y' : 'ies'} cut, see ${idxPath}`;
  }
  return idx;
}

// How far back the hook-error rollup below looks. Long enough that a failure
// which only fires on PreCompact or SessionEnd is still visible next session,
// short enough that a fixed problem stops being reported.
const HOOK_ERROR_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const sessionId = input.session_id || null;
  const { scope, base } = lib.resolveScope(cwd, sessionId);

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

    // Empty-`goal` nudge. `goal`/`next` are agent-written by design (see
    // _lib.js's header: a PostToolUse hook only sees tool_input, never
    // conversation content, so it cannot infer intent) -- and in practice they
    // go unwritten. WORKFLOW.md's Understand section predicts this exact
    // failure in its own text, and the 2026-08-27 external audit then found a
    // real injected checkpoint with `goal:` blank and nothing but two
    // filenames under `files:` (finding #2). The rule existed with zero
    // backstop, which is the criteria for mechanizing.
    //
    // Deliberately surfaced HERE rather than as a new nudge hook: this is the
    // one moment the agent is looking straight at the thin checkpoint and
    // establishing what the session is about, it reuses a read that already
    // happens, and it needs no new settings.json wiring (an upgrade cost this
    // pack has already paid twice). It cannot retroactively fill the previous
    // session's goal -- nothing can -- it breaks the habit loop that produced
    // the empty field.
    const prev = lib.parseCheckpoint(raw);
    if (!String(prev.goal || '').trim()) {
      parts.push(
        '## Claude Harness — checkpoint had no `goal`\n\n' +
          'The checkpoint above was written with an empty `goal:` field, so it cannot answer ' +
          '"what were we doing" — only which files were touched. `goal`/`next` are never ' +
          'hook-written (see `memory/SPEC.md`); the agent edits them directly. Write ' +
          `\`goal:\` into \`${cpPath}\` as soon as this session's objective is clear, and ` +
          '`next:` before it ends.'
      );
    }

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
        } catch (err) {
          /* best-effort rotation — a missed rotation just means one stale
             read next session, not data loss */
          lib.recordHookError(err, `rotating ${cpPath} into ${archiveDir}`);
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
    const idx = readIndexCapped(lessonsIndexPath, LESSONS_INDEX_CAP_BYTES);
    const lessonsNonEmpty = idx.trim().length > 0;
    parts.push('## Claude Harness — lessons index\n\n' + idx.trim());

    // Lesson-promotion review nudge (memory/SPEC.md "Lesson-promotion memory").
    // Folded into this block, not a new hook file -- it reuses the read/
    // existence check just above rather than a second SessionStart
    // registration and a second settings.json wiring entry. Read-only: this
    // never writes promotion/state.json -- see WORKFLOW.md's promotion
    // ritual for the agent-authored write side.
    if (lessonsNonEmpty) {
      try {
        const promotionStatePath = path.join(base, 'promotion', 'state.json');
        let lastReviewedAt = null;
        if (fs.existsSync(promotionStatePath)) {
          try {
            const state = JSON.parse(fs.readFileSync(promotionStatePath, 'utf8'));
            lastReviewedAt = state && typeof state.lastReviewedAt === 'string' ? state.lastReviewedAt : null;
          } catch (err) {
            /* malformed state file -- treat as never-reviewed (fail toward
               nudging, not toward silence), never block SessionStart over it */
            lib.recordHookError(err, `malformed ${promotionStatePath}`);
          }
        }
        // NaN-safe by construction: Date.parse of a missing/malformed watermark
        // is NaN, and `indexMtimeMs > NaN` is false in JS -- which would read a
        // corrupt watermark as "already reviewed," the wrong failure direction
        // for a nudge whose only cost is one skippable line. Explicit
        // Number.isFinite check instead of trusting the comparison's own NaN behavior.
        const lastReviewedMs = lastReviewedAt ? Date.parse(lastReviewedAt) : NaN;
        const indexMtimeMs = fs.statSync(lessonsIndexPath).mtimeMs;
        const needsReview = !Number.isFinite(lastReviewedMs) || indexMtimeMs > lastReviewedMs;
        if (needsReview) {
          const msg =
            'Lessons changed since the last promotion-review pass. Classify each lesson ' +
            '(or cluster): short cross-cutting rule -> rules/*.md; multi-step behavior -> ' +
            'skills/manifest.yaml; structural fact, not a correction -> an architecture-note ' +
            "instead; coincidental/not-yet-durable -> leave as-is. See WORKFLOW.md's promotion " +
            'ritual and memory/SPEC.md\'s "Lesson-promotion memory" section.';
          parts.push('## Claude Harness — lesson promotion review\n\n' + msg);
        }
      } catch (err) {
        lib.recordHookError(err, 'lesson-promotion review nudge');
        // A transient stat/read failure here (e.g. the index file vanishing
        // between the readFileSync above and this statSync -- external
        // delete, AV scan, a sync-engine lock) must never abort main(): the
        // checkpoint/archive-index/lessons-index text already queued into
        // `parts` would be lost too, not just this nudge. Fail toward
        // skipping the nudge, never toward losing everything already built.
      }
    }
  }

  // Project-architecture memory: ambient index injection, see memory/SPEC.md's
  // "Recall" section. Full-note recall on a message/file match happens
  // separately in memory-recall.js (UserPromptSubmit) and
  // memory-architecture.js (PostToolUse) -- this block only injects the
  // compact one-line-per-note index so the agent knows what exists.
  function injectArchIndex(label, idxPath, capBytes) {
    if (!fs.existsSync(idxPath)) return;
    const idx = readIndexCapped(idxPath, capBytes);
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

  // Drift-canary rollup (memory/SPEC.md "Canary-drift memory") -- only
  // surfaces when there's something open. A "0 misses, all clear" banner
  // every session is noise that doesn't change what the agent does next;
  // silence when clean, same context-economy audit rule as everything else
  // this hook injects.
  const canaryStatePath = path.join(base, 'canary', 'state.json');
  if (fs.existsSync(canaryStatePath)) {
    try {
      const canaryState = JSON.parse(fs.readFileSync(canaryStatePath, 'utf8'));
      const openCount = Object.values(canaryState).filter((s) => s && s.pending).length;
      if (openCount) {
        const canaryLogPath = path.join(base, 'canary', 'log.md');
        parts.push(
          `## Claude Harness — drift canary\n\n${openCount} open naming-miss${openCount === 1 ? '' : 'es'} across recent sessions — see ${canaryLogPath}`
        );
      }
    } catch (err) {
      /* malformed state file -- skip the rollup, never block SessionStart over
         it. Recorded: a corrupt canary state silently disables the rollup,
         which reads identically to "no open misses" -- the reassuring answer. */
      lib.recordHookError(err, `malformed ${canaryStatePath}`);
    }
  }

  // Hook-error rollup -- the read side of _lib.js's diagnostics channel. Every
  // hook here is fail-open by contract, so a hook that throws on every single
  // invocation produces exactly the same user-visible result as one with
  // nothing to do: silence. This is the one place per session that says
  // otherwise. Silent when clean, same context-economy rule as the canary
  // rollup above.
  const hookErrors = lib.readRecentHookErrors(HOOK_ERROR_WINDOW_MS);
  if (hookErrors.count) {
    parts.push(
      `## Claude Harness — memory hook errors\n\n` +
        `${hookErrors.count} hook error${hookErrors.count === 1 ? '' : 's'} recorded in the last 7 days — memory/gate hooks fail open, so some of this session's memory may be silently missing. Full log: ${hookErrors.path}\n\n` +
        `Most recent: ${hookErrors.latest}`
    );
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
} catch (err) {
  // Never let a memory-hook failure surface to the user or block session start.
  // Recorded so the next session's rollup above can report it -- including a
  // failure of this hook itself.
  lib.recordHookError(err, 'memory-init failed');
}
process.exit(0);
