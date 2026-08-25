# Episodic task log

Append-only, one bullet per task-boundary entry (typically right before/after a commit).
Never read-modify-write — pure append, same lock-free-by-construction safety as
lessons/index.md (memory/SPEC.md's Concurrency section). Not injected anywhere by any
hook — read on demand only, and by the promotion-review ritual (WORKFLOW.md) as raw
material for spotting a pattern worth promoting into a lesson/rule/skill.

Stage 1 only (memory/SPEC.md's "Episodic task log" section): no mechanical trigger, no
nudge. The agent appends by judgment at a natural task boundary — nothing enforces it.

Format, one line per entry, appended to the end of this file:
- <ISO8601>: task=<what was asked> approach=<what was actually done> result=<outcome, one clause> lesson=<optional, one clause — omit the field entirely if there isn't one, don't write "none">
