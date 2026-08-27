#!/usr/bin/env node
'use strict';
// Standalone mechanical check -- NOT a Claude Code hook (no hookSpecificOutput,
// no stdin JSON). Invoked directly by install.sh's --onboard path, by the
// onboarding skill's Bash calls, and by a session that wants to know whether
// this pack's mechanical layer is actually alive RIGHT NOW. Resolves the pack
// dir the exact same way install.sh does (CLAUDE_HARNESS_TARGET override, else
// $HOME/.claude) so a sandboxed test run and a real run check the same thing.
//
// Modes:
//   (default)        static post-install check -- files, config, wiring
//   --live           adds the liveness tier: did each wired hook actually run
//                    in the CURRENT session? This is the falsifiable one.
//   --check-wiring   exit 1 if any hook is unwired / stale-matcher / missing;
//                    used by install.sh instead of its own embedded node
//   --session <id>   pin the --live tier to a specific session id
//   --json           machine-readable
//
// WHY THE LIVE TIER EXISTS. Every defect the 2026-08-27 external audit found
// shared one structural gap: nothing verified that a REAL session invokes these
// hooks the way the unit-test fixtures assume. This verifier was itself part of
// the problem -- it reported all-green through four broken findings, because
// every check it had was file-presence or a settings.json substring match. A
// hook can be present on disk, named in settings.json, and still never run
// (unwired event, stale matcher, syntax error, wrong path). The only evidence
// that distinguishes those is state THIS session's hooks actually wrote.
//
// Falsifiability is the whole point: see onboarding/test/red-demos.sh, which
// breaks each of these checks one at a time against a sandboxed fake install
// and asserts this script goes RED. A checker never shown failing has not been
// shown working.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
// The layout is identical in the repo and under PACK_DIR (install.sh syncs
// caveman/ and onboarding/ side by side), so the runtime resolver is always
// a sibling -- verify checks the exact config path the hooks actually read,
// rather than re-deriving it.
const { getConfigPath: cavemanConfigPath } = require(path.join(__dirname, '..', 'caveman', 'hooks', 'caveman-config.js'));

const ARGV = process.argv.slice(2);
const WANT_LIVE = ARGV.includes('--live');
const WANT_JSON = ARGV.includes('--json');
const WANT_WIRING_EXIT = ARGV.includes('--check-wiring');
const SESSION_OVERRIDE = (() => {
  const i = ARGV.indexOf('--session');
  return i >= 0 ? ARGV[i + 1] : null;
})();

const CLAUDE_DIR = process.env.CLAUDE_HARNESS_TARGET || path.join(os.homedir(), '.claude');
const PACK_DIR = path.join(CLAUDE_DIR, 'claude-harness');
const SETTINGS_PATH = path.join(CLAUDE_DIR, 'settings.json');
const HOME_DIR = process.env.CLAUDE_HARNESS_HOME_OVERRIDE || os.homedir();

// ── Expected hook wiring: the single source of truth for "is this pack wired
// correctly." `tokens` are the tool names a matcher MUST cover; membership, not
// string equality, so reordering `Edit|Write` -> `Write|Edit` is not a failure
// but dropping `Skill` is. That distinction is exactly the 6.4.0 upgrade bug:
// review-gate-check.js's matcher went Bash -> Bash|Skill|Agent, and install.sh
// only ever grepped for the hook's FILENAME, so a stale install got no signal.
// `group` drives opt-in detection: install.sh can install the memory hooks, the
// caveman layer, and the security guard independently, so a group with NO hook
// wired anywhere is "opted out", while a group that is PARTLY wired is broken.
// Without this, a memory-hooks-only install would report every caveman hook as
// UNWIRED and install.sh would reprint its wiring block forever.
const EXPECTED_HOOKS = [
  { file: 'caveman-activate.js', event: 'SessionStart', group: 'caveman' },
  { file: 'memory-init.js', event: 'SessionStart', group: 'memory' },
  { file: 'caveman-mode-tracker.js', event: 'UserPromptSubmit', group: 'caveman' },
  { file: 'memory-recall.js', event: 'UserPromptSubmit', group: 'memory' },
  { file: 'canary-check.js', event: 'UserPromptSubmit', group: 'memory' },
  { file: 'review-gate-check.js', event: 'UserPromptSubmit', group: 'memory' },
  { file: 'design-lane-gate-check.js', event: 'UserPromptSubmit', group: 'memory' },
  { file: 'visual-plan-gate-check.js', event: 'UserPromptSubmit', group: 'memory' },
  { file: 'secret-guard.js', event: 'PreToolUse', group: 'security', tokens: ['Edit', 'Write'] },
  { file: 'memory-checkpoint.js', event: 'PostToolUse', group: 'memory', tokens: ['Edit', 'Write'] },
  { file: 'memory-architecture.js', event: 'PostToolUse', group: 'memory', tokens: ['Read', 'Edit', 'Write'] },
  { file: 'review-gate-check.js', event: 'PostToolUse', group: 'memory', tokens: ['Bash', 'Skill', 'Agent'] },
  { file: 'design-lane-gate-check.js', event: 'PostToolUse', group: 'memory', tokens: ['Edit', 'Write', 'Read', 'Bash'] },
  { file: 'visual-plan-gate-check.js', event: 'PostToolUse', group: 'memory', tokens: ['Edit', 'Write', 'ExitPlanMode'] },
  { file: 'memory-compact.js', event: 'PreCompact', group: 'memory' },
  { file: 'memory-flush.js', event: 'SessionEnd', group: 'memory' },
];

// ── Liveness probes. `every-turn` hooks run on UserPromptSubmit, so by the time
// anything can invoke this script they have already written state for this
// session -- no probe call needed, and a missing entry means genuinely dead.
const LIVE_PROBES = [
  { hook: 'canary-check.js', gate: 'canary', when: 'every-turn' },
  { hook: 'review-gate-check.js', gate: 'review-gate', when: 'every-turn' },
  { hook: 'design-lane-gate-check.js', gate: 'design-lane-gate', when: 'every-turn' },
  { hook: 'visual-plan-gate-check.js', gate: 'visual-plan-gate', when: 'every-turn' },
  { hook: 'memory-checkpoint.js', checkpoint: true, when: 'on-edit-write' },
  // every-turn, not session-start: caveman-mode-tracker.js re-touches this flag
  // on every prompt, so a MISSING flag mid-session is not "not yet exercised",
  // it is the 2026-08-27 kill-switch bug (finding #9) having fired -- silently,
  // which is exactly why it went unnoticed for 6 of 20 real sessions.
  { hook: 'caveman flag (.caveman-active)', cavemanFlag: true, when: 'every-turn' },
];
// Deliberately NOT claimed as provable in-session, rather than faked:
const UNPROVABLE = [
  ['memory-recall.js', 'read-only hook, writes no state -- no mechanical footprint to check'],
  ['memory-architecture.js', 'writes only when flagging a note stale; silence is the normal case'],
  ['memory-init.js', 'SessionStart ran before any state existed to compare against'],
  ['memory-compact.js', 'PreCompact -- fires only on a compaction, which may never happen'],
  ['memory-flush.js', 'SessionEnd -- cannot fire while the session is still open'],
];

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// A verifier that reports "not wired" when it simply couldn't look is lying in
// the reassuring direction -- the same failure class this file's ponytail block
// was added to close. Every unreadable probe below says so on stderr, so an
// all-"missing" report caused by a permissions problem can't be mistaken for a
// genuinely incomplete install.
function warn(message) {
  process.stderr.write(`[claude-harness] verify: ${message}\n`);
}

function exists(p) {
  try {
    return fs.existsSync(p);
  } catch (err) {
    warn(`cannot stat ${p} (${err.code || err.message}) -- treating as absent`);
    return false;
  }
}

function readJSON(p) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (_) {
    return null;
  }
}

function settingsContains(needle) {
  try {
    return fs.readFileSync(SETTINGS_PATH, 'utf8').includes(needle);
  } catch (err) {
    // No settings.json at all is a legitimate pre-wiring state.
    if (err.code !== 'ENOENT') warn(`cannot read ${SETTINGS_PATH} (${err.code || err.message}) -- wiring checks below report as not-wired`);
    return false;
  }
}

// cavemanConfigPath is caveman-config.js's own getConfigPath, imported above
// -- not re-derived here, so this check reads the exact path the real hook
// reads, not a parallel guess at its logic. (PR3 dedupe, 2026-08-27: the
// local reimplementation checked APPDATA unconditionally regardless of
// platform; the shared version gates it behind `process.platform === 'win32'`
// and falls back to `AppData/Roaming` when APPDATA is unset there -- strictly
// more correct, not just less duplicated.)

const results = [];
function push(tier, status, detail, rows) {
  results.push(rows ? { tier, status, detail, rows } : { tier, status, detail });
}

// Is ANY of this pack wired into settings.json? Distinguishes "fresh install,
// nothing pasted yet" (every tier legitimately pending) from "configured
// machine with one thing broken". Without it, a first-run install reports hard
// failures for wiring the user has not been asked to paste yet -- which is a
// real regression this file shipped for one commit, caught by
// onboarding/test/run.sh asserting install.sh exits zero on a scratch target.
const SETTINGS_READABLE = exists(SETTINGS_PATH);
const anyHarnessWiring =
  settingsContains('claude-harness') || settingsContains('secret-guard.js') || settingsContains('caveman-activate.js');

// ── always-on: rules + manifest, no toggle, always expected present ───────────
{
  const missing = [];
  if (!exists(path.join(PACK_DIR, 'rules'))) missing.push('rules/');
  if (!exists(path.join(PACK_DIR, 'skills', 'manifest.yaml'))) missing.push('skills/manifest.yaml');
  push('always-on', missing.length ? 'missing' : 'ok', missing.length ? `missing: ${missing.join(', ')}` : 'rules + manifest present');
}

// ── wiring: a real JSON parse, not a substring match. Catches an unwired hook,
// a stale matcher, and a settings.json entry pointing at a file that no longer
// exists on disk -- three failures this pack has actually shipped. ────────────
const wiringProblems = [];
{
  const settings = readJSON(SETTINGS_PATH);
  if (!settings) {
    push('wiring', 'missing', `settings.json unreadable or not valid JSON at ${SETTINGS_PATH}`);
    wiringProblems.push('settings.json unreadable');
  } else {
    const hooks = settings.hooks || {};
    const wiredBlob = JSON.stringify(hooks);
    // A group counts as installed if ANY of its hooks is wired anywhere.
    const groupWired = {};
    for (const exp of EXPECTED_HOOKS) {
      groupWired[exp.group] = groupWired[exp.group] || wiredBlob.includes(exp.file);
    }
    const rows = [];
    for (const exp of EXPECTED_HOOKS) {
      const entries = (hooks[exp.event] || []).filter((e) =>
        (e.hooks || []).some((h) => String(h.command || '').includes(exp.file))
      );
      const label = `${exp.event}:${exp.file}`;
      if (!entries.length) {
        if (!groupWired[exp.group]) {
          rows.push([label, 'opted-out', `${exp.group} hooks not wired`]);
        } else {
          rows.push([label, 'UNWIRED', 'named nowhere under this event in settings.json']);
          wiringProblems.push(`${label} unwired`);
        }
        continue;
      }
      // matcher token coverage. Tokens are matched as literal `|`-delimited
      // members of the matcher string, not raw regex -- a token containing a
      // regex metachar (e.g. `mcp__playwright.*`) previously risked a false
      // STALE MATCHER (or, worse, a false pass) depending on how the
      // metacharacters happened to interact with `\b`. escapeRe() makes the
      // token literal; `(^|\|)` / `(\||$)` require it to be a whole matcher
      // segment, not a substring of a longer one.
      if (exp.tokens) {
        const matcher = entries.map((e) => e.matcher || '').join('|');
        const missingTok = exp.tokens.filter(
          (t) => !new RegExp(`(^|\\|)${escapeRe(t)}(\\||$)`, 'i').test(matcher)
        );
        if (missingTok.length) {
          rows.push([label, 'STALE MATCHER', `matcher "${matcher}" is missing: ${missingTok.join(', ')}`]);
          wiringProblems.push(`${label} stale matcher (missing ${missingTok.join(', ')})`);
          continue;
        }
      }
      // The command must point at a file that actually exists. Anchored on
      // exp.file rather than "the first quoted span" -- a hand-edited
      // settings.json with an unquoted command (`node /home/u/.../hook.js`,
      // valid shell, no spaces) previously extracted `null` and silently
      // skipped this check entirely, in the one tier whose job is catching
      // exactly this. Matches with or without surrounding quotes.
      const cmds = entries.flatMap((e) => (e.hooks || []).map((h) => String(h.command || '')));
      const target = cmds.find((c) => c.includes(exp.file));
      const m = target && target.match(new RegExp(`"?([^"\\s]*${escapeRe(exp.file)})"?`));
      const filePath = m ? m[1] : null;
      if (filePath && !exists(filePath)) {
        rows.push([label, 'MISSING FILE', `wired to ${filePath}, which does not exist`]);
        wiringProblems.push(`${label} points at a missing file`);
        continue;
      }
      rows.push([label, 'ok', exp.tokens ? `matcher covers ${exp.tokens.join(',')}` : 'wired']);
    }
    const bad = rows.filter((r) => !['ok', 'opted-out'].includes(r[1]));
    push('wiring', bad.length ? 'BROKEN' : 'ok', bad.length ? `${bad.length} problem(s) -- see rows` : `${rows.length} hook wirings verified by JSON parse`, rows);
  }
}

// ── secret-guard: rules/security-invariants.md:5 designates this the SINGLE
// mechanical backstop for all of Tier 0. Until 2026-08-27 it lived only as an
// untracked v4 leftover on one machine -- in the repo, uninstalled, unverified.
// Presence is not enough here: this tier actually RUNS it. ────────────────────
{
  const guardPath = path.join(CLAUDE_DIR, 'hooks', 'secret-guard.js');
  const guardWired = settingsContains('secret-guard.js');
  if (!exists(guardPath)) {
    push('secret-guard', 'missing', `NOT installed at ${guardPath} -- security-invariants.md Tier 0 claims a mechanical backstop that does not exist. Re-run install.sh.`);
  } else if (!guardWired && !anyHarnessWiring) {
    // Fresh install: the files landed, the user hasn't pasted any wiring yet.
    // Same state caveman/memory-hooks report as pending-manual-paste -- not a
    // failure, and install.sh must not exit nonzero for it (it just printed the
    // block to paste). Distinguished from the case below by "is ANYTHING from
    // this pack wired at all".
    push('secret-guard', 'pending-manual-paste', `installed at ${guardPath}, settings.json not yet updated (paste the PreToolUse block from install.sh output)`);
  } else if (!guardWired) {
    // The deceptive case: the rest of the pack IS wired, so this is a
    // configured machine -- but the guard is named nowhere, so it never runs
    // while everything around it does. The file is right there on disk, which
    // is exactly why file-presence checking reported this as healthy.
    push('secret-guard', 'BROKEN', `installed at ${guardPath} but NOT wired into settings.json while the rest of the pack is -- it never runs. Add the PreToolUse "Edit|Write" block (see install.sh output).`);
  } else {
    // Functional smoke test. A canonical fake AWS key literal must be blocked
    // (exit 2) and benign content must pass (exit 0). Built with string
    // concatenation so this source file does not itself contain a matchable
    // literal -- the guard blocks writes to its own test, as the 2026-08-27
    // audit found the hard way.
    const bad = JSON.stringify({ tool_name: 'Write', tool_input: { content: `key = "${'AKIA'}${'A'.repeat(16)}"` } });
    const good = JSON.stringify({ tool_name: 'Write', tool_input: { content: 'console.log(1)' } });
    const run = (payload) => spawnSync(process.execPath, [guardPath], { input: payload, encoding: 'utf8' }).status;
    const badExit = run(bad);
    const goodExit = run(good);
    if (badExit === 2 && goodExit === 0) {
      push('secret-guard', 'ok', 'installed, wired, and smoke-tested live (blocks a secret literal with exit 2, passes benign content)');
    } else {
      push('secret-guard', 'BROKEN', `installed but not functioning: secret payload exited ${badExit} (want 2), benign payload exited ${goodExit} (want 0)`);
    }
  }
}

// ── ponytail: required:true, distributed as a Claude Code marketplace plugin ──
{
  const enabled = settingsContains('"ponytail@ponytail": true');
  push(
    'ponytail',
    enabled ? 'ok' : 'missing',
    enabled
      ? 'installed and enabled (Claude Code marketplace plugin)'
      : 'NOT installed -- required:true but missing. Run: claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail'
  );
}

// ── caveman: default-on communication layer ───────────────────────────────────
{
  const dirPresent = exists(path.join(PACK_DIR, 'caveman'));
  const cfgPath = cavemanConfigPath();
  let cfgHasMode = false;
  let cfgError = null;
  try {
    const parsed = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    cfgHasMode = !!(parsed && parsed.defaultMode);
    if (!cfgHasMode) cfgError = 'no defaultMode field';
  } catch (err) {
    // "Not there yet" and "there but broken" both block activation, but only one
    // of them is fixed by re-running the installer -- say which this is.
    cfgError = err.code === 'ENOENT' ? 'missing defaultMode' : `unreadable/malformed (${err.code || err.message})`;
  }
  const wired = settingsContains('caveman-activate.js');
  let status, detail;
  if (!dirPresent || !cfgHasMode) {
    status = 'missing';
    detail = !dirPresent
      ? 'caveman/ not installed'
      : `config ${cfgError || 'missing defaultMode'} at ${cfgPath}`;
  } else if (!wired) {
    status = 'pending-manual-paste';
    detail = 'files + config ok, settings.json not yet updated (see install.sh output)';
  } else {
    status = 'ok';
    detail = 'installed, configured, wired into settings.json';
  }
  push('caveman', status, detail);
}

// ── memory-hooks: opt-in, off by default -- absence is not a failure ──────────
{
  const dirPresent = exists(path.join(PACK_DIR, 'memory', 'hooks'));
  let status, detail;
  if (!dirPresent) {
    status = 'not-installed';
    detail = 'opted out (default) -- re-run with --with-memory-hooks to add';
  } else if (!settingsContains('memory-init.js')) {
    status = 'pending-manual-paste';
    detail = 'files installed, settings.json not yet updated (see install.sh output)';
  } else {
    status = 'ok';
    detail = 'installed and wired into settings.json';
  }
  push('memory-hooks', status, detail);
}

// ── live: did the mechanical layer actually RUN this session? ─────────────────
// Session identity is bootstrapped from the scope pin file (_lib.js's
// resolveScope writes it on the first hook to see a session id, which is also
// the only thing that knows this session's true scope). Falls back to the
// newest lastSeen across gate state in the cwd-resolved scope for installs
// predating the pin, and says which route it took either way -- guessing
// silently is how the old all-green report happened.
function resolveLiveTarget() {
  const pinPath = path.join(HOME_DIR, '.claude', 'session-scope.json');
  const pins = readJSON(pinPath);
  if (pins && Object.keys(pins).length) {
    let bestId = SESSION_OVERRIDE;
    if (!bestId) {
      let bestAt = '';
      for (const [id, p] of Object.entries(pins)) {
        if (p && p.at && p.at > bestAt) {
          bestAt = p.at;
          bestId = id;
        }
      }
    }
    const pin = bestId && pins[bestId];
    if (pin && pin.base) return { sessionId: bestId, base: pin.base, via: 'scope pin file' };
  }
  // fallback: walk for a git root from cwd, same rule _lib.js uses
  let dir = path.resolve(process.cwd());
  const home = path.resolve(HOME_DIR);
  let base = path.join(home, '.claude');
  for (;;) {
    if (dir !== home && exists(path.join(dir, '.git'))) {
      base = path.join(dir, '.claude');
      break;
    }
    if (dir === home) break;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  let sessionId = SESSION_OVERRIDE;
  if (!sessionId) {
    let bestAt = '';
    for (const g of ['canary', 'review-gate', 'design-lane-gate', 'visual-plan-gate']) {
      const st = readJSON(path.join(base, g, 'state.json')) || {};
      for (const [id, v] of Object.entries(st)) {
        if (v && v.lastSeen && v.lastSeen > bestAt) {
          bestAt = v.lastSeen;
          sessionId = id;
        }
      }
    }
  }
  return { sessionId, base, via: 'newest gate lastSeen (no scope pin file -- pre-6.5.0 install)' };
}

if (WANT_LIVE) {
  const { sessionId, base, via } = resolveLiveTarget();
  if (!sessionId) {
    push('live', 'INDETERMINATE', `no session state found under ${base} -- either no harness hook has ever run here, or the scope resolved wrong (via: ${via})`);
  } else {
    const rows = [];
    for (const probe of LIVE_PROBES) {
      let seen = false;
      let note = '';
      if (probe.gate) {
        const st = readJSON(path.join(base, probe.gate, 'state.json')) || {};
        const e = st[sessionId];
        seen = !!(e && e.lastSeen);
        note = seen ? `wrote state at ${e.lastSeen}` : `no entry for this session in ${probe.gate}/state.json`;
      } else if (probe.checkpoint) {
        const cp = path.join(base, 'session', 'checkpoint.md');
        const txt = exists(cp) ? fs.readFileSync(cp, 'utf8') : '';
        seen = txt.includes(sessionId);
        note = seen ? 'live checkpoint carries this session_id' : 'no checkpoint for this session (expected until the first Edit/Write)';
      } else if (probe.cavemanFlag) {
        const flag = path.join(CLAUDE_DIR, '.caveman-active');
        seen = exists(flag);
        note = seen ? `flag present (${String(fs.readFileSync(flag, 'utf8')).trim()})` : 'flag file absent -- caveman was deactivated or never activated (statusline badge will be missing too)';
      }
      const status = seen ? 'ok' : probe.when === 'every-turn' ? 'DEAD' : 'not-exercised';
      rows.push([probe.hook, status, note]);
    }
    for (const [hook, why] of UNPROVABLE) rows.push([hook, 'unprovable', why]);
    const dead = rows.filter((r) => r[1] === 'DEAD');
    push(
      'live',
      dead.length ? 'BROKEN' : 'ok',
      dead.length
        ? `${dead.length} every-turn hook(s) never ran this session -- wired but not executing`
        : `session ${sessionId} (via ${via}); every-turn hooks all confirmed executing`,
      rows
    );
  }
}

// ── output ───────────────────────────────────────────────────────────────────
if (WANT_JSON) {
  process.stdout.write(`${JSON.stringify(results)}\n`);
} else {
  const icon = {
    ok: '✓',
    missing: '✗',
    BROKEN: '✗',
    INDETERMINATE: '?',
    'pending-manual-paste': '…',
    'not-installed': '-',
  };
  console.log(`[claude-harness] onboarding verify${WANT_LIVE ? ' --live' : ''}:`);
  for (const r of results) {
    console.log(`  ${icon[r.status] || '?'} ${r.tier.padEnd(14)} ${r.status.padEnd(20)} ${r.detail}`);
    for (const [name, st, note] of r.rows || []) {
      if (st === 'ok' || st === 'opted-out') continue; // only surface what needs attention
      console.log(`      - ${name.padEnd(38)} ${st.padEnd(14)} ${note}`);
    }
  }
}

// --check-wiring is install.sh's gate: nonzero means "reprint the wiring block".
if (WANT_WIRING_EXIT) process.exit(wiringProblems.length ? 1 : 0);
// Any hard failure is a nonzero exit so a script can branch on it. `missing` on
// an opt-in tier (memory-hooks) is not a failure; a BROKEN gate is -- and so is
// a missing `secret-guard` or `ponytail`, because rules/security-invariants.md
// and skills/manifest.yaml claim both UNCONDITIONALLY (required:true / Tier 0).
// A claim the pack makes with no opt-out must not exit 0 when unmet: that is
// precisely how this verifier used to report green through audit finding #11.
// Gated on SETTINGS_READABLE: with no settings.json at all there is nothing to
// read a plugin enablement out of, so `ponytail: missing` there means "could
// not measure", not "confirmed absent" -- and asserting a hard failure you did
// not measure is the same overreach as reporting green for one you didn't check.
const HARD_TIERS = ['secret-guard', 'ponytail'];
process.exit(
  results.some(
    (r) => r.status === 'BROKEN' || (SETTINGS_READABLE && HARD_TIERS.includes(r.tier) && r.status === 'missing')
  )
    ? 1
    : 0
);
