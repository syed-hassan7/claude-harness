# Architecture note
id: architecture-memory-design
scope: project
repo: claude-harness
project: claude-harness
component: memory
tags: memory, architecture, recall, hooks, memory-recall, memory-architecture
watch_files:
  - memory/hooks/memory-recall.js
  - memory/hooks/memory-architecture.js
  - memory/SPEC.md
created: 2026-08-22T00:00:00.000Z
updated: 2026-08-26T09:00:00.000Z
status: possibly-stale
index_line: architecture-memory-design | claude-harness | memory, architecture, recall, hooks, memory-recall, memory-architecture | Project-architecture recall is mechanical (3 hook layers), not agent-judgment prose | notes/architecture-memory-design.md

## Summary
Project-architecture recall is mechanical (3 hook layers: SessionStart ambient index, UserPromptSubmit keyword match, PostToolUse file-touch match), not agent-judgment prose — the original design assumed no hook could do this and was corrected after checking Claude Code's real hook I/O schemas.

## Detail
Note-content authoring stays agent-judgment (gated, same posture as lessons) — only recall and staleness-flagging are hook-mechanical. See memory/SPEC.md's "Project-architecture memory" section for the full design and the correction note explaining why the original synthesis got this wrong.

## Verified against
memory/hooks/memory-recall.js, memory/hooks/memory-architecture.js, memory/SPEC.md's "Recall (read trigger) — three layers, implemented" section, re-confirmed 2026-08-26 (a 4th time — new "Visual-plan gate memory" section and a Design-lane-gate-memory extension added to SPEC.md for the native-control/visual-plan-gate build). Neither touches the "Recall" section; the 3-layer Project-architecture-memory design this note describes is unchanged.

## Staleness check

<!-- possibly-stale-since: 2026-08-26T08:56:24.649Z -- edited: memory/SPEC.md -->
## Superseded
