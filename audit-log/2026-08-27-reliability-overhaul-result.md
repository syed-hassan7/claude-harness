# Reliability overhaul — result summary

**Date:** 2026-08-27. **Version:** 6.5.0. **Brief:** `2026-08-27-reliability-overhaul-prompt.md`.
Companion evidence: `2026-08-27-task0-live-wire-trace.md`, `2026-08-27-claims-backstop-triage.md`.
Full narrative: `CHANGELOG.md` 6.5.0.

## Fixed and verified

Every row has a command/output behind it, not a reading of the code.

| What | Evidence |
|---|---|
| **Task 0** — `review-gate-check.js`'s unconfirmed field names | Traced live via a temp payload-dump shim in the already-wired installed hook. `tool_input.skill` / `.subagent_type` / `.command` **all correct**; a real `Skill(review-loop)` flipped `reviewSeen` in live state. No code change needed. Shim reverted, re-diffed to zero. |
| **Finding #5** — one session's state split across scopes by a Bash `cd` | Root-caused (`input.cwd` is the Bash tool's *persisted* cwd) and fixed in `resolveScope()` alone, so all 10 call sites inherit it. Tests 66–69. **Shown RED first:** disabling pinning reproduces `REGRESSION (audit finding #5): a cd into repo B split session pinS1's state`. |
| **Finding #2** — checkpoint `goal` empty in practice | `memory-init.js` nudge on an empty/whitespace `goal:`. Test 70 covers both directions. |
| **Findings #13 / #14** — rules naming uninstalled skills | Claims corrected, not propped up. `design-lane.md`'s hard gate no longer requires the absent `anti-slop`; `WORKFLOW.md` no longer names the unresolvable `superpowers` skill. Rationale for *not* enabling the plugin recorded (known open Windows `SessionStart` error). |
| **Findings #11 / #9 / #15** — re-verified per methodology | `ponytail` confirmed installed **and** enabled (its `SessionStart` banner fires in this session); the caveman flag is present and now surfaces as `DEAD` if it ever isn't; `verify.js`'s coverage gaps closed by the tiers below. |
| **Finding #24** — 33 claims, 3 backed | Fully triaged in a dedicated file. 13 of the 33 aren't rules at all; 4 newly backed; 6 recorded as structurally unmechanizable; 1 deferred with reasoning. Deliberately restrained. |
| **Deliverable 3** — falsifiable session self-check | `onboarding/verify.js --live`. **13 RED demos** (`onboarding/test/red-demos.sh`), each break asserted to produce its specific RED, green baselines at both ends. |
| Test suites | 80 hook checks + 12 caveman + 5 onboarding + 13 RED demos. All green. |

## Found off the brief's list

1. **`secret-guard.js` was not in this repo — the most serious finding of the pass.**
   `rules/security-invariants.md:5` designates it the *sole* mechanical backstop for all of Tier 0,
   no opt-out. It existed only as an untracked leftover at `~/.claude/hooks/secret-guard.js`, dated
   Jun 20, from the retired v4 harness — not installed by `install.sh`, not checked by `verify.js`.
   **Every fresh install shipped the security claim and none of the hook.** A sixth instance of the
   brief's own thesis, and structurally identical to finding #11 with worse stakes. Now vendored to
   `security/hooks/`, installed unconditionally, and functionally smoke-tested by `verify.js`.

2. **`isGitCommitCommand` false-fired on commit *mentions*.** Two gates trigger off it. All 11 real
   commit shapes already matched (including the heredoc and PowerShell here-string forms this setup
   mandates — a genuine non-finding, verified not assumed), but `cat docs/git-commit-pr.md` and any
   path containing `git-commit` logged a MISS for a commit that never ran. False MISS is the
   trust-eroding direction. Tightened; RED-demoed against the old regex.

3. **A failed `Skill` dispatch does not reach `PostToolUse`.** Probed because the payload carries
   `tool_response.success`, raising the question of whether `Skill(security-audit)` on a machine
   lacking it would satisfy the gate for free. It cannot. Recorded as a **non-finding** so it isn't
   re-chased, and no dead `tool_response` check was added.

4. **The RED-demo harness caught its own bug, of exactly the class it exists to catch.** Its first
   version asserted by grepping the human-readable report for `"secret-guard"`, `"ponytail"`, and
   `"stale"` — all of which appear in a *fully green* report too. Three demos would have passed
   regardless of what `verify.js` did. Rewritten to assert on `--json` status fields, then scoped
   per tier after a second row-name collision surfaced.

5. **Two bugs introduced and caught inside this pass**, recorded rather than quietly fixed, because
   the brief's whole point is that fixes ship bugs:
   - `install.sh`'s new wiring check inverted the exit-code polarity (`verify.js` exits 0 for
     healthy; the bash caller reads 0 as "stale"), so it claimed stale wiring on a known-green
     install. Caught by running `--check` against that install, not by reading the diff.
   - `verify.js`'s new hard exits broke a **fresh** install, where unwired hooks are the expected
     state — `onboarding/test/run.sh` caught it by asserting `install.sh` exits zero on a scratch
     target. Fixed with a `pending-manual-paste` state and a "could not measure ≠ confirmed absent"
     gate on the hard-exit condition.

6. **Observed once, deliberately not headlined:** a hook that crashes at module load (exit 1 +
   stderr) did not visibly surface in the session across three tool calls. Seen accidentally, from
   my own mis-escaped shim, and not tested deliberately — testing it properly needs live
   `settings.json` mutation. Recorded as an observation only. **Nothing in these fixes depends on
   it**: an unwired hook or stale matcher produces no error under any platform behaviour, which is
   precisely why the `--live` tier checks for written state rather than for errors.

## Deferred, explicitly

**Cosmetics from the audit** — logged, not fixed, per the brief's instruction not to spend the
budget on a statusline colour: the permanently-empty `$0.00/$0.00` statusline row and its hardcoded
`$` against a live `currency: GBP` (#17); the undocumented third-party `impeccable@1` `PostToolUse`
hook (#19); `claude-mem` installed-but-inert against its "opt-in only" manifest note (#20); the
`'unknown'` session bucket, unreachable in normal operation since Claude Code always supplies a
`session_id` (#21); Claude Code's own `gitStatus` probe disagreeing with `git rev-parse`, which is
not this pack's code (#22); and the `WORKFLOW.md` HTML-out-vs-markdown-ask divergence (#25).

**One substantive deferral:** mechanizing the web-transport invariants
(`<form method="post">`, `X-Forwarded-For[-1]`). It arguably meets the mechanization bar and is
structurally detectable, and was still declined — its false-positive surface spans docs, fixtures,
and templates, and a security gate that cries wolf is worse than an honest prose rule. Reasoning
and a build recipe are in the triage file so it can be picked up deliberately.

**Not re-opened:** the Skill-tool dispatch staleness (#12) remains a documented Claude Code
platform constraint in `skills/manifest.yaml`'s `known_issues`. Re-confirmed live this session
incidentally — `Skill(security-audit-DELIBERATELY-BOGUS)` returns `Unknown skill`, and the
already-registered skills dispatch fine.

## Probe side effects on real state (disclosure)

Same discipline as the original audit's disclosure section — these are artifacts of verification,
not organic:

- `~/.claude/review-gate/state.json` gained a `t0-manual` key; the sandboxed hook suite also writes
  keys like `probe-only` in its own scratch dirs, not here.
- This session's own `reviewSeen` is `true` in project scope because Task 0 invoked
  `Skill(review-loop)` as a wire probe — the skill was loaded, not run.
- The installed pack at `~/.claude/claude-harness/` was temporarily patched (payload-dump shim) and
  restored; `diff` against the repo copy confirms byte-identical. It remains on the **pre-6.5.0**
  code until `install.sh` is re-run, which is why `verify.js --live` currently reports the
  `newest gate lastSeen` fallback route rather than the scope-pin route.
- Sandboxed suites use `CLAUDE_HARNESS_TARGET` / `CLAUDE_HARNESS_HOME_OVERRIDE` and touch no real
  `settings.json`. The hook suite's Test 13 asserts the real `~/.claude/session` gained no files.

## Not done — requires the human gate

- **Nothing is committed.** All changes are uncommitted working-tree edits.
- `install.sh` has **not** been re-run against the real machine, so the live install is still on
  pre-6.5.0 hooks. Re-running it is what activates scope pinning, the `goal` nudge, the tightened
  commit matcher, and the vendored `secret-guard.js`.
