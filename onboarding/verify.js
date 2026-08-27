#!/usr/bin/env node
'use strict';
// Standalone mechanical post-install check -- NOT a Claude Code hook (no
// hookSpecificOutput, no stdin JSON). Invoked directly by install.sh's
// --onboard path and by the onboarding skill's Bash calls, so both delivery
// surfaces prove the same real state instead of trusting install.sh's own
// stdout. Resolves the pack dir the exact same way install.sh does
// (CLAUDE_HARNESS_TARGET override, else $HOME/.claude) so a sandboxed test
// run and a real run check the same thing.

const fs = require('fs');
const path = require('path');
const os = require('os');
// The layout is identical in the repo and under PACK_DIR (install.sh syncs
// caveman/ and onboarding/ side by side), so the runtime resolver is always
// a sibling -- verify checks the exact config path the hooks actually read,
// rather than re-deriving it.
const { getConfigPath: cavemanConfigPath } = require(path.join(__dirname, '..', 'caveman', 'hooks', 'caveman-config.js'));

const CLAUDE_DIR = process.env.CLAUDE_HARNESS_TARGET || path.join(os.homedir(), '.claude');
const PACK_DIR = path.join(CLAUDE_DIR, 'claude-harness');
const SETTINGS_PATH = path.join(CLAUDE_DIR, 'settings.json');

function settingsContains(needle) {
  try {
    return fs.readFileSync(SETTINGS_PATH, 'utf8').includes(needle);
  } catch (_) {
    return false;
  }
}

function exists(p) {
  try {
    return fs.existsSync(p);
  } catch (_) {
    return false;
  }
}

const results = [];

// --- always-on: rules + manifest, no toggle, always expected present ---
{
  const missing = [];
  if (!exists(path.join(PACK_DIR, 'rules'))) missing.push('rules/');
  if (!exists(path.join(PACK_DIR, 'skills', 'manifest.yaml'))) missing.push('skills/manifest.yaml');
  results.push({
    tier: 'always-on',
    status: missing.length ? 'missing' : 'ok',
    detail: missing.length ? `missing: ${missing.join(', ')}` : 'rules + manifest present',
  });
}

// --- ponytail: required:true core engineering skill, distributed as a
// Claude Code marketplace plugin (not part of this pack's own file tree, so
// there's nothing under PACK_DIR to check presence of -- the only real
// signal is whether install.sh's plugin-install step actually landed).
// Added 2026-08-27 after an external audit found this exact gap: the
// pre-existing tiers above only check file presence + settings.json
// wiring, which stayed all-green while ponytail (required:true) was never
// installed at all -- a verifier that can't detect its own pack's most
// prominent lie isn't verifying the thing that matters.
{
  const enabled = settingsContains('"ponytail@ponytail": true');
  results.push({
    tier: 'ponytail',
    status: enabled ? 'ok' : 'missing',
    detail: enabled
      ? 'installed and enabled (Claude Code marketplace plugin)'
      : 'NOT installed -- required:true but missing. Run: claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail',
  });
}

// --- caveman: default-on communication layer ---
{
  const dirPresent = exists(path.join(PACK_DIR, 'caveman'));
  const cfgPath = cavemanConfigPath();
  let cfgHasMode = false;
  try {
    cfgHasMode = !!JSON.parse(fs.readFileSync(cfgPath, 'utf8')).defaultMode;
  } catch (_) {
    cfgHasMode = false;
  }
  const wired = settingsContains('caveman-activate.js');
  let status, detail;
  if (!dirPresent || !cfgHasMode) {
    status = 'missing';
    detail = !dirPresent ? 'caveman/ not installed' : `config missing defaultMode at ${cfgPath}`;
  } else if (!wired) {
    status = 'pending-manual-paste';
    detail = `files + config ok, settings.json not yet updated (see install.sh output)`;
  } else {
    status = 'ok';
    detail = 'installed, configured, wired into settings.json';
  }
  results.push({ tier: 'caveman', status, detail });
}

// --- memory-hooks: opt-in, off by default -- absence is not a failure ---
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
  results.push({ tier: 'memory-hooks', status, detail });
}

if (process.argv.includes('--json')) {
  process.stdout.write(JSON.stringify(results) + '\n');
} else {
  const icon = { ok: '✓', missing: '✗', 'pending-manual-paste': '…', 'not-installed': '-' };
  console.log('[claude-harness] onboarding verify:');
  for (const r of results) {
    console.log(`  ${icon[r.status] || '?'} ${r.tier.padEnd(14)} ${r.status.padEnd(20)} ${r.detail}`);
  }
}
