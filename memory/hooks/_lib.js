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
  try {
    if (process.stdin.isTTY) return {};
    const raw = fs.readFileSync(0, 'utf8').trim();
    return raw ? JSON.parse(raw) : {};
  } catch (_) {
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
    } catch (_) {
      /* best-effort */
    }
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
      if (err.code !== 'EEXIST') return false;
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
  } catch (_) {
    /* already gone — fine */
  }
}

// Write-to-temp-then-rename in the SAME directory as the target, so the
// rename is a same-volume atomic replace on both POSIX and Windows (Node's
// fs.renameSync uses MoveFileExW w/ MOVEFILE_REPLACE_EXISTING on Windows,
// not a shell `mv` — the Git-Bash-`mv`-under-contention caveat in
// memory/SPEC.md does not apply to this code path; verified empirically,
// see memory/hooks/test/concurrency.md).
function atomicWrite(filePath, content) {
  const dir = path.dirname(filePath);
  const tmp = path.join(dir, `.${path.basename(filePath)}.tmp.${process.pid}.${Math.random().toString(36).slice(2)}`);
  fs.writeFileSync(tmp, content, 'utf8');
  fs.renameSync(tmp, filePath);
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

module.exports = {
  readHookInput,
  walkForGitRoot,
  resolveScope,
  ensureDir,
  ensureGitignore,
  stripSecrets,
  nowISO,
  acquireLock,
  releaseLock,
  atomicWrite,
  withLock,
  parseCheckpoint,
  serializeCheckpoint,
};
