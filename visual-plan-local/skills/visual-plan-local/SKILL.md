---
name: visual-plan-local
description: >
  Renders non-trivial implementation plans as a structured, visual document
  instead of a long chat paragraph — this pack's default plan-mode output.
  Use whenever entering plan mode for non-trivial or multi-file work,
  whenever the user asks to "map this out", "design a plan for X", "plan and
  build", or explicitly invokes /visual-plan-local. Fires as part of plan
  mode's own "Final Plan" step, not as a separate thing the user has to name.
metadata:
  derived-from: "BuilderIO/skills visual-plan (MIT) + cathrynlavery/diagram-design (MIT) -- see references/ and vendor/ for provenance"
---

# visual-plan-local

Local, dependency-free counterpart to BuilderIO's `visual-plan`: same
document discipline, same idea of a reviewable visual surface, zero hosted
MCP connector. Read `../../vendor/diagram-design/NOTICE.md` and this pack's
`skills/manifest.yaml` `visual-plan-local` entry for why: `visual-plan`'s
real actions are all calls to a third-party hosted server with no offline
fallback — confirmed absent in this environment — so its discipline was kept
and its hosted rendering layer was replaced with the `Artifact` tool plus a
vendored, self-contained diagram engine.

## When this fires

This is not a skill the user needs to name. It slots into the harness's
existing plan-mode flow (see `EnterPlanMode`'s own "Phase 4: Final Plan")
as the default way that phase produces output, for any plan judged
non-trivial per `../../references/plan-discipline.md`'s "Gate thoughtfully"
rule. Trivial, single-step, or single-sentence-diff work skips this
entirely and just gets made — don't wrap a typo fix in a plan document.

## What no skill can change

`EnterPlanMode`/`ExitPlanMode` are harness-level tools with fixed behavior:
`ExitPlanMode` reads and displays exactly the plan file at the path the
system gives, in its own native approval UI. This skill does not (and
cannot) replace that rendering. What it does — matching what `visual-plan`
itself actually does under the hood — is keep the plan *file* held to a real
quality bar instead of loose prose, and add a rendered `Artifact` companion
alongside it. Both show the same plan; the artifact is the readable one.

## Steps

1. **Read both reference files before drafting** — `../../references/plan-
   discipline.md` and `../../references/document-quality.md`. Don't author a
   plan from memory of what these say; re-read them, same posture their own
   upstream source states for itself.
2. **Do the harness's normal plan-mode exploration** — Explore/Plan agents,
   `grill-me` per `rules/engineering.md`'s "Planning" section — unchanged.
   This skill governs the *output* of planning, not the research process.
3. **Draft to `document-quality.md`'s bar.** Outcome-first objective and
   done-criteria, scope and non-goals, decisions with rationale, ordered
   steps naming real files, risks, verification. When a decision or
   relationship is genuinely two-dimensional (architecture, dependency, data
   flow, sequence, state), don't invent diagram conventions — read
   `../../vendor/diagram-design/SKILL.md`'s visual-type guide (§3), pick the
   nearest type, load its reference, follow its own quality bar (4px grid,
   the 6 connector rules in §6, the complexity budget in §7, the accessible-
   SVG contract) to produce inline SVG.
4. **Self-review non-trivial plans** — the adversarial pass in `plan-
   discipline.md`'s "Self-Review Before Handoff". Skip for small,
   single-decision plans.
5. **Fill `../../template.html` with the drafted content**, following its
   section structure and repeat-block comments exactly (don't restructure it
   ad hoc). Load the `artifact-design` skill first if you haven't this
   session — this is a utilitarian technical-doc treatment, not a landing
   page: real hierarchy, both themes, no gratuitous hero. Publish via the
   `Artifact` tool.
6. **Write the plan file** at the path plan mode gives you, structured to the
   same bar, with the artifact's URL prominently at the top (e.g. right under
   the title, before the objective). Then call `ExitPlanMode` as normal.

## After approval

If the user requests changes before approving, update both the plan file and
re-publish the artifact to the same path (the `Artifact` tool redeploys to
the same URL on a repeat call) — don't leave them out of sync, and don't
describe the update as a correction to the prior draft inside the document
itself (`document-quality.md`'s "Every published plan must stand alone").
