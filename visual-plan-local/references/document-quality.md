# Plan document quality — single source of truth

> Adapted from [BuilderIO/skills](https://github.com/BuilderIO/skills)'
> `visual-plan` skill (`references/document-quality.md`, MIT license), commit
> `8fb28e5be81a01df76c8e863aafa2cdbfa476268`. The document-quality prose below
> is tool-agnostic and kept close to verbatim; every reference to a hosted
> Plan MCP connector, block-registry tool call, or MDX-specific mechanic has
> been replaced with this pack's own local equivalents (§ "Use the right
> block" below, and rendering via the `Artifact` tool instead of a hosted
> app). See `../vendor/diagram-design/NOTICE.md` for this skill's other
> vendored dependency.

This file is the canonical quality bar for the plan document read before
drafting one; it is the quality bar. Do not write the document from memory or
paraphrase these rules per task.

**The document is a serious technical plan, not marketing.** Write it the way
a strong implementation plan reads: outcome-first, prose-first,
self-contained, and specific. State the objective and what "done" means, the
scope and non-goals, the proposed approach with the key decisions and their
rationale, ordered steps that name real files, symbols, and data shapes, the
risks, and a closing verification step (tests, build, or a checkable
behavior). Replace vague prose with specifics; never ship a step like "make
it work." No hero art, gradients, logos, nav bars, slogans, or marketing
cards unless the user explicitly asks.

**Every published plan must stand alone.** Even when revising an existing
plan, the output is a plan to do the work, not a changelog of the
conversation. Do not write phrases like "preserve the previous plan", "do not
drop the old idea", "as discussed above", "this revision", "unlike the prior
version", or "correction from the earlier plan". Fold the right decisions
into the plan as normal objective, architecture, scope, and roadmap prose. A
reader who opens the plan with no chat history should understand it. Avoid
negative framing that only makes sense against absent context ("not the old
mode", "not just X") unless the contrast is defined in the plan and genuinely
helps; state the positive model directly.

**Make abstract plans instantly legible.** If the idea is broad, strategic,
or intended for a third-party reviewer, put one concrete example near the top
before dense architecture, mode tables, or roadmaps — what changes, in
product/user terms, before the mechanics. Then put mechanics, data flow, and
implementation detail in separate diagrams or document sections.

**Preserve the user's level of abstraction.** A motivating use case is not
automatically the architecture. When the prompt describes a broader
framework, product mode, or reusable primitive, separate the reusable core
from specific apps, providers, customers, scripts, or launch examples. Use
the concrete example to make the plan understandable, then make clear which
parts are core, which are app-specific adapters, and which are future
examples.

**Diagrams support a claim, they don't duplicate the prose next to them.**
Each diagram should sit next to the recommendation or decision it clarifies;
the diagram carries the spatial relationship (layers, dependencies,
before/after), the surrounding prose carries the reasoning. If a diagram and
its paragraph say the same thing twice, cut one.

**Use the right block, and make it carry substance.** This pack's local
block vocabulary — no external registry call needed, these are just
`template.html` sections and inline HTML:

- **Prose** — plan narrative with real structure (headings, lists, bold for
  the load-bearing terms). No filler paragraphs.
- **File-reference list** — when a load-bearing file is worth highlighting,
  name it with a one-line note on what changes there and why, grouped by
  step. Highlight only the files worth reading; never an exhaustive list of
  every touched file, and never a prose-only description of a file that
  should have been named directly.
- **Decision callout** — for a settled choice, state it as a short callout:
  the decision, the rationale, and (optionally) the alternative(s) weighed
  and why they lost. If the choice is still genuinely open, it belongs in the
  bottom Open Questions section instead, not restated in two places.
- **Diagram** — for two-dimensional architecture, dependency, data-flow,
  sequence, or state relationships, only when it clarifies something real.
  Built via `../vendor/diagram-design` (see that skill's own visual-type
  guide and quality bar) — don't invent ad hoc diagram conventions when a
  vetted one already exists in `vendor/`. Prefer standard two-dimensional
  layouts (layered, swimlane, dependency map, before/after panel) over a
  left-to-right chain unless the relationship is truly sequential.
- **Risks / callout** — concise, scannable, one risk per line with its
  mitigation or why it's accepted.

**Open questions live at the bottom as a single section when answers would
change the plan.** Surface answerable unresolved decisions in one final "Open
Questions" section. That bottom section is the ONLY place that enumerates
open questions: never add a second "Open Questions" heading, list, or recap
of the same questions earlier in the document. A one-line pointer in the
overview prose ("a few decisions are still open — see Open Questions below")
is fine, but do not reproduce the question list above it. State the
recommended default alongside each question. Keep non-answerable assumptions
or risks as concise callouts in the relevant section instead — never bury a
questions/decisions wall inside the plan narrative, and never ask the same
question twice.

For complex plans, do not end without an open-question audit: if
architecture, scope, data shape, or rollout still depends on a choice, either
commit to a recommendation with rationale or add it to the bottom section
with a recommended default. A complex plan with no open questions is fine
only when every meaningful decision has been explicitly made.

**Verification must exercise the real workflow.** The final verification
section should go beyond typecheck/unit tests when the plan changes
behavior, config, or a multi-step flow. Include at least one end-to-end
smoke that matches the real usage path — a real command, a real fixture, a
checkable file/state change. Name the command or manual path when it's known.

**Before handoff, open the plan and check it.** Fix overlap, excessive
whitespace, clipped fragments, poor contrast, and unreadable diagrams before
asking for approval.
