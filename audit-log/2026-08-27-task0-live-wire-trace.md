# Task 0 — live `PostToolUse` wire trace for `Skill` / `Agent` / `Bash`

**Date:** 2026-08-27
**Why this exists:** `review-gate-check.js` (commit `1dfa5d2`) decides whether a review happened by
reading `input.tool_name` plus `input.tool_input.skill` / `.subagent_type` / `.command`. Those field
names were *inferred* from this session's own chat-facing tool schemas, never confirmed against a
real hook payload — a second reviewer flagged exactly that and it shipped anyway on secondary
evidence. With the old transcript-scan fallback deleted, wrong field names would mean a silently
dead gate with no fallback at all. This file is the live confirmation.

## Method

The hook is already wired in the live `~/.claude/settings.json` under `PostToolUse` matcher
`Bash|Skill|Agent`. Rather than change any wiring (which would need a session restart and would
mutate live config), a temporary one-line payload dump was inserted into the **installed** copy —
`~/.claude/claude-harness/memory/hooks/review-gate-check.js`, verified byte-identical to the repo
copy first via `diff -rq` — immediately after `lib.readHookInput()`:

```js
try { require('fs').appendFileSync(process.env.TEMP + '/claude/task0-wire.jsonl',
      JSON.stringify(input) + require('os').EOL); } catch (e) {}
```

Real tool calls were then made from a live Claude Code session and the dump read back. The shim was
reverted by re-copying the repo copy over the installed one and re-`diff`ing to zero.

## Result — field names CONFIRMED CORRECT, no code change needed

Every payload carried the same envelope keys:

```
session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
hook_event_name, tool_name, tool_input, tool_response, tool_use_id, duration_ms
```

| `tool_name` | `tool_input` (verbatim, truncated) | hook reads | verdict |
|---|---|---|---|
| `"Skill"` | `{"skill":"ponytail:ponytail-help"}` | `tool_input.skill` | ✅ correct |
| `"Skill"` | `{"skill":"review-loop","args":"…"}` | `tool_input.skill` | ✅ correct |
| `"Agent"` | `{"description":"…","prompt":"…","subagent_type":"coderabbit:code-reviewer","model":"haiku","run_in_background":false}` | `tool_input.subagent_type` | ✅ correct |
| `"Bash"` | `{"command":"rm -f \"$TEMP/…\"","description":"Clear dump"}` | `tool_input.command` | ✅ correct |

## End-to-end confirmation, not just field names

After the real `Skill(review-loop)` call, live project-scope state for this session:

```json
{"reviewSeen":true,"pending":null,"lastSeen":"2026-08-27T10:54:19.897Z"}
```

Before the call it was `{"reviewSeen":false,…,"lastSeen":"2026-08-27T10:50:13.950Z"}`. The gate
transitioned on a real invocation, in a real session, through real Claude Code wiring. Note the
absence of an `offset` field — confirms the live state is on the post-`1dfa5d2` structural shape,
not a leftover transcript-scanning entry.

Also confirmed live: the `ponytail:ponytail-help` call did **not** set `reviewSeen` — a non-review
Skill invocation is correctly ignored, so the flag isn't set by any Skill call whatsoever.

## Adversarial probe that came back clean (a non-finding, recorded so it isn't re-chased)

The payload envelope carries `tool_response` (e.g. `{"success":true,"commandName":"review-loop"}`),
which raised the question: does a **failed** skill dispatch — `Unknown skill: …`, a live condition
on this machine per audit finding #12 — still fire `PostToolUse` and thereby satisfy the gate
without any review running?

```
Skill(security-audit-DELIBERATELY-BOGUS) → Unknown skill: security-audit-DELIBERATELY-BOGUS
```

Dump file after that call contained **only** the preceding `Bash` entry — no `Skill` entry at all.
A failed dispatch does not reach `PostToolUse`. The hole does not exist; no `tool_response.success`
check is needed, and adding one would be dead code.

## Side effects on real state (disclosure)

Same discipline as the original audit's disclosure section — these are probe artifacts, not organic:

- `~/.claude/review-gate/state.json` gained a `t0-manual` session key (manual pipe test).
- Earlier in the same session a mis-escaped version of the dump shim left the installed hook
  syntactically invalid for roughly three tool calls; it exited 1 at module load and wrote no state.
  Reverted and re-verified byte-identical to the repo copy. Observed once, incidentally: that
  exit-1 + stderr did not visibly surface in the session. Recorded as an observation only — not
  tested deliberately, and nothing in the fixes below depends on it being true.
- Full capture retained at `%TEMP%/claude/task0-wire-final.jsonl` for the life of that temp dir.
