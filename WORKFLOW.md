# WORKFLOW.md — how Claude Harness v5 works

No state machine. No phase that blocks a tool call. This is a loop the agent (and the human reading along) applies by judgment, informed by which skills the task shape triggers — not a gate enforcing a fixed order.

```
Understand → Plan → Build → Verify → Security-if-needed
```

Any step can be revisited. There is no "phase" stored anywhere that prevents moving backward, skipping a step that doesn't apply, or doing two steps in one turn.

## Understand

- Read the relevant code before proposing a change. Reuse existing functions/utilities/patterns — see `rules/engineering.md`'s YAGNI ladder.
- Check `memory/` (see `memory/SPEC.md`) for the live checkpoint — continue from prior context instead of re-exploring from scratch.
- For UI-shaped tasks, this is also where `rules/design-lane.md`'s pre-UI exploration step applies.

## Plan

- For non-trivial or multi-file changes, state the approach before writing code. Ask only when a decision genuinely can't be made from context — don't interrupt for things you can reasonably infer. `grill-me` (see `rules/engineering.md` "Planning") is the lightweight tool for this — a short pre-implementation interview to surface disagreement before code gets written.
- Large features only: `to-spec` → `to-tickets` (see `rules/engineering.md` "Planning") is the default lighter pipeline; `spec-kit` (see `skills/manifest.yaml`, `trigger: large-feature`) remains WATCH — cherry-pick its templates only, don't wire its full gate-driven workflow. Most tasks skip all of this entirely; it is not mandatory infrastructure.

## Build

- Apply `rules/engineering.md`: minimal safe code, surgical scope, reuse before you write.
- TDD is a technique, not a gate — use the superpowers TDD skill when the task calls for test-first, not because a phase requires it (see `rules/engineering.md`).
- For UI work, apply `rules/design-lane.md`'s sequence (explore → `ui-ux-pro-max` → component search → build).

## Verify

- **External verification only** — run the tests, linter, build, and read their actual output. Never self-grade "done" from having written plausible code (`rules/security-invariants.md`, Tier 0 — Agent behavior).
- UI changes: actually exercise the feature (browser, Playwright) before calling it done. If you can't verify visually in a given environment, say so explicitly rather than claiming success.
- Memory checkpoint updates as you go — see `memory/SPEC.md` for the automatic hook-driven mechanism (no manual `/compact`).

## Security-if-needed

- `rules/security-invariants.md` applies unconditionally, every turn, regardless of task shape — it is not a step you reach, it is always active.
- For security-relevant surfaces (auth, API endpoints, data handling), writing a spec via `/security-spec` before implementing is still good practice — advisory now, not phase-gate-blocked.
- Pre-merge: run `/security-review` (read-only audit) on security-relevant changes before they ship.

## What this replaces

Claude Harness v4's harness state machine: `orient → speckit_specify → security_spec → speckit_plan → speckit_tasks → red → green → refactor → ci_gates → ux_gate → task_complete`, mechanically advanced via `/machina next` and blocked by `phase-gate.js` + `pass-ceiling.js`. This file is the entire replacement — five judgment-driven steps, no enforcement machinery, no verifier artifacts, no phase stored in any state file.
