#!/usr/bin/env node
// caveman — shared configuration resolver
//
// Resolution order for default mode:
//   1. CAVEMAN_DEFAULT_MODE environment variable
//   2. Config file defaultMode field:
//      - $XDG_CONFIG_HOME/caveman/config.json (any platform, if set)
//      - ~/.config/caveman/config.json (macOS / Linux fallback)
//      - %APPDATA%\caveman\config.json (Windows fallback)
//   3. 'full'

const fs = require('fs');
const path = require('path');
const os = require('os');

const VALID_MODES = [
  'off', 'lite', 'full', 'ultra',
  'wenyan-lite', 'wenyan', 'wenyan-full', 'wenyan-ultra',
  'commit', 'review', 'compress'
];

// These hooks are fail-open by contract -- none of them may block a session
// start or a prompt -- but fail-open is not fail-silent: a mode that silently
// resolves to 'full' because the config is malformed is indistinguishable from
// one the user actually asked for. stderr is the channel here rather than
// memory/hooks/_lib.js's diagnostics log, because the caveman tier installs
// standalone (as a plugin, without memory/) and must not depend on it; Claude
// Code captures hook stderr in its debug output.
function warn(message) {
  try {
    process.stderr.write(`caveman: ${message}\n`);
  } catch (_) {
    /* stderr closed -- nothing left to report to */
  }
}

// One-shot skill invocations, not persistent chat-style intensity levels.
const INDEPENDENT_MODES = new Set(['commit', 'review', 'compress']);

// Flag file read by the statusline scripts and per-turn reminder.
function getFlagPath() {
  return path.join(os.homedir(), '.claude', '.caveman-active');
}

function writeFlag(mode) {
  const flagPath = getFlagPath();
  try {
    fs.mkdirSync(path.dirname(flagPath), { recursive: true });
    fs.writeFileSync(flagPath, mode);
  } catch (e) {
    // Best-effort, never blocking -- but the statusline badge reads this file,
    // so a failure here shows up to the user as "the mode didn't activate"
    // with no other explanation available anywhere.
    warn(`cannot write flag ${flagPath} (${e.code || e.message}) -- statusline badge will not show the active mode`);
  }
}

function clearFlag() {
  try {
    fs.unlinkSync(getFlagPath());
  } catch (e) {
    // No flag to clear is the expected case; a flag that CAN'T be cleared
    // means the statusline keeps advertising a mode that is not active.
    if (e.code !== 'ENOENT') warn(`cannot clear ${getFlagPath()} (${e.code || e.message})`);
  }
}

function readFlag() {
  try {
    return fs.readFileSync(getFlagPath(), 'utf8').trim();
  } catch (e) {
    // No flag means no active mode -- the normal path. Anything else means the
    // per-turn reinforcement caller silently stops firing, which reads as
    // "caveman drifted off" rather than "the hook can't read its own flag".
    if (e.code !== 'ENOENT') warn(`cannot read ${getFlagPath()} (${e.code || e.message})`);
    return '';
  }
}

function getConfigDir() {
  if (process.env.XDG_CONFIG_HOME) {
    return path.join(process.env.XDG_CONFIG_HOME, 'caveman');
  }
  if (process.platform === 'win32') {
    return path.join(
      process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
      'caveman'
    );
  }
  return path.join(os.homedir(), '.config', 'caveman');
}

function getConfigPath() {
  return path.join(getConfigDir(), 'config.json');
}

function getDefaultMode() {
  // 1. Environment variable (highest priority)
  const envMode = process.env.CAVEMAN_DEFAULT_MODE;
  if (envMode && VALID_MODES.includes(envMode.toLowerCase())) {
    return envMode.toLowerCase();
  }

  // 2. Config file
  const configPath = getConfigPath();
  let raw = null;
  try {
    raw = fs.readFileSync(configPath, 'utf8');
  } catch (e) {
    // No config file is the normal, expected case -- anything else (permissions,
    // an unreadable mount) means the user's configured mode is being ignored.
    if (e.code !== 'ENOENT') warn(`cannot read ${configPath} (${e.code || e.message}) -- falling back to 'full'`);
  }
  if (raw !== null) {
    try {
      const config = JSON.parse(raw);
      const configured = config && typeof config.defaultMode === 'string' ? config.defaultMode.toLowerCase() : null;
      if (configured && VALID_MODES.includes(configured)) return configured;
      // Present but unusable: silently returning 'full' here is how a typo'd
      // mode name looks exactly like no configuration at all.
      if (configured) warn(`unknown defaultMode "${configured}" in ${configPath} -- falling back to 'full'`);
    } catch (e) {
      warn(`malformed JSON in ${configPath} (${e.message}) -- falling back to 'full'`);
    }
  }

  // 3. Default
  return 'full';
}

module.exports = {
  getDefaultMode, getConfigDir, getConfigPath, VALID_MODES, warn,
  INDEPENDENT_MODES, getFlagPath, writeFlag, clearFlag, readFlag,
};
