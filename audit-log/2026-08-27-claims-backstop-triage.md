# Finding #24 — every "hard / always / mandatory" claim, triaged against a mechanical backstop

**Date:** 2026-08-27. **Source of the list:**

```bash
grep -nE "\b(hard|always|mandatory|must|never|unconditional|every turn|not optional)\b" rules/*.md WORKFLOW.md
→ 33 hits
```

The external audit's finding #24 reported "33 hard/always/mandatory claims, only 3 with any hook
backing." That count is accurate as a grep result but overstates the problem: **13 of the 33 hits
are not rules at all** — they are section headings, historical root-cause notes, research
rejections, and doc-structure prose that merely contain the word "always" or "never." Mechanizing
those is not possible because there is nothing to comply with.

Triage criteria are the pre-existing ones from `project_skill_mechanization_audit` (2026-08-25),
not new ones invented for this pass:

> **explicit written rule ∧ real stakes if skipped ∧ currently zero backstop**

The 2026-08-25 pass deliberately left ~31 manifest entries as agent judgment. That restraint is
the point — this pack deleted a phase-gate state machine on purpose, and reflexively gating
everything rebuilds it. Four claims met the bar this pass. They got hooks. The rest did not, and
the reason is recorded per row so a future pass doesn't re-litigate from zero.

## Summary

| Disposition | Count |
|---|---|
| Not a rule (heading / history / research note / framing prose) | 13 |
| Already had a mechanical backstop before this pass | 5 |
| **Newly backed by this pass** | **4** |
| Structurally unmechanizable — self-graded, no observable exists | 6 |
| Judgment-only by the criteria (no crisp trigger, or needs code semantics) | 4 |
| Deferred candidate, reasoning recorded | 1 |

## Newly backed by this pass

| Claim | Location | New backstop |
|---|---|---|
| Tier 0 secrets — "hard stop, no exceptions" | `security-invariants.md:11-18` | `secret-guard.js` **vendored into this repo**, installed unconditionally by `install.sh`, and `verify.js`'s `secret-guard` tier now proves it is present, wired, AND blocking (live smoke test, exit 2). Previously the rule's designated sole backstop existed only as an untracked v4 leftover on one machine — every fresh install shipped the claim and none of the hook. |
| Ponytail "always on" baseline | `engineering.md:3,9` | `verify.js`'s `ponytail` tier, now a **hard** tier: a missing `required: true` skill exits nonzero instead of reporting green (audit finding #11's exact failure). |
| Caveman "ACTIVE EVERY RESPONSE… no revert" | `WORKFLOW.md:13`, caveman SKILL.md | `verify.js --live` treats an absent `.caveman-active` flag as **DEAD**, not "not yet exercised" — the silent kill-switch of finding #9 is now observable mid-session rather than only via a missing statusline badge. |
| "Global/scratch scope needs `goal` written by hand" | `WORKFLOW.md:36` | `memory-init.js` nudge when the injected checkpoint's `goal:` is empty or whitespace. The doc predicted this failure in its own text and the audit found it live (finding #2). |

## Already backed before this pass

| Claim | Backstop | Note |
|---|---|---|
| Render-before-judging "hard gate" | `design-lane-gate-check.js` | Post-hoc, non-blocking, and its evidence test is satisfiable by reading any `.png`. Known and documented; not re-opened. Its `anti-slop` dependency is fixed as a doc correction below. |
| Pre-commit review evidence | `review-gate-check.js` | Field names confirmed on the wire this pass — see `2026-08-27-task0-live-wire-trace.md`. |
| Drift canary | `canary-check.js` | Proxy only (citation ∧ name co-occurrence), self-labelled as such in `WORKFLOW.md:19`. |
| HTML-out default doesn't relax the design gate | `design-lane-gate-check.js` | Same hook as above. |
| Lesson-promotion review "when nudged" | `memory-init.js` watermark nudge | Shipped 6.2.0. |

## Structurally unmechanizable — recorded as such, not as debt

There is no observable that distinguishes compliance from imitation for these. The audit reached
the same conclusion and labelled it **unverifiable-by-construction**; that label is correct and is
adopted here rather than papered over with a hook that would only check a proxy.

| Claim | Location | Why no hook can check it |
|---|---|---|
| Never read a secret's value from disk | `security-invariants.md:15,18` | `secret-guard.js` is `PreToolUse` on `Edit|Write` and reads only write content. A `Read` of a populated `.env`, a Bash `cat`, or a secret pasted into chat are all outside it. The rule's own text at `:45` already concedes this. |
| External verification before "done" | `security-invariants.md:38`, `WORKFLOW.md:54` | "I ran the tests and read the output" is indistinguishable from claiming to have. |
| Sub-tool confidence ≠ user authorization | `security-invariants.md:40` | Requires knowing what the user authorized, which no hook payload carries. |
| Match scope of destructive actions | `security-invariants.md:39` | "Proportionate" is a judgment, not a predicate. |
| Auth/data invariants (404-not-403, rate limits, UUIDs, query scoping) | `security-invariants.md:22-26` | Needs whole-program semantics. A regex-level check would produce false confidence, which is worse than a rule known to be judgment-only. |
| Secrets in env vars, never logged | `security-invariants.md:25` | The literal-in-source half IS covered by `secret-guard.js`; "never logged" is not statically decidable. |

## Judgment-only by the criteria

- **CI/test-infra: reproduce locally before pushing** (`engineering.md:64`) — no crisp trigger. "Is this change CI-infra?" has no mechanical answer, and a hook guessing it would fire on unrelated pushes.
- **N-variant judge panel** (`design-lane.md:39`) — explicitly gated behind user opt-in; firing on its own is the documented anti-goal.
- **`to-spec`/`to-tickets`, `spec-kit` WATCH** (`WORKFLOW.md:43`) — the doc states most tasks skip it entirely; it is guidance, not an obligation.
- **Reading `.env.example` is allowed** (`security-invariants.md:16`) — a permission, not a duty. Nothing to enforce.

## Deferred candidate — with the reasoning, so it can be picked up

**Web transport invariants** (`security-invariants.md:30-32`): `<form>` with sensitive fields must
be `method="post"`; trust `X-Forwarded-For[-1]`.

This is the one row that arguably *does* meet all three criteria, and it is structurally
detectable — a `Write`/`Edit` whose content contains a `<form>` without `method="post"` is exactly
the same shape as `design-lane-gate-check.js`'s existing native-control detection, which already
works. Deferred anyway, for two stated reasons:

1. **False-positive surface is large and the payload is content-blind.** Forms appear in docs,
   fixtures, tests, email templates, and framework examples. `design-lane-gate-check.js`'s
   native-control nudge gets away with a loose check because it is a *nudge about a blind spot*;
   a security invariant that cries wolf on a test fixture gets tuned out, and a tuned-out security
   gate is worse than an honest prose rule. That is the same trust-erosion argument that motivated
   tightening `GIT_COMMIT_RE` in this very pass.
2. **Scope.** This overhaul's mandate is making the existing mechanical layer provably alive, not
   adding lanes to it. Adding a new gate in the same pass that fixes four broken ones would ship
   an unproven gate alongside the proof machinery — precisely the pattern that produced two
   bugs-in-the-fix last week.

If picked up later: build it as a `PostToolUse` nudge on `Edit|Write`, reuse `gatePaths`/
`appendGateLog` from `_lib.js`, exclude paths matching test/fixture/docs conventions, and write the
adversarial tests (form in a markdown code block, `method` set via a framework prop, uppercase
`METHOD="POST"`) *before* the detection logic.

## Correctness fixes to the claims themselves

Two claims named skills that are not installed. The honest fix is to correct the claim, not to
install a plugin nobody asked for — a rule that names an unavailable tool is a rule that cannot be
followed, and pretending otherwise is how the `ponytail`/`secret-guard` gaps happened.

| Finding | Claim | Fix |
|---|---|---|
| #14 | `design-lane.md:25`'s **hard gate** ends "run `anti-slop`'s Delivery Gate" — `anti-slop` is `required: false` and not installed | Reworded so the screenshot is the hard requirement and `anti-slop` is the optional adjunct it actually is. The gate no longer claims a step half of which cannot execute. |
| #13 | `WORKFLOW.md:49` — "use the superpowers TDD skill when the task calls for test-first"; the plugin is on disk but not in `enabledPlugins`, so it is not callable | Reworded to describe the practice (test-first when it fits) without naming an unresolvable skill as the way to do it. TDD-when-called-for is discretionary — not load-bearing — so removing the name costs nothing. Enabling the plugin was the alternative and was rejected: it carries a known open Windows `SessionStart` error (`skills/manifest.yaml` `known_issues`, obra/superpowers#1554), so it would trade a doc inaccuracy for a real per-session error. Flagged for the human gate. |
