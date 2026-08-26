# Episodic task log

Append-only, one bullet per task-boundary entry (typically right before/after a commit).
Never read-modify-write — pure append, same lock-free-by-construction safety as
lessons/index.md (memory/SPEC.md's Concurrency section). Not injected anywhere by any
hook — read on demand only, and by the promotion-review ritual (WORKFLOW.md) as raw
material for spotting a pattern worth promoting into a lesson/rule/skill.

Stage 1 only (memory/SPEC.md's "Episodic task log" section): no mechanical trigger, no
nudge. The agent appends by judgment at a natural task boundary — nothing enforces it.

Format, one line per entry, appended to the end of this file:
- <ISO8601>: task=<what was asked> approach=<what was actually done> result=<outcome, one clause> cost=<coarse estimate — steps mandated (plan/review/test/doc passes) and rough token order-of-magnitude, e.g. "6 steps, ~40k"; a felt-sense estimate, not instrumented telemetry — optional, omit if genuinely trivial> lesson=<optional, one clause — omit the field entirely if there isn't one, don't write "none">

`cost` exists because "this felt expensive" was anecdotal in every retro until it had a number attached — see the 2026-08-26 harness token-spend audit. It doesn't need precision; it needs to exist consistently enough that a future retro can compare entries instead of relying on memory.
