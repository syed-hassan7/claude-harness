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

module.exports = { getDefaultMode, getConfigDir, getConfigPath, warn, VALID_MODES };
