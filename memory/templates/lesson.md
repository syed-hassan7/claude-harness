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

## Superseded
<omit this section unless a later session invalidates this lesson. When it does, don't delete — strike the summary through inline instead:>
<!-- superseded: <ISO8601> — <reason, e.g. "refactor removed the code path this applied to"> -->
~~<original summary text>~~
