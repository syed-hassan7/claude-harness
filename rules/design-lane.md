# Design lane — anti-slop, triggered by task type

Design skills activate when a task touches UI/UX surfaces — new screens, component work, visual polish, accessibility. Not always-on; not gated by a rigor dial. Trigger on task shape, same as any other skill.

## Sequence

1. **Pre-UI exploration** — for new screens/flows/information architecture, explore the design space before implementing (brainstorming-style skill, e.g. `superpowers` brainstorming — verify actual name/source in `skills/RESEARCH.md`).
2. **Design intelligence** — `ui-ux-pro-max` for typography, spacing, color, accessibility, and anti-slop review against an established design system. Already available as a Claude Code skill in this environment.
3. **Component search** — shadcn MCP first, for existing component patterns before hand-rolling new ones. Two verified registry sources ride this same mechanism (add the namespace to `components.json`, install via `npx shadcn@latest add @<ns>/<name>` — see `skills/manifest.yaml`):
   - **KokonutUI** (`@kokonutui`) — general-purpose Tailwind/shadcn components.
   - **Bklit UI** (`@bklit`) — charts/data-visualization components; pairs with the bundled `dataviz` skill for chart-heavy work.
4. **Animation** — when a component needs motion, prefer **Motion** (React/JS, formerly Framer Motion) for component-level gestures/layout/springs, or **Anime.js** for lower-level DOM/SVG/canvas sequences. Both are libraries the agent imports and writes code against, not installable skills — see `skills/manifest.yaml`'s `watched_libraries` for why they aren't manifest entries. (Note: KokonutUI is itself built on Motion, so it may already be a transitive dependency once installed.)
5. **Verification** — actually run the feature in a browser (Playwright, or manual) before calling UI work done. Type-checking and test suites verify code correctness, not visual/UX correctness — say so explicitly if browser verification isn't possible in a given environment.

## Evaluated and rejected

Two founder-submitted candidates turned out to be human-only, browser-based design tools with no API/MCP/CLI surface an agent could invoke — **Brik AI** (prompt-to-motion-graphics generator) and **Wevi.ai** (prompt-to-demo-video generator). Both produce visual/video assets, not code, and neither has a programmatic integration point. Kept in `skills/manifest.yaml`'s `reviewed_rejected` list with rationale so they aren't re-proposed without cause; see `skills/RESEARCH.md` §6 for the full research trail.

## What this replaces

Claude Harness v4's `ux_gate` was a mechanical phase: CI must pass, then `agent-browser`/Playwright evidence had to land in `.machina/verifiers/<task>/ux.txt` before `task_complete`, with `ui_touched` auto-set by file-path heuristics and `SKIPPED` requiring a logged reason via `/machina next --skip-ux`. v5 keeps the *sequence* (explore → design → verify) as guidance, drops the artifact-gate and the auto-detection machinery — no phase blocks a write for skipping a step, the agent is trusted to apply the sequence when the task shape calls for it.
