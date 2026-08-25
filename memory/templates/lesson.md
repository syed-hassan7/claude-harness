# Lesson
id: <short-kebab-slug, unique within scope — e.g. read-own-code-before-external-research>
scope: project | global
trigger: correction | effort-mismatch
created: <ISO8601>
index_line: <the one line injected at SessionStart via the lessons index — id + this summary + file path, nothing else>

## Summary
<one or two sentences — the generalizable rule, not the specific incident. See memory/SPEC.md's fire-emoji example: not "check statusline.sh," but "when debugging output from code written this session, read that code directly before researching externally.">

## Incident
<what actually happened — concrete enough that a future session can tell whether this lesson applies, but this section is never injected wholesale, only read on demand>

## Criticality check passed
<one line per gate from memory/SPEC.md's four pre-write tests — quoted-content stripped, non-correction veto checked, same-sentence co-occurrence confirmed (correction trigger only), generalizability confirmed>

## Promoted
<omit this section unless this lesson has graduated into a more durable/authoritative store
(rules/*.md, skills/manifest.yaml, or an architecture-note). Never combine with ## Superseded
— promotion means the content was right and generalizable, not invalidated. A single strong
incident can promote without ever repeating; repetition across lessons is one signal to weigh,
never a hard gate. On promotion: this file stays on disk forever, but its lessons/index.md
line is REMOVED (same retention rule as architecture-notes' supersession, memory/SPEC.md's
"Retention" section — content that graduated to a standing store shouldn't also keep costing
SessionStart byte budget as a duplicate index line). One comment line per promotion target (a
lesson can promote into more than one target):>
<!-- promoted: <ISO8601> — target: <rules/<file>.md | skills/manifest.yaml | architecture-note:<id>> — <one clause: why this generalized beyond the single incident> -->

## Superseded
<omit this section unless a later session invalidates this lesson. When it does, don't delete — strike the summary through inline instead:>
<!-- superseded: <ISO8601> — <reason, e.g. "refactor removed the code path this applied to"> -->
~~<original summary text>~~
