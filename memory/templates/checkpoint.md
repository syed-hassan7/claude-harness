# Session checkpoint
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
