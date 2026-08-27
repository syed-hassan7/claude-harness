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

// Deactivation must be a real directive, not a quoted mention or a negated
// reference to the phrase -- a bare substring test over the whole prompt
// (the pre-2026-08-27 behavior) silently killed the flag any time a session
// merely discussed caveman mode, which is exactly the class of session where
// the user is most likely to be working on the pack itself (confirmed: 6/20
// real local sessions tripped it, e.g. `without saying "stop caveman"` and
// `grep -n "normal mode" ./docs/*.md`, both quoted mentions, neither a real
// ask). Same two-step filter memory/SPEC.md's correction-detection gate
// already uses (strip quoted/code spans first, borrowed from
// texastoast/claude-memory-loops) -- both real repro cases above had the
// phrase inside quotes, so stripping alone clears them; the negation veto
// below additionally covers an unquoted negated mention.
// Single-quote stripping is bounded (lookbehind/lookahead require a
// non-word char, or start/end of string, on each side) -- a naive
// /'[^']*'/g pairs the apostrophes in ordinary contractions ("let's ...
// don't ...") as if they were a quote pair and deletes everything between
// them, including a real directive in the middle. Caught during this fix's
// own review: `"let's stop caveman, and don't forget it's done"` silently
// ate "s stop caveman, and don'" under the naive version.
//
// The bounded version alone has its OWN failure mode, caught by a second
// review pass: a GENUINE quoted span that itself contains a contraction
// before its closing quote (`"the docs say 'stop caveman, that's how you
// exit' somewhere"`) fails to strip AT ALL -- [^']* can't cross the
// interior apostrophe, and that apostrophe fails both lookarounds (it's
// letter-preceded and letter-followed), so the whole match attempt aborts.
// That's the exact "quoted mention kills the flag" bug this function exists
// to prevent, just triggered by a different sentence shape. Fixed by
// letting the span explicitly swallow a `'<letter>` sequence as a
// contraction (never a delimiter) via the repeated non-capturing group,
// rather than treating every apostrophe as a potential span boundary.
function stripQuotedSpans(text) {
  return text
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/"[^"]*"/g, ' ')
    .replace(/(?<![A-Za-z0-9])'[^']*(?:'[A-Za-z][^']*)*'(?![A-Za-z0-9])/g, ' ');
}
const KILL_PHRASE_RE = /\b(stop caveman|normal mode)\b/gi;
const NEGATION_BEFORE_RE = /\b(without|never|don't|do not|not|avoid)\b[^.,;?!]{0,40}$/i;
// Checks EVERY occurrence of the phrase, not just the first -- a prompt
// like "don't stop caveman... actually, stop caveman" must not let an
// earlier negated mention veto a later real, unnegated one.
function isRealDeactivation(prompt) {
  const stripped = stripQuotedSpans(prompt);
  let match;
  KILL_PHRASE_RE.lastIndex = 0;
  while ((match = KILL_PHRASE_RE.exec(stripped))) {
    if (!NEGATION_BEFORE_RE.test(stripped.slice(0, match.index))) return true;
  }
  return false;
}

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

    // Detect deactivation -- see isRealDeactivation's header comment above.
    if (isRealDeactivation(prompt)) {
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
