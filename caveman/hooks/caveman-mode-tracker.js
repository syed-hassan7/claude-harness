#!/usr/bin/env node
// caveman — UserPromptSubmit hook to track which caveman mode is active
// Inspects user input for /caveman commands and writes mode to flag file.
//
// Also re-emits a short reminder every turn (see bottom of the try block).
// caveman-activate.js only injects the full ruleset once, at SessionStart —
// in long, tool-heavy conversations that early context loses priority and
// behavior drifts back to verbose prose. UserPromptSubmit stdout is injected
// as context on every single prompt (unlike most hook events), so a cheap
// per-turn reminder here is the anchor that actually survives session length.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { getDefaultMode } = require('./caveman-config');

const flagPath = path.join(os.homedir(), '.claude', '.caveman-active');

// One-shot skill invocations, not persistent chat-style levels — no chat
// reinforcement reminder applies to these.
const INDEPENDENT_MODES = new Set(['commit', 'review', 'compress']);

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const prompt = (data.prompt || '').trim().toLowerCase();

    // Match /caveman commands
    if (prompt.startsWith('/caveman')) {
      const parts = prompt.split(/\s+/);
      const cmd = parts[0]; // /caveman, /caveman-commit, /caveman-review, etc.
      const arg = parts[1] || '';

      let mode = null;

      if (cmd === '/caveman-commit') {
        mode = 'commit';
      } else if (cmd === '/caveman-review') {
        mode = 'review';
      } else if (cmd === '/caveman-compress' || cmd === '/caveman:caveman-compress') {
        mode = 'compress';
      } else if (cmd === '/caveman' || cmd === '/caveman:caveman') {
        if (arg === 'lite') mode = 'lite';
        else if (arg === 'ultra') mode = 'ultra';
        else if (arg === 'wenyan-lite') mode = 'wenyan-lite';
        else if (arg === 'wenyan' || arg === 'wenyan-full') mode = 'wenyan';
        else if (arg === 'wenyan-ultra') mode = 'wenyan-ultra';
        else mode = getDefaultMode();
      }

      if (mode && mode !== 'off') {
        fs.mkdirSync(path.dirname(flagPath), { recursive: true });
        fs.writeFileSync(flagPath, mode);
      } else if (mode === 'off') {
        try { fs.unlinkSync(flagPath); } catch (e) {}
      }
    }

    // Detect deactivation
    if (/\b(stop caveman|normal mode)\b/i.test(prompt)) {
      try { fs.unlinkSync(flagPath); } catch (e) {}
    }

    // Per-turn reinforcement (see header comment for why this exists).
    let activeMode = '';
    try { activeMode = fs.readFileSync(flagPath, 'utf8').trim(); } catch (e) {}

    if (activeMode && activeMode !== 'off' && !INDEPENDENT_MODES.has(activeMode)) {
      process.stdout.write(
        'CAVEMAN ' + activeMode.toUpperCase() + ' still active — reply tersely: ' +
        'no articles/filler/pleasantries/hedging, fragments ok, technical substance ' +
        'unchanged. Code/commits/PRs stay normal prose.'
      );
    }
  } catch (e) {
    // Silent fail
  }
});
