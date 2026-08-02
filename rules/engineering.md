# Engineering rules

Claude Harness's engineering lane is **Ponytail's YAGNI ladder as the always-on baseline**, plus a set of triggered skills covering debugging, code review, static analysis, dependency hygiene, performance, and commit/PR lifecycle — verified real in `skills/RESEARCH.md` §1 and §7. Ponytail alone covers "write less code"; it does not cover reviewing it, debugging it, or shipping it safely. The rest of this file is the answer to that gap.

All of this is advisory prose, not a mechanical gate — no hook blocks a write for violating it.

## Baseline: Ponytail (always on)

[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) — confirmed real (`skills/RESEARCH.md` §1: SKILL.md read directly, npm package `@dietrichgebert/ponytail`, ~20 agent adapters).

### The ladder (apply in order, every change)

1. **Does this need to exist at all?** Prefer deleting or not-writing code over adding it.
2. **Is there an existing function/utility/pattern that already does this?** Reuse before you write.
3. **Minimal correct implementation** — no speculative abstraction, no future-proofing for requirements nobody asked for.
4. **Surgical scope** — edit only the logic the task requires. No drive-by formatting, renames, or refactors bundled into an unrelated change.
5. **One logical concern per commit.**

**Not `code-simplifier` too — pick one.** Corrected 2026-08-02: Anthropic's own first-party `code-simplifier` plugin was originally listed as "ship alongside Ponytail." Adversarial review found a real, documented duplicate-ownership conflict — a third-party curator dropped `code-simplifier` specifically because it and Ponytail compete for the same "simplify" job (see `skills/manifest.yaml`). Ponytail is the default; treat `code-simplifier` as an alternative to try instead of, not with, it.

## Debugging — methodology + mechanism

**Methodology:** `superpowers`' `systematic-debugging` skill (see below) — 4-phase root-cause process, "no fixes without root cause first." This is the manifest's answer to "no debugging skill exists" — it was already present, just not surfaced until the 2026-08-02 follow-up research.

**Mechanism:** `debug-skill` (AlmogBaku) — drives a real debugger via the Debug Adapter Protocol (breakpoints, stepping, live inspection) instead of print-statement debugging. Pair the two: methodology for *how to think about* a bug, mechanism for *how to actually step through* one.

## Code review — pick a default, alternatives documented

Four real, live options (`skills/manifest.yaml`), not mutually exclusive:

- **CodeRabbit** — recommended default. This is what already backs the founder's own `/review-loop` skill outside this repo; confirmed live and well-funded, not just a config reference.
- **Qodo** — alternative with a self-hostable open-source core (PR-Agent), no vendor lock-in.
- **Greptile** — alternative, full-codebase-indexing (catches cross-file breakage diff-only reviewers miss).
- **Anthropic first-party** (`code-review` + `pr-review-toolkit`) — zero-third-party-vendor option.

Also from `superpowers`: `requesting-code-review` / `receiving-code-review` skills — dispatch a review subagent with crafted context, and verify feedback technically rather than complying reflexively. Use alongside whichever external reviewer is chosen.

## Static analysis — beyond raw CI Semgrep

This repo's CI already runs Semgrep end-of-pipeline. `trailofbits/skills` (CodeQL + Semgrep + a triage subagent classifying true/false positives, from an independent security research firm) is the recommended agent-facing layer on top.

**`semgrep-guardian` — do not install, corrected 2026-08-02.** It was the original pick here; adversarial review found it's confirmed broken on Windows (silently returns no findings ever — `semgrep/guardian#59`; crashes on a cross-drive project — `#60`, both open), and its `hooks.json` registers a `PreToolUse` hook on `Write|Edit|Bash` — the same blocking primitive as the demolished `phase-gate.js`, contradicting this pack's "no mechanical gates" premise. It also ships a skill literally named `semgrep`, identical to trailofbits' — installing both risks silent skill-shadowing (Trail of Bits found and tried to fix this exact collision in their own plugin; the fix wasn't merged). Use `trailofbits/skills` alone.

## Dependency hygiene — beyond raw audit tools

`managing-dependencies` (Andrew Nesbitt, creator of libraries.io/ecosyste.ms) — verifies packages exist before recommending them (no hallucinated packages), queries ecosyste.ms for maintainer/age/advisory signals, checks for typosquatting, then invokes the same ecosystem-native audit tools (npm audit/pip-audit/cargo audit) this repo's CI already runs — a judgment layer on top, not a duplicate.

## Performance — when it matters

`codspeed-optimize` — real CI benchmark-regression detection (baseline-vs-current comparison, flamegraph MCP tools), not just "run a profiler and eyeball it." Trigger only on perf-sensitive work; not a default.

## Commit / PR lifecycle

`compound-engineering-plugin` (Every.to) — commit → push → PR (auto-documents new concepts) → babysit CI/review comments until merge → draft release notes. Whole loop, not just message formatting.

## What this replaces

Claude Harness v4 enforced a subset of the Ponytail baseline mechanically: `pass-ceiling.js` (5-edit block), `phase-gate.js` (red/green TDD blocking), surgical-changes as "Tier C advisory." v5 keeps the substance and drops the enforcement machinery. Everything beyond the baseline (debugging, review, static analysis, dependency hygiene, perf, commit lifecycle) is **net-new breadth v4 never had at all** — it wasn't demolished, it didn't exist.

## TDD — advisory, not gated

Test-first is valuable when the user wants it. Use `superpowers`' `test-driven-development` skill when a task calls for it — there is no red/green phase, no `red.txt` verifier artifact requirement. Writing tests first is a technique you reach for, not a state the harness forces you into.

**Not `mattpocock-tdd` too — evaluated 2026-08-02, not adopted.** Read both full skills head-to-head (`skills/RESEARCH.md` §10). superpowers wins for an autonomous agent specifically: mandatory verify-red/verify-green with literal run commands, a rationalization-rebuttal table that targets agent shortcut-taking under pressure, gate-function pre-write checklists, a mutation-check correctness bar. `mattpocock-tdd` doesn't have equivalents to any of these. It does have two ideas worth keeping — see below.

### Designing for testability (grafted from `mattpocock-tdd`, not a skill swap)

- **Pre-agreed seams.** Before writing any test, name the public interface under test and confirm it with the user: "What's the public interface, and which seams should we test?" Don't test against internals nobody agreed were the boundary.
- **Mock only at system boundaries** (external APIs, DB, time/randomness, filesystem) — same rule superpowers already states, worth reinforcing.
- **Design for mockability, not just mocking discipline.** Use dependency injection — pass external clients in rather than constructing them inside the function — and prefer SDK-style interfaces (one specific function per external operation) over a single generic fetcher with conditional logic. Makes the boundary itself easy to mock cleanly, instead of fighting a monolithic mock later.

## Planning — lighter alternative to spec-kit

`spec-kit` (see `skills/manifest.yaml`, `trigger: large-feature`) is WATCH — its 4-stage ceremony reintroduces the gating v5 removed. For most non-trivial tasks, use this lighter pipeline instead:

1. **`grill-me`** — before implementation starts, a short interview to sharpen the plan/design and surface disagreement early. Not just for large features — apply this to any non-trivial task where the approach isn't already obvious.
2. **`to-spec`** — for large features only: synthesize the conversation + codebase exploration into a formal, user-story-centric spec grounded in real code state (not invented requirements).
3. **`to-tickets`** — break that spec into independent, vertical-slice tickets with explicit blocking edges, so parallel agent work is possible without collisions.

Cherry-pick spec-kit's spec/plan templates if useful; don't wire its full gate-driven workflow (same guidance as before, now with a lighter default to reach for first).

## Architecture review — beyond per-change simplicity

Ponytail's ladder governs simplicity *per change*; it doesn't review structure across a codebase. Use `improve-codebase-architecture` when module boundaries are unclear or coupling is fighting the change you're trying to make — it looks for structural confusion and proposes module-deepening opportunities, not a per-diff style pass.
