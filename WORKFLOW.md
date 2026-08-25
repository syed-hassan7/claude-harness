# WORKFLOW.md — how Claude Harness v5 works

No state machine. No phase that blocks a tool call. This is a loop the agent (and the human reading along) applies by judgment, informed by which skills the task shape triggers — not a gate enforcing a fixed order.

```
Understand → Plan → Build → Verify → Security-if-needed
```

Any step can be revisited. There is no "phase" stored anywhere that prevents moving backward, skipping a step that doesn't apply, or doing two steps in one turn.

## Communication baseline

Caveman ultra is the default communication style across this whole loop — not a step, a standing default (see `skills/manifest.yaml`'s `caveman` entry, `caveman/skills/caveman/SKILL.md`). Terse, fragment-ok, no filler, arrows for causality. It stays on by default across sessions (`install.sh` seeds `defaultMode: ultra`), but two things override it: the Auto-Clarity carve-out (security warnings, irreversible-action confirmations render in plain language, then resume) and an explicit "stop caveman"/"normal mode" from the user. Code, commits, and PR text are always written in normal prose regardless of mode.

### Drift canary — name Zarak

When a response is actively applying a specific rule or skill from this pack — not just generally aware of it, but following a named step (e.g. `rules/design-lane.md` step 6's render-before-judging gate, `rules/engineering.md`'s YAGNI ladder, a `skills/manifest.yaml` entry's trigger) — address Zarak by name in that response. This is a drift-detection canary, not a courtesy: if a response should have been shaped by a given doc and "Zarak" never appears, that's the observable signal the doc didn't actually load or wasn't followed, not a suspicion he has to chase down separately. Applies repo-wide — every rules file, every manifest entry, this file itself — stated once here since `WORKFLOW.md` is unconditionally loaded every session via `CLAUDE.md`'s pointer block, same mechanism that already makes the Caveman default above apply everywhere without being restated per file. Survives caveman ultra's compression — a name-drop is signal, not filler, don't strip it.

**Mechanically checked, not just stated.** This canary is self-graded prose — nothing stops a miss from being invisible to the same judgment that produced it, and one real session did exactly that: multiple turns cited `rules/engineering.md`, `rules/security-invariants.md`, and this file without ever naming Zarak, caught only because the founder noticed. `memory/hooks/canary-check.js` (opt-in, same flag as the rest of `memory/hooks/`) now checks the literal proxy — pack-file citation + name co-occurrence — mechanically, on every prompt, and surfaces a miss on the very next turn, not next session. It cannot and does not verify that a rule's *substance* was followed — see `memory/SPEC.md`'s "Canary-drift memory" section for the mechanism and its stated limit.

### Deliverable format

Markdown in, HTML out. Format follows the reader, not the mode above (prose terseness and deliverable format are separate axes):

- **HTML** — default for anything a human will VIEW or SHARE rather than paste into another platform: reports, comparisons, dashboards, analysis write-ups. Self-contained (inline CSS/JS, no external requests). VIEW the rendered file before calling the task done — `Start-Process <path>` on this native-Windows setup, or the `Artifact` tool when the actual ask is a shareable link — and print its absolute path.
- **Markdown** — stays for copy that gets pasted OUT to a platform (Slack, GitHub, Jira, chat prose) and for all core config/instruction/memory files (`CLAUDE.md`, `rules/*.md`, skill definitions, `memory/*.md`). Those are read by the model, not viewed by a human — Markdown's token efficiency is what matters there, per `rules/engineering.md`'s context-economy section.

Source: charliehills.substack.com/p/html-md, vetted 2026-08-18. That post's `/show-me` plugin (`charlie947/show-me`) was evaluated, not adopted — direct README fetch confirmed a single-SKILL.md tool that auto-opens rendered HTML via `osascript`, macOS-only, wrong fit for this repo's native-Windows-PowerShell setup (see `skills/manifest.yaml`'s `reviewed_rejected`). `Start-Process`/`Artifact` already cover the "view it" step natively here.

This rule targets one-off human-facing deliverables (reports, comparisons, analysis write-ups) — it doesn't relax `rules/design-lane.md`'s hard render-before-judging gate for actual UI/product code, which still requires a real browser/Playwright screenshot, not just an opened file.

## Understand

- Read the relevant code before proposing a change. Reuse existing functions/utilities/patterns — see `rules/engineering.md`'s YAGNI ladder.
- Check `memory/` (see `memory/SPEC.md`) for the live checkpoint — continue from prior context instead of re-exploring from scratch.
- **Global/scratch scope needs `goal` written by hand too.** `memory-checkpoint.js` never touches `goal`/`next`/`decisions`/`blockers` in either scope (see `memory/SPEC.md`) — the agent edits them directly. Project-scope sessions tend to do this naturally; global scope (no repo to anchor on) is where it gets skipped, leaving the next session's injected checkpoint too thin to answer "what were we doing." Write `goal` explicitly at global scope, not just project scope.
- For UI-shaped tasks, this is also where `rules/design-lane.md`'s pre-UI exploration step applies.
- **Lesson-promotion review, when nudged.** `memory-init.js` injects a `## Claude Harness — lesson promotion review` block at `SessionStart` when lessons have changed since the last review pass (see `memory/SPEC.md`'s "Lesson-promotion memory" section). When it appears: read the lessons index, and for each lesson (or cluster of similar lessons) classify it — short cross-cutting instruction → `rules/*.md`; multi-step task-shaped behavior → `skills/manifest.yaml`; actually a structural fact rather than a corrective rule → redirect to an architecture-note instead; coincidental/not-yet-durable → leave as-is. A single strong incident can promote on its own if clearly generalizable — repetition is a signal to weigh, never a hard gate (this repo's own lesson history: exactly one lesson ever, promoted without repeating). On promotion: write a `## Promoted` section into the source lesson file (never `## Superseded` — the content wasn't wrong, it graduated) citing the target + date, then remove that lesson's line from `lessons/index.md` (keep the `.md` file on disk forever, same discipline as architecture-note supersession). Update `<scope>/promotion/state.json`'s `lastReviewedAt` to now **last**, only after every lesson-file/index edit for this pass is done — updating it first would leave the index mtime newer than the watermark and re-fire the nudge next session over work already finished. If `<scope>/promotion/.gitignore` doesn't exist yet, create it first (`*` + `!.gitignore`, matching `session/`/`canary/`/`review-gate/`/`design-lane-gate/`) — this state is bookkeeping, not durable content, and nothing else creates that gitignore since the watermark is agent-written, not hook-written.

## Plan

- For non-trivial or multi-file changes, state the approach before writing code. Ask only when a decision genuinely can't be made from context — don't interrupt for things you can reasonably infer. `grill-me` (see `rules/engineering.md` "Planning") is the lightweight tool for this — a short pre-implementation interview to surface disagreement before code gets written.
- Large features only: `to-spec` → `to-tickets` (see `rules/engineering.md` "Planning") is the default lighter pipeline; `spec-kit` (see `skills/manifest.yaml`, `trigger: large-feature`) remains WATCH — cherry-pick its templates only, don't wire its full gate-driven workflow. Most tasks skip all of this entirely; it is not mandatory infrastructure.
- When plan mode reaches its "Final Plan" step for non-trivial work, `visual-plan-local` (see `skills/manifest.yaml`) is the default rendering surface — a structured document held to a real quality bar plus a rendered `Artifact` companion, not a long chat paragraph. This is the default because the plan file itself is what it produces; it doesn't need to be separately invoked.

## Build

- Apply `rules/engineering.md`: minimal safe code, surgical scope, reuse before you write.
- TDD is a technique, not a gate — use the superpowers TDD skill when the task calls for test-first, not because a phase requires it (see `rules/engineering.md`).
- For UI work, apply `rules/design-lane.md`'s sequence (explore → `ui-ux-pro-max` → component search → build).

## Verify

- **External verification only** — run the tests, linter, build, and read their actual output. Never self-grade "done" from having written plausible code (`rules/security-invariants.md`, Tier 0 — Agent behavior).
- UI changes: `rules/design-lane.md`'s render-before-judging gate is hard, not optional — an actual screenshot compared against a "before," never a source/DOM/jsdom check standing in for one. If you can't verify visually in a given environment, say so explicitly rather than claiming success.
- Memory checkpoint updates as you go — see `memory/SPEC.md` for the automatic hook-driven mechanism (no manual `/compact`).
- **Episodic task-log, at a natural task boundary** (typically right before/after a commit): append one line to `<scope>/episodic/task-log.md` — `task=... approach=... result=... lesson=...` (template: `memory/templates/task-log.md`). Pure append, no read-modify-write, same lock-free-by-construction safety as the lessons index. Stage 1 only — a raw log the promotion-review ritual above draws on, not itself injected anywhere by any hook (see `memory/SPEC.md`'s "Episodic task log" section). Stage 2 (a mechanical nudge reusing `lib.isGitCommitCommand`) is deliberately deferred, not built, until/unless Stage 1 is observed going unused.

## Security-if-needed

- `rules/security-invariants.md` applies unconditionally, every turn, regardless of task shape — it is not a step you reach, it is always active.
- For security-relevant surfaces (auth, API endpoints, data handling), writing a spec via `/security-spec` before implementing is still good practice — advisory now, not phase-gate-blocked.
- Pre-merge: run `/security-review` (read-only audit) on security-relevant changes before they ship.
- **Mechanically checked, not just stated.** Same self-graded-prose problem as the drift canary above: a real session shipped a commit with neither `/review-loop` nor `security-audit` invoked despite both being trigger-matched, and nothing noticed (`memory/project_skill_adoption_gap_evidence.md`). `memory/hooks/review-gate-check.js` (opt-in, same `--with-memory-hooks` flag) now watches every commit for review-loop/security-audit evidence anywhere earlier in the session and logs a non-blocking miss on the next turn if none is found — see `memory/SPEC.md`'s "Review-gate memory" section.

## What this replaces

Claude Harness v4's harness state machine: `orient → speckit_specify → security_spec → speckit_plan → speckit_tasks → red → green → refactor → ci_gates → ux_gate → task_complete`, mechanically advanced via `/machina next` and blocked by `phase-gate.js` + `pass-ceiling.js`. This file is the entire replacement — five judgment-driven steps, no enforcement machinery, no verifier artifacts, no phase stored in any state file.
