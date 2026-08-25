---
name: onboarding
description: >
  Guided first-run setup for claude-harness from inside a live Claude Code
  session — the mid-session counterpart to `install.sh --onboard`'s
  cold-start bash wizard. Orients on the 3 install tiers, asks the 2 real
  install choices, runs the install non-interactively, then proves it landed
  with a real mechanical check rendered as a lit-up status page. Use when the
  user says "/harness-onboard", "onboard me to claude-harness", "set up
  claude harness", or "install claude harness pack".
---

# claude-harness onboarding (in-CLI)

Read `onboarding/steps.json` (relative to the claude-harness repo root) at
the start of this flow — it is the single source of truth for the tier
copy and the 2 real questions, shared with `install.sh --onboard`. Never
hand-write this copy inline; if it drifts from steps.json, the two wizards
disagree with each other.

## 1. Dry-run or real?

Ask first, before anything else:

> Ask via `AskUserQuestion`: "Try this in a scratch directory first (zero
> risk to your real `~/.claude`), or install for real?" Options: **Dry-run
> to a scratch directory (Recommended)**, **Install for real**.

If dry-run: pick a path under this session's scratchpad directory (e.g.
`<scratchpad>/ch-onboard-dryrun`) and export
`CLAUDE_HARNESS_TARGET=<that path>` for every Bash call in the rest of this
flow. Tell the user the path so they can inspect it afterward, and that
nothing under their real `~/.claude` will change. If real: don't set the
env var: the plain `~/.claude` default resolution applies.

## 2. Orient

Read `onboarding/steps.json`'s `orient.tiers` and present the 3-tier
breakdown in plain prose (label + description per tier) before asking
anything. Don't let anyone pick opt-ins blind.

## 3. Ask the 2 real questions

Read `onboarding/steps.json`'s `questions` array and ask each via
`AskUserQuestion`, using its `prompt` text and `choices` (or yes/no for a
`boolean` question) verbatim — don't reword them, that's what makes this
surface agree with the bash wizard.

## 4. Confirm, then run non-interactively

This is a real filesystem write. Confirm with the user before running,
naming the resolved target directory. Then run install.sh directly with
flags — **never** `--onboard` here, that path blocks on `read -p` waiting
for a TTY this flow doesn't have:

```
./install.sh [--with-memory-hooks] --caveman-mode=<answer>
```

(omit `--with-memory-hooks` if the user answered no).

## 5. Verify mechanically

Run `node onboarding/verify.js --json` (same `CLAUDE_HARNESS_TARGET`, if
set) and parse the array of `{tier, status, detail}`. Don't take install.sh's
own stdout as proof — this is the actual check, same one the bash wizard
runs at the end of `--onboard`.

## 6. Render the report

Read `onboarding/report-template.html` (repo-relative, next to this file's
parent `onboarding/` dir) and fill in its `{{...}}` placeholders from the
verify.json result:
- `{{ALWAYS_STATUS}}` / `{{CAVEMAN_STATUS}}` / `{{MEMORY_STATUS}}`: the raw
  `status` string for that tier (`ok`, `pending-manual-paste`, `missing`,
  `not-installed`) — also used as the CSS state class, don't alter it.
- `{{*_LIT_CLASS}}`: literal `lit` if status is `ok`, otherwise empty string.
- `{{*_ICON}}`: `✓` for `ok`, `…` for `pending-manual-paste`, `✗` for
  `missing`, `–` for `not-installed`.
- `{{*_DETAIL}}`: that tier's `detail` string, verbatim.
- `{{HEADLINE}}` / `{{SUBHEAD}}`: short, honest summary of what just
  happened (mention dry-run vs real explicitly if it was a dry run).
- `{{FIRST_LIGHT}}`: `steps.json`'s `firstLight.instructions`, verbatim.

Write the filled template to a scratchpad file and publish it with the
`Artifact` tool (title "claude-harness — install report", pick a favicon,
`description` one sentence). If any tier came back `pending-manual-paste`,
say so in chat too and offer to help paste the printed settings.json snippet
from install.sh's own output — don't let the artifact be the only place that
surfaces an unfinished step.

## 7. Close

Point at `README.md` and `WORKFLOW.md` for reference (not required reading).
State the reversibility note plainly if memory hooks were installed: there
is no implicit uninstall — removing them means deleting the pasted
settings.json hook entries and `<pack dir>/memory/hooks`.

If this was a dry run and the user liked what they saw, offer to repeat
step 4 onward for real (same answers, no `CLAUDE_HARNESS_TARGET` override).
