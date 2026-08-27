# Hand-over: claude-harness reliability overhaul (v6.5.0, uncommitted)

**Written:** 2026-08-27, mid-task, by the Claude Code session that did the work below.
**For:** whoever picks this up next (Devin).
**Repo:** `C:\Users\SyedHassan\OneDrive - thrivelearning.com\Documents\claude-harness`, branch `main`.
**State:** all work is **uncommitted working-tree edits**. Nothing pushed. A human approval gate
before any commit is a hard rule on this repo and was not relaxed for this effort.

---

## 0. Read these first, in this order

1. `audit-log/2026-08-27-reliability-overhaul-prompt.md` — the original brief. Its **thesis** is the
   constraint that matters, not its gap list. Thesis, compressed: *every defect ever found in this
   pack lived in the gap between "what the synthetic test fixture sends" and "what a real Claude
   Code session actually sends." The mission is to eliminate that class of gap and build something
   that keeps eliminating it.*
2. `audit-log/2026-08-27-external-audit.md` — the 27-finding audit that started it.
3. `audit-log/2026-08-27-reliability-overhaul-result.md` — **my summary of everything done.** Start
   here for the what; this hand-over is the how and the what's-left.
4. `audit-log/2026-08-27-task0-live-wire-trace.md` — Task 0 evidence (the one result that is
   expensive to reproduce).
5. `audit-log/2026-08-27-claims-backstop-triage.md` — finding #24, all 33 claims triaged.
6. `CHANGELOG.md` 6.5.0 entry — the full narrative, already written.

Methodology rules from the brief that are **non-negotiable** and that I followed — keep following
them:

- **Empirical, not read-and-reasoned.** Every claim needs the command + output that proves it. "I
  read the code and it looks right" is what shipped two buggy fixes the week before.
- **Adversarial tests.** For every gate, write the test that tries to make it *fail to detect* a
  real violation, not the happy path.
- **A self-check must be shown RED before any GREEN from it is trusted.** One red demonstration per
  thing it claims to check.
- **Independent review, expect it to find something.**
- **Call `advisor()`** before committing to an approach and again before declaring done. I did both;
  both calls changed the plan materially.

---

## 1. What is done (all verified, all uncommitted)

### Task 0 — CLOSED. Field names confirmed on the wire.

`review-gate-check.js` reads `input.tool_input.skill` / `.subagent_type` / `.command`. Those names
had been *inferred* from chat-facing tool schemas and shipped on secondary evidence after a reviewer
objected — and 6.4.0 had already deleted the transcript-scan fallback, so wrong names meant a
silently dead gate with no fallback.

Method (reuse this technique, it works and needs no session restart): the hook is already wired in
the live `~/.claude/settings.json` under `PostToolUse` matcher `Bash|Skill|Agent`. I inserted a
one-line payload dump into the **installed** copy at
`~/.claude/claude-harness/memory/hooks/review-gate-check.js` (verified byte-identical to the repo
copy with `diff` first), made real tool calls, read the dump, then restored the repo copy over it and
re-`diff`ed to zero. Claude Code spawns `node <file>` fresh per hook invocation, so a file edit takes
effect immediately — **no `settings.json` change and no restart needed.**

Result: **all three field names correct, no code change required.** Payload envelope is
`session_id, transcript_path, cwd, prompt_id, permission_mode, effort, hook_event_name, tool_name,
tool_input, tool_response, tool_use_id, duration_ms`. A real `Skill(review-loop)` flipped
`reviewSeen` to `true` in live project-scope state; `Skill(ponytail:ponytail-help)` correctly did
not. Bonus non-finding, recorded so nobody re-chases it: a **failed** dispatch (`Unknown skill: …`)
never reaches `PostToolUse` at all, so it cannot satisfy the gate for free.

### Code changes

| File | Change | Why |
|---|---|---|
| `memory/hooks/_lib.js` | **Session-scope pinning.** `resolveScope(cwd, sessionId)` pins a session's scope on first sight into `~/.claude/session-scope.json` (global always — only place all scopes agree to look), 30-day TTL prune, read-inside-lock re-check. `resolveScopeFromCwd()` split out and still exported. | Audit finding #5. Root cause: **a hook's `input.cwd` is the Bash tool's *persisted* cwd, not the session's launch cwd** — one `cd` moved every later hook write into a different scope, splitting one session's state across two `.claude/` dirs. Fixed in the one shared function so all 10 call sites inherit it. |
| `memory/hooks/_lib.js` | **`GIT_COMMIT_RE` tightened** to `/(?:^\|[\s;&\|(])git\s[^&\|;\n]*\bcommit\b/i`. | All 11 real commit shapes already matched (verified, incl. bash heredoc + PowerShell here-string), but `\bgit\b` matched the word anywhere, so `cat docs/git-commit-pr.md` logged a MISS for a commit that never ran. False MISS is the trust-eroding direction. |
| 10 hook files | `lib.resolveScope(cwd)` → `lib.resolveScope(cwd, sessionId)` / `(cwd, input.session_id)`. | Threading the pin. Done mechanically by script; all sites verified, none left bare. |
| `memory/hooks/memory-init.js` | **Empty-`goal` nudge** on the injected checkpoint. | Finding #2. The one claim from #24 that met the mechanization bar. Folded into an existing read — no new hook, no new `settings.json` wiring. |
| `onboarding/verify.js` | **Rewritten.** New tiers: `wiring` (real JSON parse vs an expected-wiring table — catches unwired hook, stale matcher, entry pointing at a missing file), `secret-guard` (present + wired + **live smoke test** asserting exit 2), `ponytail` promoted to a hard tier, and `--live` (did each every-turn hook actually run *this session*, bootstrapped from the scope-pin file with a fallback). `--check-wiring` and `--json` modes. | The old verifier had 3 file-presence checks and reported all-green through 4 live broken findings. |
| `onboarding/test/red-demos.sh` | **New. 13 RED demos.** | Falsifiability. See §2. |
| `security/hooks/secret-guard.js` | **New — vendored.** Self-contained (dropped the 51-line `harness-hook-utils.js` it used 12 lines of). Message renamed `MACHINA` → `CLAUDE HARNESS`. | See §3 — biggest finding of the pass. |
| `install.sh` | New section **1e** installs `secret-guard.js` unconditionally to `$CLAUDE_DIR/hooks/` (the **existing** wired path, so no install needs to re-paste). `review_gate_matcher_stale()` (hook-specific, embedded `node -e`) replaced by `harness_wiring_stale()` delegating to `verify.js --check-wiring`. Final `verify.js` call made `|| true`. | Generalizes a one-hook check to all hooks; removes bash-embedded JS. |
| `rules/design-lane.md` | The "hard gate" no longer requires the uninstalled `anti-slop`; screenshot is the hard part. | Finding #14 — half of a "hard, not optional" rule could not execute. |
| `WORKFLOW.md` | Drops the unresolvable `superpowers` skill name; documents `verify.js --live` in the Verify section. | Finding #13 + deliverable 3. |
| `rules/security-invariants.md` | Points at `security/hooks/secret-guard.js`, states its real scope limits, tells the reader to verify rather than assume. | See §3. |
| `memory/SPEC.md` | New "One session, one scope — the pin" section; `goal`-nudge rationale. | Deliverable 4. |
| `README.md`, `CHANGELOG.md`, `skills/manifest.yaml` (`version: 6.5.0`) | Docs + version. | |

### Tests — all green, **pre-independent-review**

```bash
bash memory/hooks/test/run.sh          # ALL 80 CHECKS PASSED   (74 before this pass, 71 at audit)
bash caveman/hooks/test/run.sh         # ALL 12 CHECKS PASSED
bash onboarding/test/run.sh            # ALL 5 CHECKS PASSED
bash onboarding/test/red-demos.sh      # ALL 13 RED DEMOS PASSED
node onboarding/verify.js --live       # all tiers ok, exit 0
bash -n install.sh                     # syntax ok
```

New tests: 65 (`isGitCommitCommand`, 16 real command strings, both directions), 66–69 (scope
pinning: cross-scope regression, no cross-session bleed, no dir creation, TTL prune), 70 (`goal`
nudge, both directions).

**Both behavioural fixes were demonstrated RED against the pre-fix logic** before their green was
trusted (brief methodology point 3):
- old `\bgit\b` matcher restored → `FALSE-FIRED: path naming a commit doc | FALSE-FIRED: hyphenated token`
- pinning disabled → `REGRESSION (audit finding #5): a cd into repo B split session pinS1's state into a second scope`

Helper used for that: `scratchpad/break.js` (takes `matcher` or `pin`, reverts one fix in `_lib.js`).
Deliberately kept in scratch, not the repo — the permanent regression tests are the durable guard.

---

## 2. The self-check, and why its green is worth anything

`node ~/.claude/claude-harness/onboarding/verify.js --live`

Static mode checks the install. `--live` asks a different question: **not "is it installed" but "did
it run this session"** — it looks for *this session's own id* in the state each every-turn hook
writes, and reports `DEAD` for anything wired, present, current-matcher, and still not executing.
What it cannot prove in-session (`PreCompact`, `SessionEnd`, read-only hooks with no footprint) it
labels `unprovable` instead of counting silence as success.

Key design facts you need if you touch it:
- All four gate hooks (`canary`, `review-gate`, `design-lane-gate`, `visual-plan-gate`) **do** write
  per-session `lastSeen` on every `UserPromptSubmit`. Verified live, not assumed — I checked the real
  state files for this session before designing the probe.
- Session identity bootstraps from `~/.claude/session-scope.json` (newest `at`), falling back to
  newest `lastSeen` across gate state. It **prints which route it took**, because guessing silently
  is how the old all-green report happened.
- An absent `.caveman-active` flag counts as `DEAD`, not "not yet exercised" — that silent kill
  switch (finding #9) hit 6 of 20 real sessions.

`onboarding/test/red-demos.sh` breaks all 13 claims one at a time against a sandboxed fake install
(`CLAUDE_HARNESS_TARGET` + `CLAUDE_HARNESS_HOME_OVERRIDE`, zero live mutation), asserts each produces
its specific RED, with **green baselines at both ends** so the suite cannot pass by the verifier being
permanently red.

**The harness caught its own bug of exactly the class it exists to catch — read this before editing
it.** The first version asserted by grepping the human-readable report for `"secret-guard"`,
`"ponytail"`, and `"stale"`. All three appear in a *fully green* report too (two tier names, and the
prose "flagging a note stale"). Three demos would have passed no matter what `verify.js` did. It now
asserts on `--json` **status fields**, scoped **per tier** (a second collision: `canary-check.js`
names a row in both the `wiring` and `live` tiers, and an unscoped match asserted against whichever
came first). **Never assert against report prose in this file.**

---

## 3. Biggest finding, and it was not on the brief's list

**`secret-guard.js` was not in this repo.**

`rules/security-invariants.md:5` designates it the **sole** mechanical backstop for all of Tier 0,
with no opt-out. It existed only as an untracked leftover at `~/.claude/hooks/secret-guard.js`, dated
Jun 20, inherited from the retired v4 harness. Not in the repo (`find` returned nothing), not
installed by `install.sh`, not checked by `verify.js`. **Every fresh install shipped the security
claim and none of the hook.** Structurally identical to `ponytail` being `required: true` and never
installed (finding #11), with strictly worse stakes. A sixth instance of the brief's own thesis.

Fixed: vendored to `security/hooks/secret-guard.js`, installed unconditionally, functionally
smoke-tested by `verify.js` (runs it against a secret literal, asserts exit 2), and RED-demoed three
ways (absent / present-but-unwired / present-but-neutered).

Generalized lesson, saved to auto-memory as `feedback_verify_claims_ship_with_their_code`: when a doc
names a mechanical backstop or a `required: true` tool, check the **repo**, not the current machine.
This defect has now been found three times (`ponytail`, `anti-slop`+`superpowers`, `secret-guard`).

---

## 4. WHAT I WAS ABOUT TO DO — pick up exactly here

### 4a. Two false-green paths in `verify.js`, flagged by `advisor()`, NOT yet fixed

Both are the same category as the bugs already found in this pass: **the check reports healthy
because the check didn't execute.** Neither is fixed. **My attempt to verify them produced a
corrupted result — see the warning below.**

**Bug A — matcher token regex.** `verify.js`'s wiring tier does roughly:

```js
const missingTok = exp.tokens.filter((t) => !new RegExp(`\\b${t}\\b`, 'i').test(matcher));
```

Any token containing a regex metacharacter, or where `\b` doesn't sit where you'd expect (leading or
trailing `_`, a `.`, a `*`), silently fails to match a matcher that genuinely covers it → **STALE
MATCHER reported on a healthy install.** The currently-declared tokens are all plain alphanumerics so
this may not be *live* today, but the shape is a trap, and adding `mcp__playwright.*` as a token (the
obvious next edit, since that matcher really does contain it) would trip it.

Suggested fix (small): add an `escapeRe()` helper and escape the token, **or** switch to plain
case-insensitive substring containment (tool names are alphanumeric; `Edit` matching inside a longer
name is harmless in practice). Prefer whichever is fewer characters.

**Bug B — command-path extractor, a false green in the tier whose whole job is catching a hook that
points at nothing.**

```js
const m = target && target.match(/"([^"]+)"/);
const filePath = m ? m[1] : null;
if (filePath && !exists(filePath)) { /* MISSING FILE */ }
```

`install.sh` generates `node "C:/…/hook.js"`, so the first quoted span is the path. But a command
with **no quotes at all** (`node /home/u/.claude/…/hook.js` — valid on Linux, and what a human
hand-editing `settings.json` will write) yields `filePath === null`, so the existence check is
**silently skipped** and the row reports `ok`. Confirmed by direct string test: the unquoted form
extracts `NULL`.

Suggested fix: build the match from the expected filename so it works quoted or not, e.g.
``target.match(new RegExp(`"?([^"\\s]*${escapeRe(exp.file)})"?`))``. One `escapeRe()` helper serves
both bugs.

**Then add the RED demo that would have caught Bug B** — write an unquoted `command` pointing at a
deleted hook file into the sandbox `settings.json` and assert
`expect_row "wiring" "<hook>" "MISSING FILE"`. Call it RED 3b, next to RED 3. Without that demo the
fix is unproven, which is the whole point of this exercise.

### ⚠️ WARNING about my last tool call — the output is WRONG, do not trust it

My final command tried to verify Bug A inline with `node -e "…'\\\\b'…"` inside bash double quotes.
The escaping collapsed to a literal backspace character instead of a `\b` word boundary, so it
reported `Bash` as "not covered" by `Edit|Write|Read|Bash|mcp__playwright.*`, which is false. **The
Bug A half of that output is an artifact of my own broken test, not evidence.** The Bug B half of the
same output (`NULL` for the unquoted command) uses no regex escaping and **is** valid.

Re-verify Bug A from a **script file**, not `node -e`. This bit me four separate times this session
(see §5).

### 4b. The independent review never reported — this is a gate, not a formality

I dispatched a background `coderabbit:code-reviewer` subagent over the full diff. **Its results never
arrived before the session ended, so nothing in this diff has had an independent adversarial pass.**
The brief's methodology point 5 makes that a gate and says to expect it to find something — the two
prior fixes in this repo each shipped a real bug caught only by such a review.

Re-dispatch it. The prompt I used asked it to prioritise, in order: (1) the scope-pinning lock/TTL/
concurrency/corrupt-file behaviour in `_lib.js`, (2) `GIT_COMMIT_RE` false negatives (backticks,
`$()`, `xargs`, `sudo`, `env VAR=x git commit`, aliases, CRLF, `&&git` with no space, `( git commit )`,
`if … then git commit`), (3) `verify.js` false-green paths **including the two above**, (4) whether any
RED demo could pass without proving what it claims, (5) `install.sh`'s deliberate exit-code polarity
inversion + `set -euo pipefail` interaction. Told it explicitly: no style nits, no "add more tests"
or abstractions — this codebase deliberately values minimal code.

Also worth doing: run `bash onboarding/test/red-demos.sh` **twice back-to-back in the same shell** to
confirm the demos are order-independent (`reset_sandbox` now re-copies hooks and the guard, which
fixed one leak; nothing asserts ordering yet). Cheap check, no harness needed.

### 4c. Fix the "All green" wording

`audit-log/2026-08-27-reliability-overhaul-result.md`'s test row says "All green." Qualify it as
**"all green pre-review"** until the subagent reports. Faithful reporting, not early reporting.

---

## 5. Environment gotchas that cost me real time — don't rediscover them

1. **Shell escaping is the #1 hazard here.** `node -e "…"` and `python - <<'PY'` inside this Bash
   tool mangled my content **four times**: a `\n` became a literal newline and left the installed
   hook syntactically invalid for three tool calls; a `\\b` became a backspace char and produced a
   fake test result (§4a); a heredoc died with `unexpected EOF while looking for matching '`. **Write
   the script to a file and run the file.** Every time I did that it worked first try.
2. **Git Bash `/tmp` ≠ Windows Python's `/tmp`.** `sed > /tmp/x` then `python` reading `/tmp/x` fails
   with `FileNotFoundError`. Use the session scratchpad directory for cross-tool temp files.
3. **The installed pack and the repo are separate.** Hooks run from
   `~/.claude/claude-harness/…`; the repo is the source. Editing the repo changes nothing at runtime
   until `install.sh` re-runs. `install.sh --check` diffs them (it currently reports drift, correctly).
4. **A hook file edit takes effect immediately** (fresh `node` spawn per invocation) — that is what
   makes the Task 0 shim technique work without a restart. A `settings.json` change is the thing that
   would need a restart.
5. **The test suite's sandbox is real.** `CLAUDE_HARNESS_HOME_OVERRIDE` / `CLAUDE_HARNESS_TARGET`
   isolate everything; `memory/hooks/test/run.sh`'s Test 13 asserts the real `~/.claude/session`
   gained no files. Keep that property.
6. **`memory-init.js` is a pure read and must create nothing.** Test 1 enforces it and caught my
   first pinning implementation immediately (it called `ensureDir` on `<home>/.claude`). Pinning now
   skips if that directory is absent.
7. **Test fixtures can encode reality wrong.** Test 38 failed on the pinning fix because the suite
   reused one `session_id` across three different project dirs — impossible in reality. I corrected
   the fixtures, not the fix. Watch for more of that shape.

---

## 6. Two decisions that are the human's, not yours

Present both out loud at the gate; don't just point at a file.

1. **`superpowers` plugin (finding #13).** It is on disk but absent from `settings.json`'s
   `enabledPlugins`, so `Skill(superpowers:test-driven-development)` returns `Unknown skill`. I chose
   to **soften the doc** (drop the skill name; TDD-when-called-for is discretionary, so naming no
   skill costs nothing). The alternative is enabling the plugin, which carries a **known open Windows
   `SessionStart` error** (`skills/manifest.yaml` `known_issues`, obra/superpowers#1554) — trading a
   doc inaccuracy for a real per-session error. Zarak's call.
2. **Re-running `install.sh`.** The live install is still on **pre-6.5.0** hooks, so *every fix
   verified above is inert on this machine until it runs*. That is also why `verify.js --live`
   currently reports the fallback session-resolution route rather than the scope-pin route. Re-running
   it is what activates scope pinning, the `goal` nudge, the tightened commit matcher, and the
   vendored `secret-guard.js`. It will also print a `PreToolUse` block for `secret-guard` — but the
   guard installs to the **same path the existing wiring already points at**, so no re-paste is
   actually required on this machine.

---

## 7. Explicitly deferred — do not reopen without new reason

The reasoning is written down in `audit-log/2026-08-27-claims-backstop-triage.md`; `advisor()`
reviewed and endorsed the restraint. Reopening these is how the phase-gate machinery this pack
deliberately deleted gets rebuilt.

- **Web-transport invariants** (`<form method="post">`, `X-Forwarded-For[-1]`). Genuinely detectable,
  arguably meets the mechanization bar, still declined: false-positive surface spans docs, fixtures,
  and templates, and a security gate that cries wolf is worse than an honest prose rule. Build recipe
  is in the triage file if it is ever picked up.
- **Cosmetics** #17 (statusline `$0.00/$0.00` + hardcoded `$` vs `currency: GBP`), #19 (undocumented
  `impeccable@1` hook), #20 (`claude-mem` installed-but-inert), #21 (`'unknown'` session bucket,
  unreachable in normal operation), #22 (Claude Code's own `gitStatus` probe — not this pack's code),
  #25 (HTML-out vs markdown-ask divergence).
- **Finding #12** (Skill-tool dispatch staleness) — an accepted Claude Code platform constraint in
  `skills/manifest.yaml`'s `known_issues`. Incidentally re-confirmed live this session.
- **Expanding `secret-guard`'s pattern set** or making it see `Read`/Bash. Its scope limits are now
  stated honestly in `rules/security-invariants.md` and recorded as structurally unmechanizable in
  the triage file. Do not paper over them with a proxy check.
- **The exit-1-invisibility observation.** I saw a crashed hook (exit 1 + stderr) not visibly surface
  across three tool calls, but that was accidental and untested, and testing it properly needs live
  `settings.json` mutation. It is recorded as an observation only, and **nothing in these fixes
  depends on it** — an unwired hook or stale matcher produces no error under any platform behaviour,
  which is exactly why the `--live` tier checks for written state rather than for errors.

---

## 8. Probe side effects on real state (disclosure — not organic)

- `~/.claude/review-gate/state.json` gained a `t0-manual` key (manual pipe test).
- This session's `reviewSeen` is `true` in project scope because Task 0 invoked `Skill(review-loop)`
  as a wire probe. The skill was **loaded, not run** — that is not evidence a review happened.
- The installed pack was temporarily patched with the payload-dump shim and restored; `diff` against
  the repo copy confirms byte-identical.
- Full capture retained at `%TEMP%/claude/task0-wire-final.jsonl` for the life of that temp dir.
- Sandboxed suites touched no real `settings.json`.

---

## 9. Two auto-memory entries were written

In `C:\Users\SyedHassan\.claude\projects\C--Users-SyedHassan-OneDrive---thrivelearning-com-Documents-claude-harness\memory\`,
plus `MEMORY.md` index lines and a status update appended to
`project_skill_adoption_gap_evidence.md`:

- `project_harness_liveness_selfcheck` — the `--live` self-check exists, when to run it, why its
  green is trustworthy, plus the scope-pin and `secret-guard` facts.
- `feedback_verify_claims_ship_with_their_code` — check the **repo**, not the machine, when a doc
  names a backstop or a `required: true` tool.

---

## 10. TL;DR next actions

1. Re-verify Bug A **from a script file** (not `node -e`), then fix Bug A + Bug B in
   `onboarding/verify.js` with one shared `escapeRe()` helper.
2. Add **RED 3b** (unquoted command → deleted file → `MISSING FILE`) so Bug B's fix is proven.
3. Re-dispatch the independent adversarial review over the whole diff. **Expect findings.** Triage,
   fix, re-verify.
4. Re-run all four suites + `verify.js --live` + `bash -n install.sh`. Run `red-demos.sh` twice in
   one shell for order-independence.
5. Change "All green" → "all green pre-review" in the result summary until (3) is done.
6. `advisor()` before declaring done.
7. Present the human gate: lead with the `secret-guard` finding, then the two decisions in §6. **Wait
   for approval before any commit or push.**
