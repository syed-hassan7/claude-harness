# Changelog

Full release history for claude-harness. See `README.md` for the current-state pitch — this file is the archive.

## 6.1.0 — the mechanical layer becomes a family, and it catches its own bugs

A live audit asked one question of every `required: false` entry in `skills/manifest.yaml` (52 of them): does this actually fire as default behavior, or does it just sit as well-written markdown nobody reads at the right moment? Two real gaps turned up, both closed the same way the drift canary already handled its own — an after-the-fact, non-blocking hook, not a rule that hopes to be remembered:

- **[`review-gate-check.js`](memory/hooks/review-gate-check.js)** — a commit ships with no `/review-loop`/`security-audit` evidence anywhere in the session? Logged, surfaced once on the next turn, never blocked. Prompted by a real incident: a prior session shipped exactly that.
- **[`design-lane-gate-check.js`](memory/hooks/design-lane-gate-check.js)** — a commit ships a touched UI file with no screenshot/Playwright evidence in-session? Same treatment. Detection here is almost entirely structural (`tool_name`/`file_path`, not transcript text) — a free-text scan for "done"/"verified" was designed first, then rejected, specifically because caveman-ultra's own house style uses those words constantly for unrelated work in the same session.
- **The canary caught a bug in itself.** Replaying `canary-check.js`'s own detection logic against a real transcript found it batching an entire multi-turn span into one check — one early name-drop was silently covering eight later unnamed citations. Fixed: detection now partitions on real user-turn boundaries, not hook-invocation boundaries.
- Both new hooks went through a real `/review-loop` pass on their own diff before shipping — internal review plus an actual `coderabbit:code-reviewer` pass, not skipped. Five findings, four fixed inline, one deferred with a named follow-up (`memory/SPEC.md`).
- A live diagram-design audit (skinned to this repo's own palette) produced the README's new architecture diagram, replacing several paragraphs of prose Mermaid never rendered well.
- `install.sh --with-memory-hooks` no longer reprints its settings.json wiring snippet once everything's already wired — found by re-running the onboarding flow twice against the same real machine.

See `README.md`'s "Mechanical backstops" section for the shape all three hooks share, and `skills/manifest.yaml`'s `known_issues` list for a fourth finding from the same audit that isn't a hook at all — a Claude Code platform constraint (a freshly-added skill can't be dispatched by name until a fresh session reloads the index), routed around instead of chased.

## 6.0.0 — design lane, benchmarked against an external methodology

The design lane was benchmarked against an external "How to Design With AI" methodology — component-library-first, moodboard-over-prose, many-variants-over-one. The existing shadcn-first component search already matched it; three real gaps got closed:

- **[React Bits](https://github.com/DavidHDev/react-bits)** — pre-built animated/personality components, checked before hand-assembling motion from raw primitives. `rules/design-lane.md`, step 5.
- **[Agentation](https://github.com/benjitaylor/agentation)** — click a rendered element, hand the agent its exact selector/position instead of a prose description. `rules/design-lane.md`, step 7.
- **Moodboard-first reference input** — real reference images are now the primary input for the named-aesthetic commitment, not just a verbal style list. Steps 1–2.
- **N-variant judge-panel for open-ended briefs** — generate several genuinely different directions in parallel and score them, instead of one build iterated on rejection. Step 9 — gated behind explicit user opt-in into multi-agent orchestration; it never fires on its own.

The memory layer grew a new store the same release — project-architecture memory, see `README.md`'s section on it.
