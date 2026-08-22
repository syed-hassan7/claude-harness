# Session checkpoint
# Agent-authored content — goal/done/next/decisions/blockers. Hooks mechanically
# manage scope/repo/session_id/updated/files and the rotation lifecycle, but
# never originate goal/next/decisions/blockers text. A raw hook-only checkpoint
# will look sparser than this template — that's expected, not a bug (see
# memory/SPEC.md and memory/hooks/_lib.js's top docblock).
scope: project | global
repo: <name or null>
session_id: <from hook input — used at SessionStart to detect a stale global checkpoint, since SessionEnd is not reliable enough to rotate on, see memory/SPEC.md>
updated: <ISO8601>
goal: <one line — latest user intent>
done:
  - <bullet>
next:
  - <bullet>
files:
  - <path touched>
decisions:
  - <non-obvious choice + why, so a later session doesn't re-litigate it>
blockers:
  - <if any, else omit this section>
