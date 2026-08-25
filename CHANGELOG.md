# Changelog

Full release history for claude-harness. See `README.md` for the current-state pitch — this file is the archive.

## 6.2.0 — lessons stop being a store that only grows

A cross-repo memory-system review (q-agent-harness, mex-memory) checked against this pack's own `memory/SPEC.md` found a real, code-level gap: `memory-init.js`'s lessons-index truncation keeps the *first* 8000 bytes and drops the rest, so without any way to graduate a durable lesson out, new lessons eventually stop appearing in the injected `SessionStart` context while old ones squat at the front forever — the one dimension of this pack's memory layer that got worse, not better, with use.

- **[Lesson-promotion nudge](memory/SPEC.md)** — folded into `memory-init.js`'s existing lessons-index read, not a new hook file. A timestamp watermark (`<scope>/promotion/state.json`), not a repeat-count threshold: this repo's own lessons store has held exactly one lesson, ever, promoted without repeating — a borrowed "promote after 3 repeats" rule would never have fired once in its real history. `WORKFLOW.md` gets a classification-first ritual (rule vs. skill vs. architecture-note vs. leave it) in place of that rejected threshold. On promotion, the lesson's index line is actually removed — the step two prior ad hoc promotions both skipped, which is why the truncation risk above was never really closed until now.
- **Stage 1 episodic task log** — a lighter `<scope>/episodic/task-log.md` ritual (task/approach/result/lesson, no hook, no mechanical trigger). A free-standing nudge was designed and explicitly deferred: "a task ended" has no crisp boundary the way a commit or a correction does, and building a nudge around a fuzzy trigger risked becoming a fourth instance of the exact fallible-agent-judgment problem the other three gate hooks exist to catch. Stays ritual-only until Stage 1 is observed going unused.
- Went through a real `/review-loop` pass (internal + `coderabbit:code-reviewer`) before shipping — an unguarded `statSync` that could've silently dropped the *entire* `SessionStart` injection on a transient race got caught and fixed, not just the new nudge logic. 58/58 tests passing.
- **The self-learning loop turned on itself.** A token/time retro on this build's own agent-orchestration overhead produced two new global lessons — batching edits to a hook-watched file before resolving its staleness flag instead of resolving after every edit, and scoping a validation subagent's prompt to the specific open questions instead of a full independent re-derivation once a design is already read and advisor-vetted. Both are exactly the kind of lesson the promotion nudge above now watches for.

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
