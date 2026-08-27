#!/usr/bin/env node
'use strict';
// PreToolUse (Edit|Write) — blocks a write whose content matches a secret
// literal. Exit 2 + stderr is Claude Code's blocking contract; every other
// path exits 0 so a bug here can never block a legitimate write.
//
// WHY THIS FILE IS HERE (2026-08-27). `rules/security-invariants.md:5`
// designates this hook the single mechanical backstop for all of Tier 0 — yet
// until now it existed ONLY as an untracked leftover at `~/.claude/hooks/` on
// one developer's machine, dated Jun 20, inherited from the retired v4
// harness. It was not in this repo, not installed by `install.sh`, and not
// checked by `onboarding/verify.js`. So every fresh install shipped the RULE
// claiming a mechanical secret backstop and none of the hook — structurally
// the same defect as `ponytail` being `required: true` and never installed
// (external audit finding #11), with strictly worse stakes. Vendored here so
// the claim and the code ship together and `verify.js` can prove it.
//
// Installed to `~/.claude/hooks/secret-guard.js` — deliberately the SAME path
// the pre-existing wiring already points at, so installs that already have
// the PreToolUse block do not need to re-paste anything.
//
// Self-contained on purpose: the v4 original required a shared
// `harness-hook-utils.js` (51 lines) for 12 lines of stdin-read + block, and
// dragged in three functions nothing here used. One file, zero deps.

const fs = require('fs');

const SECRET_PATTERNS = [
  { name: 'AWS access key', re: /AKIA[0-9A-Z]{16}/ },
  { name: 'AWS secret key', re: /(?:aws)?[_-]?secret[_-]?access[_-]?key\s*[=:]\s*['"]?[A-Za-z0-9/+=]{40}/i },
  { name: 'Private key header', re: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/ },
  { name: 'GitHub PAT', re: /ghp_[A-Za-z0-9]{36,}/ },
  { name: 'Generic API key assignment', re: /(?:api[_-]?key|password|secret)\s*[=:]\s*['"][^'"\s]{8,}['"]/i },
];

function readHookInput() {
  if (process.stdin.isTTY) return {};
  try {
    const raw = fs.readFileSync(0, 'utf8').trim();
    return raw ? JSON.parse(raw) : {};
  } catch (_) {
    return {};
  }
}

function main() {
  const input = readHookInput();
  const toolInput = input.tool_input || {};
  // Edit sends new_string, Write sends content; new_str covers the older
  // Edit payload shape. Anything else this hook cannot see -- see the scope
  // limits in rules/security-invariants.md.
  const content = toolInput.content || toolInput.new_string || toolInput.new_str || '';
  if (!content || typeof content !== 'string') return;

  for (const { name, re } of SECRET_PATTERNS) {
    if (re.test(content)) {
      process.stderr.write(
        `CLAUDE HARNESS SECRET GUARD — write blocked.\n` +
          `  pattern: ${name}\n` +
          `  use environment variables or a secrets manager — never commit literals.\n`
      );
      process.exit(2); // 2 is the only exit code Claude Code treats as "block"
    }
  }
}

try {
  main();
} catch (_) {
  // Fail OPEN. A crash in the guard must not block every Edit/Write on the
  // machine -- a dead guard is a known, verifiable state (verify.js smoke-tests
  // it); a guard that blocks everything is an unusable editor.
}
process.exit(0);
