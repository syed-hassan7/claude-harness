# Claude Harness — Full Reliability Overhaul (standalone agent prompt)

**Author:** written 2026-08-27 by a Claude Code session that had just fixed the four items an
external audit found broken, then had two of those fixes themselves found buggy by a second
reviewer, twice. This prompt is the direct output of that experience — it exists because
"fix the bugs we found" turned out not to be the same job as "make this reliable."

**How to use this:** paste this whole file as your task, or point a fresh Claude Code session
at it (`Read` this file first). It is written to be self-contained — you should not need to ask
the user what's broken before you start; that's answered below. You SHOULD use your own
judgment, web research, and exploration beyond what's listed here — see "Latitude" at the end.
This is a floor, not a ceiling.

---

## The thesis (read this first, it should organize everything else)

Every real defect found in this pack across two audit passes lived in **one structural gap**:
this pack's hooks are tested by piping synthetic JSON into them (`memory/hooks/test/run.sh`),
and nothing — not the test suite, not code review, not the manifest's own claims — verifies
that a **real, live Claude Code session** actually invokes them the way the fixtures assume.
Five for five, the failures were exactly the gap between "the unit test's fixture" and "what a
real session actually sends or contains":

1. `review-gate-check.js`'s marker regex was tested against a hand-written transcript line.
   No fixture ever contained Claude Code's real injected `agent_listing_delta` boilerplate —
   because building that fixture requires looking at a real transcript, not writing one.
2. `caveman-mode-tracker.js`'s kill-phrase test never fed it real prose containing quotes,
   negation, or contractions — because nobody sat down and tried to write a paragraph a real
   user would type, they wrote the two words the regex was built to catch.
3. `ponytail` being "installed" was never checked against an actual fresh Claude Code session's
   skill listing — `required: true` in a YAML file was trusted as documentation of intent, not
   verified as documentation of reality.
4. `install.sh --check`'s wiring verification checked file-copy diffs and filename presence,
   never whether the *matcher value* a hook is wired under is current — because nobody asked
   "what if the file is right but the wiring around it is stale."
5. Two fixes to (1) and (2) above each shipped their own bug, caught only by a second,
   independent reviewer: a path-translation failure that only manifests on the real machine
   (Git-Bash path handed to native `node.exe`), and a regex edge case only real English prose
   exposes (an apostrophe inside a genuine quoted span). Both were invisible to the fix
   author's own testing, because the fix author's tests were built from the same mental model
   that had the blind spot.

**Your mission is not "fix the list below."** It's: eliminate this class of gap, everywhere in
the pack, and — this is the part that matters most — build something that keeps eliminating it
automatically, in every session, on every project that installs this pack, going forward. A
one-time fix that isn't independently verified against real session behavior will look done and
not be done. That already happened once in this repo, this week, twice in a row.

---

## Load this context before you touch anything

Read these, in order, before forming an opinion on what to fix:

1. `audit-log/2026-08-27-external-audit.md` — the full original 27-finding audit this whole
   effort responds to. Copied into this repo specifically so a fresh session can read it (the
   original lived in a different session's scratchpad and would otherwise be unreachable).
2. `CHANGELOG.md`'s `6.4.0` entry — what was fixed in response, including the two rounds of
   bugs-in-the-fix and how they were caught. Read this so you don't re-discover and re-fix
   things that are already closed.
3. This user's Claude Code auto-memory, if you're running as the same user in the same
   environment (check for a `SessionStart`-injected memory index, or read directly):
   - `feedback_adversarially_test_mechanical_gates` — the generalized lesson from this
     incident: test gate hooks against real channel noise, not happy-path fixtures, and don't
     trust a green suite the same reasoning that wrote the code also wrote the tests for.
   - `project_skill_adoption_gap_evidence` — history of `review-gate-check.js` specifically,
     including its 2026-08-25 build and 2026-08-27 breakage.
   - `project_skill_mechanization_audit` — **the criteria for when a skill/rule deserves a
     mechanical hook backstop at all**: explicit written rule ∧ real stakes if skipped ∧
     currently zero backstop. Situational/discretionary triggers (most of the manifest) do
     NOT meet this bar. Read this before mechanizing anything new — the 2026-08-25 pass
     deliberately left ~31 entries as agent judgment, not oversight. Don't rebuild the
     phase-gate machinery this pack tore down by reflexively gating everything.
   - `skills/manifest.yaml`'s `known_issues` block — accumulated, already-accepted findings
     (e.g. Skill-tool dispatch staleness) that are NOT open work, just documented constraints.
     Don't re-open these without new evidence they've changed (Claude Code platform updates
     might have changed this one specifically — see the web-research section below).

Skipping this step means re-deriving conclusions that already cost real tokens to reach once,
and risks contradicting decisions that were made deliberately (e.g. the caveman override phrase
staying, per the founder's explicit confirmation recorded in `manifest.yaml`'s caveman entry —
don't relitigate that without re-confirming with the user first).

---

## Task 0 — close the one unverified risk that's already in committed code

This is not hypothetical, and it's not on the "known gap inventory" below because it's higher
priority than all of it: `review-gate-check.js` (as of commit `1dfa5d2`) decides whether a
review happened by checking `input.tool_name === 'Skill'` and reading `input.tool_input.skill`
/ `input.tool_input.subagent_type`. Those field names were inferred from this session's own
system-prompt tool schemas, **not confirmed against a live PostToolUse hook payload** — a
second reviewer said so explicitly and it was shipped anyway on secondary evidence.

**Do this first:** in a real Claude Code session, invoke a `Skill` tool call and an `Agent` tool
call, and capture — via a temporary logging shim in the hook, or any other real means — exactly
what `tool_name` and `tool_input` look like on the wire for each. Confirm or correct
`review-gate-check.js`'s field names against that live trace. If they're wrong, the gate is
dead again, silently, with the old transcript-scan fallback already deleted — worse than before
the fix, because now it fails with no fallback at all. This must be the first thing you verify,
not the last.

---

## Known gap inventory (a floor — go find more, don't stop here)

From `audit-log/2026-08-27-external-audit.md`, with fix status. **Load-bearing items** (claims
of `required: true`, "hard gate", "always-on", "mandatory") get full adversarial treatment per
the methodology below. **Cosmetic items** (marked) get logged and explicitly deferred — say so
in your final report, don't silently spend the whole budget on a statusline color.

| # | Finding | Status as of `1dfa5d2` | Priority |
|---|---|---|---|
| 7 | `review-gate-check.js` dead gate | Fixed, but see Task 0 above | **verify Task 0 first** |
| 9 | `caveman-mode-tracker.js` kill-switch | Fixed (3 rounds) | re-verify per methodology |
| 11 | `ponytail` never installed | Fixed | re-verify per methodology |
| 12 | `visual-plan-local`/`onboarding` unresolvable via `Skill` tool | Known, accepted (platform constraint) | check if still true — see web research |
| 2 | Checkpoint `goal`/`next` fields go empty in practice | **Open** | load-bearing (WORKFLOW.md predicts this exact failure) |
| 5 | Hook scope follows Bash-tool cwd, splits one session's state across scopes | **Open** | load-bearing |
| 13 | `superpowers` TDD skill referenced by WORKFLOW.md, not enabled | **Open** | check: is it load-bearing, or should the reference be removed? |
| 14 | `anti-slop` named inside design-lane.md's "hard gate", not installed | **Open** | load-bearing — the gate explicitly can't fully run without it |
| 15 | `onboarding/verify.js`'s coverage gaps beyond what 6.4.0 already added | Partially fixed (ponytail tier added) | check what's still uncovered |
| 24 | 33 hard/always/mandatory claims across `rules/*.md` + `WORKFLOW.md`, only 3 had any hook backing (2 of those the ones that were broken) | **Open, structural** | this is close to your real mandate — see below |
| 17 | Statusline `$0.00/$0.00` row, hardcoded `$` vs `currency: GBP` | Open | **cosmetic — log and defer** |
| 19–22 | Undocumented third-party hook, claude-mem touched, `unknown` session bucket, gitStatus mismatch | Open | **cosmetic — log and defer** |

On #24 specifically: that's the real shape of "once and for all." 33 claims, 3 with any
mechanical backing. You are not expected to mechanize all 33 — re-read
`project_skill_mechanization_audit`'s criteria first, most of them are correctly judgment-only.
But every one that DOES meet the criteria (explicit rule ∧ real stakes ∧ zero backstop) and
currently has none should get one, following the same structural-not-textual pattern
`design-lane-gate-check.js` and the fixed `review-gate-check.js` now both use.

---

## Methodology requirements (non-negotiable)

1. **Empirical, not read-and-reasoned.** For every claim you fix or verify, produce the
   command/output that proves it, the way this session's own commits do (see `1dfa5d2`'s diff
   and the CHANGELOG entry for the pattern to follow). "I read the code and it looks right" is
   not evidence — this exact failure mode is what shipped two buggy fixes this week.
2. **Adversarial test-writing.** For every gate/hook, write the test that tries to make it
   *fail to detect* a real violation — a mention instead of an invocation, a quoted phrase, a
   stale wiring config, a partially-completed install — not just the happy path. If you can't
   think of an adversarial case for something, that's a signal to look harder, not to skip it.
3. **The self-check must be falsifiable, or you're rebuilding `onboarding/verify.js`.**
   `verify.js` reported all-green through four broken findings before this pass. Whatever
   session-level "is the harness actually alive" mechanism you build MUST be demonstrated going
   **RED** against a deliberately-broken install before you trust any GREEN it reports — one
   red demonstration per thing it claims to check (unwire a hook, stale a matcher, uninstall
   ponytail, corrupt a checkpoint, etc.). A checker that has never been shown failing has not
   been shown working.
4. **Verify against real Claude Code behavior, not assumed schemas.** Where you're not certain
   what a hook actually receives on stdin (see Task 0), look it up or trace it live — don't
   guess from a tool's chat-facing description.
5. **Independent review, twice if needed.** This session's own two rounds of external review
   each found a real bug the author's self-review missed. Budget for at least one adversarial
   review pass on your fixes (a fresh subagent, or CodeRabbit if reachable) before considering
   anything done — expect it to find something, and don't be surprised or defensive if it does.
6. **Call `advisor()`** (or equivalent) before committing to your fix architecture, and again
   before declaring the whole effort done — this session used it twice and both calls changed
   the plan for the better.

---

## Web research — specific, not generic

Don't just "research the web" broadly. These are the actual open questions worth looking up:

- **Claude Code's real hook I/O contract** for `PostToolUse` on `Skill` and `Agent` tool calls
  — official docs, changelogs, or GitHub issues that pin down `tool_name`/`tool_input` field
  shapes authoritatively, so Task 0's live trace has something to cross-check against.
- **Whether the Skill-tool-dispatch staleness** (`skills/manifest.yaml`'s `known_issues`,
  finding #12) has been resolved or changed by a Claude Code platform update since
  2026-08-25 — this genuinely might have shipped a fix by the time you're reading this.
- **Prior art on self-verifying CLI/agent tooling installs** — how do other agent-harness or
  dotfiles-style projects (this manifest already vets several: `ponytail`, `superpowers`,
  various `mattpocock/skills` entries) handle "prove the thing you installed actually works,"
  if at all? Is there a pattern worth adapting rather than inventing from scratch?
  `skills/manifest.yaml`'s already-researched entries and `skills/RESEARCH.md` are a starting
  point for what's already been vetted in this space — don't re-vet from zero.
- **Integration-testing patterns for Claude Code hooks specifically** — is there a documented
  way to run a hook against a *real* session transcript/tool-call fixture captured from actual
  usage, rather than hand-written JSON? If Anthropic or the community has published anything on
  this, it directly closes the structural gap the thesis above describes.

---

## Deliverables

1. A concrete, mergeable diff — not a report. Every fix ships with the adversarial test that
   proves the bug existed and the fix closes it (same pattern as `1dfa5d2`).
2. Task 0's live-trace result, documented, with `review-gate-check.js` corrected if needed.
3. A new session-level self-check mechanism, falsifiable per methodology point 3, that any
   session on any project with this pack installed can invoke to confirm the mechanical layer
   is alive *right now* — cheap enough to run routinely, not a full re-audit every time.
4. Updated `CHANGELOG.md`, `memory/SPEC.md` (or wherever the relevant mechanism is documented),
   and this user's auto-memory (project + feedback entries) — don't let this become undocumented
   tribal knowledge the way the original gaps did.
5. A short human-readable summary distinguishing: fixed-and-verified, deferred-and-why
   (cosmetics), and anything you found that wasn't on this list.
6. **Explicit human gate before any commit or push** — same rule as every session on this repo,
   not relaxed because this is a big effort. Present findings, wait for approval.

---

## Latitude

This prompt is a floor, not a spec to follow mechanically. If you find something not listed
here — a sixth instance of the same structural gap, a better architecture for the self-check
than what's implied above, a reason one of the "known gap" items doesn't actually need fixing —
pursue it and say why. The thesis is the constraint that matters; the gap inventory is a
starting point, not a checklist to close and stop. If research surfaces a fundamentally
different and better approach than anything sketched here, take it.
