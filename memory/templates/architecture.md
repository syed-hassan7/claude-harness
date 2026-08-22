# Architecture note
id: <short-kebab-slug, unique within scope>
scope: project | global
repo: <name or null>
project: <canonical project name, e.g. VenderScope, ContraAI, tender-review-assistant, claude-harness — REQUIRED even at scope:project, so global cross-project recall has a stable string independent of the local repo dirname>
component: <optional short label, e.g. auth, db-layer — organizing hint, not the recall field>
tags: <comma-separated literal keywords: codebase names, aliases, common misspellings — drawn from the codebase itself where possible, not invented vocabulary. The only field the recall rule matches against, see memory/SPEC.md's "Project-architecture memory" section.>
watch_files:
  - <repo-relative path; editing this path mechanically flags this note possibly-stale>
created: <ISO8601>
updated: <ISO8601>
status: current | possibly-stale | superseded
index_line: <exact line injected: id | project | tags | one-line summary | path — nothing more, same injected-index/full-file-on-demand split as lesson.md>

## Summary
<the structural fact / invariant / why-decision, 1-2 sentences>

## Detail
<fuller explanation — read on demand only, never injected wholesale>

## Verified against
<encouraged, not gating: file:line(s) or commit sha where this was confirmed true when captured — gives a later session something concrete to spot-check instead of a disclaimer to read past>

## Staleness check
<blank until PostToolUse flags it:>
<!-- possibly-stale-since: <ISO8601> — edited: <path> -->

## Superseded
<omit this section unless a later session invalidates this note. When it does, don't delete — strike the summary through inline instead, and remove this note's line from architecture/index.md (the .md file itself stays on disk forever — see memory/SPEC.md's "Retention" note):>
<!-- superseded: <ISO8601> — <reason, e.g. "refactor moved auth to middleware/, invariant no longer holds"> -->
~~<original summary text>~~
