'use strict';
// Shared helpers for Claude Harness memory hooks. Zero external dependencies —
// this pack is plain files + stdlib, no daemon, no database (see README).
//
// Known simplification vs memory/SPEC.md's full ambition, stated here rather
// than silently: PostToolUse hooks only receive tool_input, not conversation
// content, so `goal`/`next`/`decisions` are NOT auto-refreshed from "recent
// assistant intent" the way the SPEC.md pseudocode sketches — that would
// require parsing the transcript on every single edit, which is real risk on
// the hottest-path hook in this repo. This implementation mechanically keeps
// `files` and `updated` fresh; `goal`/`next`/`decisions`/`blockers` are meant
// to be edited by the agent directly when something material changes.

const fs = require('fs');
const path = require('path');
const os = require('os');

function readHookInput() {
  let raw;
  try {
    if (process.stdin.isTTY) return {};
    raw = fs.readFileSync(0, 'utf8').trim();
  } catch (err) {
    recordHookError(err, 'reading hook stdin');
    return {};
  }
  if (!raw) return {}; // no payload at all -- normal for a manual/TTY-less run
  try {
    return JSON.parse(raw);
  } catch (err) {
    // An unparseable payload is not the same thing as an empty one: if Claude
    // Code's hook payload shape ever changes, EVERY hook here degrades into a
    // silent no-op that is indistinguishable from "nothing to do". Still fail
    // open with {}, but leave a trace first.
    recordHookError(err, 'unparseable hook payload');
    return {};
  }
}

// CLAUDE_HARNESS_HOME_OVERRIDE lets tests point global scope at a scratch dir
// instead of the real home directory. Unset in normal use.
function homeDir() {
  return process.env.CLAUDE_HARNESS_HOME_OVERRIDE || os.homedir();
}

// Never walks past (or counts) the home directory itself. Found the hard way:
// a git-tracked home directory (dotfiles-as-repo — yadm, chezmoi, bare `git
// init ~`, all common) would otherwise make every single global-scope session
// anywhere on disk resolve as "project scope, repo: <home dir name>" once the
// walk reached ~/.git, silently collapsing the global/project distinction
// this whole memory layer exists to make.
function walkForGitRoot(startDir) {
  const home = path.resolve(homeDir());
  let dir = path.resolve(startDir);
  for (;;) {
    if (dir !== home && fs.existsSync(path.join(dir, '.git'))) return dir;
    if (dir === home) return null;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

// Returns { scope: 'project'|'global', base: <dir containing session/ and lessons/>, repo: <name or null> }
function resolveScope(cwd) {
  const root = walkForGitRoot(cwd || process.cwd());
  if (root) {
    return { scope: 'project', base: path.join(root, '.claude'), repo: path.basename(root) };
  }
  return { scope: 'global', base: path.join(homeDir(), '.claude'), repo: null };
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function ensureGitignore(dir) {
  const gi = path.join(dir, '.gitignore');
  if (!fs.existsSync(gi)) {
    try {
      fs.writeFileSync(gi, '*\n!.gitignore\n');
    } catch (err) {
      recordHookError(err, `writing ${gi}`);
    }
  }
}

// ---- Diagnostics channel.
//
// Every hook in this directory ends in a fail-open catch, and that posture is
// correct -- a broken memory hook must never block an Edit/Write or a prompt.
// Fail-open is not the same thing as fail-silent, though: a hook that throws
// on every single invocation (unwritable ~/.claude, corrupt state, a payload
// shape that changed under us) looks exactly like a hook with nothing to do,
// forever. Same failure class as the dead gates 6.4.0's audit found, one
// level down. So every catch that used to swallow an error now records one
// bounded line here, and memory-init.js surfaces the count at SessionStart.
//
// Always the HOME scope, never the project's .claude/ -- project scope is
// resolved from cwd, and cwd resolution is one of the things that can fail;
// dropping a diagnostics directory into someone's repo as a side effect of a
// failure is the footprint memory-init.js already refuses to make.
const DIAGNOSTICS_MAX_BYTES = 64 * 1024;
const DIAGNOSTICS_KEEP_LINES = 200;

function diagnosticsLogPath() {
  return path.join(homeDir(), '.claude', 'diagnostics', 'hook-errors.log');
}

function trimDiagnosticsLog(logPath) {
  const stat = fs.statSync(logPath);
  if (stat.size <= DIAGNOSTICS_MAX_BYTES) return;
  const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).filter(Boolean);
  const kept = lines.slice(-DIAGNOSTICS_KEEP_LINES);
  atomicWrite(logPath, kept.join('\n') + '\n');
}

// Reentrancy guard: this function's own helpers (ensureDir/ensureGitignore)
// report their failures through this same function, which would recurse
// forever on an unwritable home directory -- the exact case where it is most
// likely to fail.
let recordingHookError = false;

// Never throws: callers are already on their failure path, and a diagnostics
// write that raised would convert a survivable error into the crash the
// fail-open catch exists to prevent.
function recordHookError(err, context) {
  if (recordingHookError) return;
  recordingHookError = true;
  try {
    const logPath = diagnosticsLogPath();
    ensureDir(path.dirname(logPath));
    ensureGitignore(path.dirname(logPath));
    const hook = path.basename(process.argv[1] || 'unknown');
    const detail = err && err.stack ? String(err.stack).split(/\r?\n/).slice(0, 2).join(' -- ') : String(err);
    const line = `${nowISO()} | ${hook} | ${context || 'no context'} | ${stripSecrets(detail).replace(/\s+/g, ' ')}`;
    fs.appendFileSync(logPath, line + '\n');
    trimDiagnosticsLog(logPath);
  } catch (_) {
    // End of the line: the diagnostics channel itself is unavailable (read-only
    // home, disk full). There is nowhere left to escalate to that wouldn't
    // break the tool call this hook is not allowed to break.
  } finally {
    recordingHookError = false;
  }
}

// Rollup for memory-init.js's SessionStart injection -- the read side of the
// channel above. Silent when clean, same context-economy rule as the canary
// rollup it sits next to.
function readRecentHookErrors(windowMs) {
  const logPath = diagnosticsLogPath();
  let raw;
  try {
    raw = fs.readFileSync(logPath, 'utf8');
  } catch (_) {
    return { count: 0, path: logPath, latest: null };
  }
  const cutoff = Date.now() - windowMs;
  const recent = raw
    .split(/\r?\n/)
    .filter(Boolean)
    .filter((line) => {
      const at = Date.parse(line.split('|')[0].trim());
      // An unparseable leading timestamp counts as recent rather than being
      // dropped -- an error record is exactly the wrong thing to discard
      // because its own formatting is suspect.
      return !Number.isFinite(at) || at >= cutoff;
    });
  return { count: recent.length, path: logPath, latest: recent.length ? recent[recent.length - 1] : null };
}

// Moves a file whose contents can't be parsed aside under a single fixed name
// (no timestamp -- one quarantine slot per file, so this can't grow without
// bound) instead of letting the caller's next write silently overwrite it.
function quarantineCorruptFile(filePath) {
  try {
    fs.renameSync(filePath, `${filePath}.corrupt`);
    return `${filePath}.corrupt`;
  } catch (err) {
    recordHookError(err, `quarantining ${filePath}`);
    return null;
  }
}

const SECRET_PATTERNS = [
  /AKIA[0-9A-Z]{16}/g,
  /(?:aws)?[_-]?secret[_-]?access[_-]?key\s*[=:]\s*['"]?[A-Za-z0-9/+=]{40}/gi,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g,
  /ghp_[A-Za-z0-9]{36,}/g,
  /(?:api[_-]?key|password|secret)\s*[=:]\s*['"][^'"\s]{8,}['"]/gi,
];

function stripSecrets(text) {
  if (typeof text !== 'string') return text;
  let out = text;
  for (const re of SECRET_PATTERNS) out = out.replace(re, '[REDACTED]');
  return out;
}

function nowISO() {
  return new Date().toISOString();
}

// "git" and "commit" in the same clause, unbroken by a chain separator
// (&, |, ;) -- so `git status && docker commit foo` does not false-match.
// Text pattern, not a tool_response exit-code check: reading tool_response
// would cross a line audit-log/SECURITY_SPEC.md already draws deliberately
// for hook design (never consult tool_response). Best-effort classification,
// not reliable capture -- same class of limitation SECURITY_SPEC.md already
// accepts for its own Bash coverage. Shared by review-gate-check.js and
// design-lane-gate-check.js -- both treat a commit as their crisp trigger.
const GIT_COMMIT_RE = /\bgit\b[^&|;\n]*\bcommit\b/i;
function isGitCommitCommand(command) {
  return GIT_COMMIT_RE.test(command || '');
}

// Reads only the bytes appended since `sinceOffset`, stopping at the last
// complete line -- a transcript write mid-flush must never be parsed as a
// truncated JSON line. Returns the unchanged offset (not `size`) when no
// complete line is available yet, so the partial tail is retried next time.
// Shared by canary-check.js and review-gate-check.js -- both scan a
// transcript incrementally against a per-session byte offset.
function readTranscriptSince(transcriptPath, sinceOffset) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return { lines: [], newOffset: sinceOffset };
  const size = fs.statSync(transcriptPath).size;
  if (size <= sinceOffset) return { lines: [], newOffset: size < sinceOffset ? 0 : sinceOffset };
  const fd = fs.openSync(transcriptPath, 'r');
  let chunk;
  try {
    const len = size - sinceOffset;
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, sinceOffset);
    chunk = buf.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
  const lastNewline = chunk.lastIndexOf('\n');
  if (lastNewline === -1) return { lines: [], newOffset: sinceOffset };
  const usable = chunk.slice(0, lastNewline + 1);
  const newOffset = sinceOffset + Buffer.byteLength(usable, 'utf8');
  return { lines: usable.split('\n').filter(Boolean), newOffset };
}

// Bounded synchronous sleep. Avoids Atomics.wait (main-thread portability
// unverified across Node versions) in favor of a plain busy-wait — wasteful
// per-millisecond but capped tightly (see acquireLock's maxWaitMs) so total
// cost stays negligible against a single Edit/Write.
function sleepMs(ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    /* bounded busy-wait */
  }
}

// O_CREAT|O_EXCL lock with a stale-lock timeout, per memory/SPEC.md's
// concurrency section. Returns true if the lock was acquired, false if not
// (caller must treat false as "skip this write", never as "block forever" —
// this hook must stay cheap on every single Edit/Write).
function acquireLock(lockPath, { staleMs = 10000, maxWaitMs = 250, retryDelayMs = 20 } = {}) {
  const start = Date.now();
  for (;;) {
    try {
      const fd = fs.openSync(lockPath, 'wx');
      fs.writeSync(fd, String(process.pid));
      fs.closeSync(fd);
      return true;
    } catch (err) {
      if (err.code !== 'EEXIST') {
        // Not contention -- the lock file itself can't be created (unwritable
        // directory, missing parent). Returning false here means every write
        // this lock guards is skipped for as long as the condition lasts, so
        // it can't stay silent.
        recordHookError(err, `acquiring lock ${lockPath}`);
        return false;
      }
      try {
        const stat = fs.statSync(lockPath);
        if (Date.now() - stat.mtimeMs > staleMs) {
          fs.unlinkSync(lockPath);
          continue;
        }
      } catch (_) {
        continue;
      }
      if (Date.now() - start > maxWaitMs) return false;
      sleepMs(retryDelayMs);
    }
  }
}

function releaseLock(lockPath) {
  try {
    fs.unlinkSync(lockPath);
  } catch (err) {
    // Already gone is fine. Anything else means the lock stays held until its
    // stale timeout expires, blocking every write in between -- worth a line.
    if (err.code !== 'ENOENT') recordHookError(err, `releasing lock ${lockPath}`);
  }
}

// Write-to-temp-then-rename in the SAME directory as the target, so the
// rename is a same-volume atomic replace on both POSIX and Windows (Node's
// fs.renameSync uses MoveFileExW w/ MOVEFILE_REPLACE_EXISTING on Windows,
// not a shell `mv` — the Git-Bash-`mv`-under-contention caveat in
// memory/SPEC.md does not apply to this code path; verified empirically,
// see memory/hooks/test/run.sh, Test 12).
function atomicWrite(filePath, content) {
  const dir = path.dirname(filePath);
  const tmp = path.join(dir, `.${path.basename(filePath)}.tmp.${process.pid}.${Math.random().toString(36).slice(2)}`);
  try {
    fs.writeFileSync(tmp, content, 'utf8');
    fs.renameSync(tmp, filePath);
  } catch (err) {
    // A failed rename used to leave the scratch file behind forever, under a
    // name nothing ever reads or cleans up (the suite asserts no leftovers
    // after contention -- see test/run.sh Test 12). Clean up, then rethrow:
    // deciding what a failed write means is the caller's fail-open catch's
    // job, not this function's.
    try {
      fs.unlinkSync(tmp);
    } catch (_) {
      /* nothing written, or already gone */
    }
    throw err;
  }
}

function withLock(lockPath, fn) {
  const got = acquireLock(lockPath);
  if (!got) return false;
  try {
    fn();
    return true;
  } finally {
    releaseLock(lockPath);
  }
}

const LIST_FIELDS = ['done', 'next', 'files', 'decisions', 'blockers'];
const SCALAR_FIELDS = ['scope', 'repo', 'session_id', 'updated', 'goal'];

function parseCheckpoint(text) {
  const cp = { scope: '', repo: '', session_id: '', updated: '', goal: '' };
  for (const f of LIST_FIELDS) cp[f] = [];
  if (!text) return cp;
  let currentList = null;
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine;
    if (line.startsWith('#')) continue;
    const scalarMatch = line.match(/^([a-z_]+):\s*(.*)$/i);
    const listItemMatch = line.match(/^\s*-\s*(.*)$/);
    if (listItemMatch && currentList) {
      cp[currentList].push(listItemMatch[1].trim());
      continue;
    }
    if (scalarMatch) {
      const key = scalarMatch[1].toLowerCase();
      const val = scalarMatch[2].trim();
      if (LIST_FIELDS.includes(key)) {
        currentList = key;
        continue;
      }
      if (SCALAR_FIELDS.includes(key)) {
        cp[key] = val;
        currentList = null;
      }
    }
  }
  return cp;
}

function serializeCheckpoint(cp) {
  const lines = ['# Session checkpoint'];
  for (const f of SCALAR_FIELDS) lines.push(`${f}: ${cp[f] || ''}`);
  for (const f of LIST_FIELDS) {
    const items = cp[f] || [];
    if (!items.length) continue;
    lines.push(`${f}:`);
    for (const item of items) lines.push(`  - ${item}`);
  }
  return lines.join('\n') + '\n';
}

// ---- Project-architecture memory (memory/SPEC.md's "Project-architecture
// memory" section) -- shared by memory-init.js, memory-recall.js, and
// memory-architecture.js. Index line format: "[STALE?] id | project | tags |
// summary | path", one per note, flat file at <base>/architecture/index.md.

function parseArchIndexLine(line) {
  const trimmed = (line || '').trim();
  if (!trimmed) return null;
  const stale = trimmed.startsWith('[STALE?]');
  const body = stale ? trimmed.replace(/^\[STALE\?\]\s*/, '') : trimmed;
  const parts = body.split('|').map((p) => p.trim());
  if (parts.length < 5) return null;
  const [id, project, tags, summary, notePath] = parts;
  if (!id) return null;
  return { id, project, tags, summary, path: notePath, stale };
}

function readArchIndexEntries(indexPath) {
  if (!fs.existsSync(indexPath)) return [];
  return fs
    .readFileSync(indexPath, 'utf8')
    .split(/\r?\n/)
    .map(parseArchIndexLine)
    .filter(Boolean);
}

// Literal, case-insensitive substring match against an entry's tags/project
// columns -- the mechanical recall rule from SPEC.md, deliberately not
// semantic/prose judgment (that's the whole point of this store vs #3's
// existing "agent happened to notice the description" recall).
function architectureEntryMatches(entry, text) {
  if (!text) return false;
  const hay = text.toLowerCase();
  const needles = `${entry.project},${entry.tags}`
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 1);
  return needles.some((n) => hay.includes(n));
}

// Plain line-scan, not a regex spanning the whole body -- avoids JS regex's
// lack of a portable "end of string" anchor across engines.
function extractSection(body, header) {
  const lines = (body || '').split(/\r?\n/);
  const startIdx = lines.findIndex((l) => l.trim() === `## ${header}`);
  if (startIdx === -1) return '';
  let end = lines.length;
  for (let i = startIdx + 1; i < lines.length; i++) {
    if (/^##\s+/.test(lines[i])) {
      end = i;
      break;
    }
  }
  return lines
    .slice(startIdx + 1, end)
    .join('\n')
    .trim();
}

function readWatchMap(base) {
  const p = path.join(base, 'architecture', 'watch-map.json');
  let raw;
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch (err) {
    // No watch map at all is the normal state for an untracked repo.
    if (err.code !== 'ENOENT') recordHookError(err, `reading ${p}`);
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') throw new Error('watch-map.json is not an object');
    return parsed;
  } catch (err) {
    // A hand-edited watch map that no longer parses silently disables every
    // file-touch recall and every staleness flag in the repo -- the agent
    // just stops seeing architecture notes, with no signal that it should.
    recordHookError(err, `malformed ${p} -- file-touch recall disabled until fixed`);
    return {};
  }
}

// Prefixes the matching index line with "[STALE?] " (idempotent -- no-op if
// already prefixed). Caller is responsible for holding the architecture lock;
// this function only does the read-modify-write, same division of concerns
// as atomicWrite/withLock above.
function flagIndexLineStale(indexPath, noteId) {
  if (!fs.existsSync(indexPath)) return false;
  const lines = fs.readFileSync(indexPath, 'utf8').split(/\r?\n/);
  let changed = false;
  const out = lines.map((line) => {
    if (!line.trim() || line.startsWith('[STALE?]')) return line;
    const parsed = parseArchIndexLine(line);
    if (parsed && parsed.id === noteId) {
      changed = true;
      return '[STALE?] ' + line.trim();
    }
    return line;
  });
  if (changed) atomicWrite(indexPath, out.join('\n'));
  return changed;
}

// ---- Gate-hook scaffolding, shared by canary-check.js/review-gate-check.js/
// design-lane-gate-check.js/visual-plan-gate-check.js. All 4 independently
// duplicated this exact shape (own state dir under <base>/<gateName>/, own
// readJSON/appendLog/pruneIdle/final-write) before this consolidation --
// extracted here instead of left duplicated a 5th time for the next gate.

function gatePaths(base, gateName) {
  const dir = path.join(base, gateName);
  return {
    dir,
    statePath: path.join(dir, 'state.json'),
    logPath: path.join(dir, 'log.md'),
    lockPath: path.join(dir, '.lock'),
  };
}

function readGateState(statePath) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch (err) {
    if (err.code !== 'ENOENT') recordHookError(err, `reading ${statePath}`);
    return {};
  }
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') throw new Error('gate state is not an object');
    return parsed;
  } catch (err) {
    // Corrupt state used to collapse into {} and then get overwritten by this
    // call's own writeGateState -- every unresolved miss in it gone, with no
    // EXPIRED line and no trace, which is precisely what pruneIdleGateSessions'
    // EXPIRED lines exist to prevent. Move the bytes aside and say so.
    const kept = quarantineCorruptFile(statePath);
    recordHookError(err, `corrupt gate state ${statePath}${kept ? ` (kept at ${kept})` : ''}`);
    return {};
  }
}

function appendGateLog(dir, logPath, lockPath, lines) {
  if (!lines || !lines.length) return;
  ensureDir(dir);
  ensureGitignore(dir);
  const payload = lines.join('\n') + '\n';
  const wrote = withLock(lockPath, () => {
    fs.appendFileSync(logPath, payload);
  });
  if (wrote) return;
  // Contention: skipping is the right call for state.json (the next tool call
  // rewrites it), but a MISS/EXPIRED line has no next chance -- dropping it
  // silently loses the miss instead of closing it out. A single appendFileSync
  // opens with O_APPEND, so a concurrent hook's line can interleave with this
  // one but cannot corrupt it; that's strictly better than no line at all.
  try {
    fs.appendFileSync(logPath, payload);
  } catch (err) {
    recordHookError(err, `appending to ${logPath}`);
  }
}

function writeGateState(dir, statePath, lockPath, state) {
  ensureDir(dir);
  ensureGitignore(dir);
  const wrote = withLock(lockPath, () => {
    atomicWrite(statePath, JSON.stringify(state));
  });
  // Dropping a state write silently means the sticky flags this call just
  // computed (reviewSeen, uiTouched, a fresh pending miss) never happened, and
  // the gate quietly under-reports from here on. Not worth blocking a tool
  // call over -- worth one line.
  if (!wrote) recordHookError(new Error(`lock contended: ${lockPath}`), `gate state write skipped: ${statePath}`);
}

// Generic idle-session prune: any session whose lastSeen is older than ttlMs
// is dropped. `pendingFields` lists the state keys that count as "an
// unresolved miss" -- each still-truthy field on a pruned session gets one
// EXPIRED line via `describeExpired(sessionId, fieldName, sessState)`, so the
// audit trail never silently loses a miss instead of closing it out.
function pruneIdleGateSessions(state, dir, logPath, lockPath, { ttlMs, pendingFields, describeExpired }) {
  const cutoff = Date.now() - ttlMs;
  const expired = [];
  for (const id of Object.keys(state)) {
    const parsed = state[id] && state[id].lastSeen ? Date.parse(state[id].lastSeen) : 0;
    // An unparseable lastSeen has to read as "infinitely idle," not as "never
    // idle": Date.parse returns NaN, and `NaN < cutoff` is false, which made a
    // session with a corrupt timestamp immortal -- its entry never pruned, its
    // pending miss never closed out with an EXPIRED line.
    const seen = Number.isFinite(parsed) ? parsed : 0;
    if (seen < cutoff) {
      for (const field of pendingFields) {
        if (state[id] && state[id][field]) expired.push(describeExpired(id, field, state[id]));
      }
      delete state[id];
    }
  }
  appendGateLog(dir, logPath, lockPath, expired);
}

module.exports = {
  readHookInput,
  recordHookError,
  readRecentHookErrors,
  diagnosticsLogPath,
  quarantineCorruptFile,
  homeDir,
  walkForGitRoot,
  resolveScope,
  ensureDir,
  ensureGitignore,
  stripSecrets,
  nowISO,
  readTranscriptSince,
  isGitCommitCommand,
  acquireLock,
  releaseLock,
  atomicWrite,
  withLock,
  parseCheckpoint,
  serializeCheckpoint,
  parseArchIndexLine,
  readArchIndexEntries,
  architectureEntryMatches,
  extractSection,
  readWatchMap,
  flagIndexLineStale,
  gatePaths,
  readGateState,
  appendGateLog,
  writeGateState,
  pruneIdleGateSessions,
};
