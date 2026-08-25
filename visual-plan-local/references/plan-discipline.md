# Plan discipline — single source of truth

> Adapted from [BuilderIO/skills](https://github.com/BuilderIO/skills)'
> `visual-plan` skill (`SKILL.md`'s "Plan Discipline" and "Self-Review Before
> Handoff" sections, MIT license), commit
> `8fb28e5be81a01df76c8e863aafa2cdbfa476268`. Kept close to verbatim where the
> rule is tool-agnostic; every reference to `create-visual-plan`,
> `update-visual-plan`, `get-plan-feedback`, a hosted comment thread, or an
> MDX `question-form` block has been replaced with this pack's own local
> equivalent (write the plan file + render via `Artifact`, per
> `../skills/visual-plan-local/SKILL.md`).

## Plan Discipline

- **Gate thoughtfully.** A visual plan is a richer review surface, not only a
  tool for giant projects. Use it when the user needs to see, compare, or
  approve a direction before code — even for a modest change. Skip it for
  truly trivial, unambiguous work — typos, one-line fixes, a single
  well-specified function, anything whose diff you could describe in one
  sentence — and just make the change. Never pad a plan with filler and never
  ship a single-step plan.
- **Research before you draft.** Read the real files, symbols, and patterns
  first; name actual files and data shapes instead of inventing them. Check
  existing helpers/utilities before proposing new ones. Delegate wide
  exploration to a sub-agent when useful. Lead with reuse: for each step,
  name what it reuses — existing functions, patterns, config — before what it
  adds, so the plan explains the genuinely new delta instead of redescribing
  what already exists.
- **Decide the hard-to-reverse bets first.** For non-trivial work, sketch
  where the feature is headed, then call out the decisions that are
  expensive to undo once other code depends on them — wire format, public
  interfaces, data-model shape, auth/ownership boundaries — and get those
  right in the plan even if most of the feature ships later. Then scope to
  the smallest first cut that proves the approach without foreclosing it,
  stating both what is in and what is explicitly deferred.
- **Keep examples at the right altitude.** When the user's idea is a broad
  framework or operating-model change, do not collapse it into the first
  concrete example they mention. Separate the core abstraction from
  motivating examples and adapters. Use examples to make the plan legible,
  but label them as examples unless they are the whole requested scope.
- **Publish standalone plans.** If the user pasted or referenced an existing
  plan, treat it as source material, but rewrite the published plan as a
  clean standalone proposal. Preserve its useful intent and codebase facts;
  avoid revision language (see `document-quality.md`'s "Every published plan
  must stand alone"). A reader who never saw the chat should understand the
  plan.
- **Planning is read-only.** Make no source edits while building or reviewing
  the plan. Start editing only after the user approves the direction.
- **Clarify vs. assume.** Do not ask how to build it — explore and present
  the approach and options in the plan. Ask a clarifying question only when
  an ambiguity would change the design and can't be resolved from the code;
  use `AskUserQuestion` and batch 2-4 high-leverage questions before
  finalizing. Otherwise state the assumption explicitly and proceed, and keep
  anything unresolved in the plan's single bottom Open Questions section. For
  complex plans, do a final open-question pass before handoff.
- **The plan is the approval gate.** After surfacing it, ask the user to
  review and approve before writing code, and name which files/areas the work
  touches. Presenting the plan and requesting sign-off (`ExitPlanMode`) is the
  approval step — do not ask a separate "does this look good?" question.
- **The document is the source of truth, not the chat.** When scope shifts
  mid-conversation, update the plan file and re-render the artifact rather
  than only changing course in chat, and make the updated document stand
  alone.

## Self-Review Before Handoff

For high-stakes plans — architecture, data-model, migration, multi-file, or
otherwise risky work — run one adversarial self-review pass before treating
the plan as final. Skip it for small, single-decision plans where the cost
outweighs the value. Keep the pass cheap and non-blocking:

- **Review the written plan; do not re-research.** Critique the plan text
  itself. The grounding was already done while drafting, so the review checks
  the output instead of re-exploring the repo.
- **Spawn one skeptical reviewer** (a sub-agent, or a second self-pass if a
  sub-agent isn't warranted for the size of the plan) whose only job is to
  find what is weak, missing, or wrong — not to praise. Point it at:
  hard-to-reverse decisions made implicitly or not at all (wire format,
  public interfaces, data-model shape, auth, ownership); steps not anchored
  in real files or symbols; a menu of options where the plan should commit to
  one; obvious missing decisions ("what happens when X?", "why not Y?"); and
  padding or single-step filler.
- **Fix vs. ask.** Apply clear-cut fixes yourself — vague non-goals,
  unanchored claims, an obvious missing decision. Route genuine judgment
  calls back to the user instead: add them to the bottom Open Questions
  section with a recommended default, or batch them into `AskUserQuestion`.
  Do not silently decide them.
- **Summarize what the review changed.** When you next respond, briefly state
  what the self-review pass changed and what it surfaced for the user to
  decide.
