# Skill & MCP research — Phase 7

**Method:** WebSearch to discover candidates, then every hard number (stars, forks, open issues, license, dates) pulled directly from `api.github.com/repos/<owner>/<repo>` — not read off a rendered page. All figures independently cross-checked a second time via `gh api` in this session on 2026-08-02; both methods returned identical numbers. Where a claim couldn't be traced to a fetched source, it's in the UNVERIFIED section at the bottom, not stated as fact above it.

**Anomaly flag, RESOLVED for Ponytail 2026-08-02 (see §8):** Ponytail's 93,764 stars in ~7 weeks was flagged as anomalous and investigated properly via Wayback-archived star-count snapshots, an account spot-check, and fork-ratio analysis. Verdict: **organic** — the growth traces to a real, dated Hacker News front-page post (98 points, 2026-06-14) plus follow-on press, with a smooth ramp-then-decay curve, not vertical bot cliffs. Full evidence in §8. `obra/superpowers` (264,990 stars, 10-month-old repo) was **not** independently re-investigated with the same rigor — the same caution (trust the content, not the star count, until checked) still applies to it specifically.

---

## 1. Engineering

### Ponytail — locked-in "core," verification target
- **URL:** https://github.com/DietrichGebert/ponytail (GitHub routes the lowercase `dietrichgebert/ponytail` spelling in the source plan to this same canonical repo — not a separate/impostor project)
- Stars: 93,764 · Forks: 5,157 · Open issues: 128 · License: MIT
- Created: 2026-06-12 · Last pushed: 2026-07-15
- **What it ships (read from `skills/ponytail/SKILL.md` directly, not paraphrased):** a real Claude Code skill file — frontmatter (`name`, `description`, `argument-hint`, `license`), a 7-rung "laziness ladder" (YAGNI → reuse existing code → stdlib → native platform → already-installed dep → one-liner → minimal code), intensity levels (`lite`/`full`/`ultra`), and a root-cause-not-symptom bug-fix rule. Also published as an npm package `@dietrichgebert/ponytail` (latest `4.8.4`), with adapters for ~20 other agents (Cursor, Copilot CLI, Windsurf, Cline, Gemini CLI, OpenClaw, etc.).
- Agent support: Claude Code (primary) + ~20 others — genuinely portable.
- **Verdict: INCLUDE — confirmed, not vaporware.** The source plan's `required: true` lock-in for Ponytail as the engineering core is now backed by verified content, not just a name.

### superpowers (obra) — TDD + brainstorming skills
- Marketplace: https://github.com/obra/superpowers-marketplace — Stars: 1,196 · Forks: 242 · Open issues: 45 · License: MIT · Created: 2025-10-09 · Pushed: 2026-07-24
- Core plugin: https://github.com/obra/superpowers — Stars: 264,990–264,996 (moved slightly between checks) · Forks: 23,666 · Open issues: 321 (API) · License: MIT · Created: 2025-10-09 · Pushed: 2026-07-31
- **What it ships:** confirmed via raw README fetch. `/plugin marketplace add obra/superpowers-marketplace` installs 4 plugins:
  - **superpowers** (core) — **correction (2026-08-02 follow-up):** this repo ships exactly **14 skills**, not "20+" (that figure is an inflated marketing description repeated in search snippets, not the real count — verified via a recursive fetch of the `skills/` tree). Full list and engineering-relevance in §7 below. Includes `/brainstorm`, `/write-plan`, `/execute-plan`, and — the important one for the engineering-lane gap — **`systematic-debugging`**, a genuine 4-phase root-cause methodology skill. This was missed in the first pass because only 3 of the 14 skills were sampled.
  - **elements-of-style** → obra/the-elements-of-style (456 stars, pushed 2025-10-18 — stale ~10 months, **no LICENSE file**)
  - **superpowers-developing-for-claude-code** → obra/superpowers-developing-for-claude-code (134 stars, **no LICENSE file**)
  - **private-journal-mcp** → obra/private-journal-mcp (419 stars, pushed 2026-06-12, **no LICENSE file**) — semantic-search journaling MCP, same maintainer, no crypto/supply-chain red flags (see claude-mem below for contrast)
- Verdict: **INCLUDE** (core `superpowers` + marketplace) · **WATCH** (the 3 sub-plugins — real, but confirm license terms before redistributing content from them)

---

## 2. Design / UI

### Hallmark
- URL: https://github.com/Nutlope/hallmark — Stars: 20,744 · Forks: 1,037 · Open issues: 38 · License: MIT · Created: 2026-04-27 · Pushed: 2026-07-31
- What it does: anti-AI-slop design skill for Claude Code/Cursor/Codex — 22 themes, 65 "slop-test" gates, 4 verbs (build/audit/redesign/study), enforces structural variety so generated pages don't converge on the same hero→3-card→CTA template.
- Agent support: Claude Code, Cursor, Codex
- Verdict: **INCLUDE**

### Impeccable
- URL: https://github.com/pbakaus/impeccable — Stars: 53,936 · Forks: 3,207 · Open issues: 46 · License: Apache-2.0 · Created: 2025-11-16 · Pushed: 2026-08-01
- What it does: 18–23 interconnected commands (`polish`, `audit`, `critique`, `distill`, `animate`, …) that front-load a different reference distribution rather than fixing slop after the fact, plus a `detect` CLI with 44 anti-slop rules wired for CI and a Live Mode for browser iteration.
- Agent support: Claude Code, Cursor
- Verdict: **INCLUDE — overlaps with Hallmark.** Both are anti-slop design skills covering similar ground. Recommend **Impeccable as primary** (broader command set, CI-hookable `detect`, actively pushed same day as this check) and **Hallmark as reference/secondary**, not both wired as `required`.

### anti-ui-slop / UIZZE
- **UNVERIFIED.** Only a third-party curated-list PR (`sickn33/agentic-awesome-skills#924`) and marketing landing pages surfaced — no canonical `github.com/<org>/<repo>` with fetchable stats. **Do not add to the manifest** until a real source repo is located.

### Design-tokens MCP (category note)
- `yajihum/design-system-mcp` — 25 stars, no license, pushed 2026-04-14 (stale). `Blyawon/tokensStudioMCP` — 4 stars, MIT, pushed 2026-06-11 (very early).
- Verdict: **WATCH (category)** — nothing clears an "official/high-trust" bar yet. Open gap, not a solved category; re-check in a future pass.

---

## 3. MCPs (official/high-trust only)

### shadcn MCP
- Official docs: https://ui.shadcn.com/docs/registry/mcp — backed by https://github.com/shadcn-ui/ui (Stars: 120,324 · Forks: 9,655 · Open issues: 2,205 · License: MIT · Created: 2023-01-04 · Pushed: 2026-07-31)
- What it does: MCP support ships natively in shadcn CLI 3.0 (`npx shadcn@latest mcp`) — works against any shadcn-compatible registry, no separate server repo to vet.
- Verdict: **INCLUDE** — this is the current official path, supersedes third-party `shadcn-ui-mcp-server` forks (ymadd/Jpisnice/heilgar and others) that turned up in search; those are now lower-trust duplicates of functionality shadcn ships itself.

### Figma Dev Mode MCP
- Official guide: https://github.com/figma/mcp-server-guide — Stars: 1,837 · Forks: 171 · Open issues: 7 · **License: none set** · Created: 2025-08-05 · Pushed: 2026-07-30
- What it does: the MCP server itself ships inside the closed-source Figma desktop app (requires Dev/Full seat on a Professional plan); this repo is Figma's official usage guide, not the server source.
- Verdict: **INCLUDE** (official, actively maintained) — note the license gap on the guide repo and that the server is proprietary/seat-gated, worth flagging for anyone budgeting for it.

### Playwright MCP (browser automation)
- URL: https://github.com/microsoft/playwright-mcp — Stars: 35,742 · Forks: 2,982 · Open issues: 12 · License: Apache-2.0 · Created: 2025-03-21 · Pushed: 2026-07-25
- What it does: official Microsoft Playwright MCP server, drives browsers via the accessibility tree (no vision model required); used by GitHub Copilot's Coding Agent for live verification.
- Verdict: **INCLUDE** — official maintainer, low open-issue-to-star ratio (healthy triage), matches the `WORKFLOW.md` Verify step's browser-verification need directly.

---

## 4. Spec / planning

### GitHub Spec Kit (specify-cli)
- URL: https://github.com/github/spec-kit — Stars: 124,980 · Forks: 11,166 · Open issues: 330 · License: MIT · Created: 2025-08-21 · Pushed: 2026-07-31
- What it does: Spec → Plan → Tasks → Implement workflow toolkit; `specify` CLI bootstraps templates/checklists/commands for 35 agent integrations.
- Verdict: **WATCH, not required.** Legitimate and officially GitHub-maintained, but 4 formal artifact stages (spec/plan/tasks/checklists) is real ceremony — including it wholesale would reintroduce the same ceremony `CLAUDE_HARNESS_ANALYSIS.md` demolishes. If used at all, cherry-pick the spec/plan templates for the `trigger: large-feature` case in `skills/manifest.yaml`, not the full gate-driven workflow.

---

## 5. Memory / context

### claude-mem
- URL: https://github.com/thedotmack/claude-mem — Stars: 89,305 · Forks: 7,774 · Open issues: 344 · License: Apache-2.0 · Created: 2025-08-31 · Pushed: **2026-08-02 (today)**
- **Maintenance status vs. the stale note in this repo's own `harness.md` §7 ("not installed by default... full profile only"):** that note undersold it — the project is under heavy active development (pushed same-day; issues numbered into the 3000s covering Chroma DB corruption recovery, worker self-healing, Windows Git Bash fixes, OpenCode/Codex/Vertex-AI integrations). The progressive-disclosure query pattern (`search` → `timeline` → `get_observations`, ~10x token savings) is a legitimately useful design.
- **Confirmed red flag (read directly from the README, not inferred):** the project officially promotes a third-party cryptocurrency token — quoting the README verbatim: *"CMEM is a token created by a 3rd party but officially embraced by the creator of Claude-Mem (Alex Newman, @thedotmack)... Official BASE CA: 0x76b1967eec0ccaeb001bbbb2b40dc4badba31ba3."* Installer uses `curl -fsSL https://install.cmem.ai/... | bash` — arbitrary remote script execution, a supply-chain risk pattern.
- **Verdict: WATCH → lean REJECT for inclusion in an org-shipped pack.** Technically capable, actively maintained (the "abandoned" characterization in this repo's old docs is now wrong and should be corrected), but the maintainer-endorsed crypto token plus curl-pipe-bash installer are real governance/security concerns for anything Claude Harness would recommend org-wide. `memory/SPEC.md` §Evaluate-vs-adopt already reflects this: file-based hooks (Option A) ship as the v5 default; claude-mem is documented only as an optional power-user adapter, never a default install.
- **Cleaner fallback if the memory pattern is wanted:** `obra/private-journal-mcp` (419 stars, see superpowers section) — semantic-search journaling MCP, same maintainer as superpowers, no token/installer red flags, smaller feature scope.

---

## 6. Frontend animation & component libraries (user-submitted, 2026-08-02 follow-up)

Six candidates the founder surfaced from their own bookmarks. All verified live via GitHub REST API (`gh api`) where a repo existed, plus direct doc-page fetches for install mechanics.

### Anime.js
- URL: https://github.com/juliangarnier/anime — Stars: 71,698 · Forks: 4,822 · Open issues: 113 · License: MIT · Pushed: 2026-06-22 (v4.5.0 — added a `registerAdapter()` API incl. a Three.js adapter)
- What it ships: standalone JS animation engine (DOM/SVG/CSS + non-DOM targets via adapters). Actively maintained, real feature work not just patch churn.
- Is it a skill or a library?: **A library.** No Claude-Code-specific skill wrapper exists — searched, nothing found.
- Overlap: none with existing design-lane entries.
- Verdict: **WATCH**
- Rationale: excellent, current, but not agent-installable as a skill — would need a thin skill wrapper (e.g., "prefer these Anime.js patterns for X") to belong in the manifest proper. Reference it in `rules/design-lane.md` as a recommended library, not a manifest skill entry.

### Motion (formerly Framer Motion)
- URL: https://github.com/motiondivision/motion — Stars: 33,048 · Forks: 1,286 · Open issues: 113 · License: MIT · Pushed: 2026-07-28 (active `v12.x` line, `v13.0.0-alpha.0` in progress)
- What it ships: React + vanilla-JS animation (gestures, layout animation, springs, scroll effects). Rebranded from Framer Motion; homepage motion.dev.
- Is it a skill or a library?: **A library**, same as Anime.js — no Claude-Code skill wrapper found.
- Overlap: **KokonutUI (below) is built on Motion** — if KokonutUI ships, Motion is already a transitive dependency.
- Verdict: **WATCH**
- Rationale: same reasoning as Anime.js — reference in `rules/design-lane.md`, not a standalone manifest entry.

### KokonutUI
- URL: https://github.com/kokonut-labs/kokonutui (site: kokonutui.com) — Stars: 1,987 · Forks: 121 · Open issues: 0 · License: MIT · Pushed: 2026-08-02 (same day)
- What it ships: a **shadcn/ui-compatible component registry** (Tailwind + shadcn/ui + Motion under the hood) — confirmed via docs fetch. Installs through the *existing* shadcn CLI by adding a registry namespace: `"@kokonutui": "https://kokonutui.com/r/{name}.json"`, then `npx shadcn@latest add @kokonutui/particle-button`. Vercel OSS 2025 Program sponsor.
- Is it a skill or a library?: neither purely — a registry source consumed **through the shadcn MCP entry already in the manifest.**
- Overlap: direct — plugs into `shadcn-mcp`, not a new tooling category.
- Verdict: **INCLUDE**
- Rationale: zero-friction — rides infrastructure Claude Harness already ships, actively maintained, sponsor-backed.

### Bklit UI
- URL: https://github.com/bklit/bklit-ui (docs: bklit.com/docs) — Stars: 1,416 · Forks: 92 · Open issues: 3 · License: MIT · Pushed: 2026-07-28
- What it ships: an **open-source shadcn-registry component set specifically for charts/data visualization** (area, bar, candlestick, etc.). Confirmed via docs fetch — `pnpm dlx shadcn@latest add @bklit/area-chart` after registering `"@bklit": "https://ui.bklit.com/r/{name}.json"`. Real MIT source, Vercel OSS Program member — not a paid product, not a Storybook demo (both were open questions going in).
- Is it a skill or a library?: same pattern as KokonutUI — a shadcn-registry source, not a standalone skill.
- Overlap: also plugs into `shadcn-mcp`; complementary to KokonutUI (general components) and the `dataviz` skill already available in this environment (chart-specific).
- Verdict: **INCLUDE**
- Rationale: fills a real chart/dataviz gap via the same low-friction registry path as KokonutUI.

### Brik AI — reviewed and rejected
- URL(s): brik.space (Home/ToolEditor/Gallery/Pricing/About), docs.brik.space
- What it is: a browser-based "prompt-to-tool" motion-design generator — describe an idea, get a parameterized/remixable animated visual. Fully client-rendered SPA; `docs.brik.space` is marketing copy only.
- Open source or proprietary: proprietary, closed. No GitHub org/repo found.
- Agent-integration surface: **none** — no API, MCP, CLI, SDK, or webhooks anywhere in the docs.
- Credibility: weak — no Crunchbase entry, no verifiable funding/team, visibility limited to SEO tool-aggregator blurbs.
- Verdict: **REJECT**
- Rationale: human-in-the-browser visual tool, produces visual assets not code, zero agent-facing surface. A manifest entry would be a bookmark for a human motion designer, not something an agent invokes.

### Wevi.ai — reviewed and rejected
- URL(s): wevi.ai, betalist.com/startups/wevi, github.com/wevi-HQ (org exists, **no public repos**), LinkedIn company page
- Disambiguation: confirmed distinct from "Weavy.ai" and "Weviy.com" — both surfaced in search due to name similarity.
- What it is: turns a static SaaS UI into an AI-generated animated demo/marketing video from a text prompt. BetaList listing dated 2025-09-14; site is currently email-signup-only (pre-launch).
- Open source or proprietary: proprietary — GitHub org exists only to verify the domain, has zero public repos.
- Agent-integration surface: **none** — no API/MCP/CLI/SDK anywhere.
- Credibility: thin — LinkedIn shows 2–10 employees, 15 followers, no funding found.
- Verdict: **REJECT**
- Rationale: pre-launch, human-facing video tool, no programmatic surface, minimal independent credibility signals.

---

## 7. Engineering lane deep-dive — follow-up research (2026-08-02)

The founder's read after the first pass: "just having ponytail is gonna [not] do much." Correct — the original engineering lane was one skill deep. This pass covers superpowers' actual full contents, code review, debugging mechanism, static analysis, dependency/tech-debt, performance, and commit/PR lifecycle. All numbers below via `gh api` (or WebFetch cross-checked against it where noted); anomalous growth rates are flagged per the same standard as §1.

### 7a. `obra/superpowers` — full skill inventory (correcting the earlier undercount)

14 skills total, verified via the repo's `skills/` tree. Engineering-discipline-relevant ones:

| Skill | What it does | Relevance |
|---|---|---|
| **systematic-debugging** | 4-phase RCA (Root Cause Investigation → Pattern Analysis → Hypothesis/Test → Implementation). "Iron Law: NO FIXES WITHOUT ROOT CAUSE FIRST." 3-strikes-then-question-the-architecture rule. Sub-docs: `root-cause-tracing.md` (backward call-stack tracing), `defense-in-depth.md` (4-layer validation), `condition-based-waiting.md` (replace flaky timeouts with condition polling), `find-polluter.sh` (bisect test pollution). | **This is the debugging-methodology skill the manifest was missing** — already included via superpowers, just not previously surfaced |
| test-driven-development | Red-green-refactor; "if you didn't watch it fail you don't know what it tests" | Already referenced in `rules/engineering.md` as "advisory TDD" |
| receiving-code-review | Requires technical verification of feedback, not reflexive compliance | Review discipline |
| requesting-code-review | Dispatches a code-reviewer subagent with crafted context after each task | Review discipline — pairs with CodeRabbit/Qodo/Greptile below |
| subagent-driven-development | Fresh implementer subagent per task + per-task review + final branch review | SDLC discipline |
| verification-before-completion | "Evidence before claims" — run and show verification output before declaring done | Directly reinforces `rules/security-invariants.md`'s "external verification before done" |
| writing-plans | Implementation plans assuming zero codebase context, bite-sized TDD/DRY/YAGNI-aware tasks | Planning discipline |
| finishing-a-development-branch | Verify tests → detect environment → choose merge/PR path → clean up | Release hygiene |
| using-git-worktrees | Isolated workspace before feature work | Workflow hygiene |
| brainstorming, dispatching-parallel-agents, using-superpowers, writing-skills | Process/meta/orchestration, not engineering discipline per se | Already covered in `rules/design-lane.md` (brainstorming) or not manifest-relevant |

**Conclusion:** no new external debugging-methodology skill is needed as the *default* — superpowers already ships one, more rigorous than every standalone alternative found in 7b. The gap was visibility, not content.

### 7b. Debugging — mechanism layer (complementary to systematic-debugging, not a replacement)

#### AlmogBaku/debug-skill
- URL: https://github.com/AlmogBaku/debug-skill — Stars: 310 · Forks: 25 · Open issues: 2 · License: MIT
- What it does: teaches Claude to drive a **real debugger** via a companion Go CLI (`dap`) wrapping the Debug Adapter Protocol — breakpoints, stepping, inspecting locals/call stack, evaluating expressions mid-run, instead of print-statement debugging.
- Agent support: Claude Code, Codex, Opencode, Cursor (via skills.sh)
- Verdict: **INCLUDE (candidate)**
- Rationale: genuinely different capability from systematic-debugging — that's methodology (how to reason about a bug), this is mechanism (how to actually step through one). Real traction, active CI, MIT.

#### doraemonkeys/claude-code-debug-mode
- URL: https://github.com/doraemonkeys/claude-code-debug-mode — Stars: 110 · Forks: 6 · License: MIT
- What it does: hypothesis-driven debugging (ported from Cursor's "Debug Mode"): Understand → Hypothesize (3-5 testable) → Instrument → Reproduce → Diagnose → Fix → Verify → Clean up.
- Verdict: **WATCH** — meaningfully overlaps with systematic-debugging's evidence-gathering phase; not clearly additive enough to include alongside it.

#### 5-whys-skill, Debug Detective, mcpmarket "root-cause-investigator"
- Verdict: **WATCH / REJECT / UNVERIFIED** respectively — narrow single-technique (5-whys, 45 stars), abandoned-on-arrival (0 stars/forks since a single-day push), and a 429-erroring third-party listing with no traceable primary repo. None surpass what's already in superpowers.

### 7c. Code review

#### CodeRabbit
- URL: https://www.coderabbit.ai/ · plugin repo https://github.com/coderabbitai/claude-plugin (54 stars, MIT, pushed 2026-07-29)
- What it is: AI PR/IDE/CLI code review — AST parsing + codegraph + 40+ integrated static analyzers, reads CLAUDE.md project guidelines automatically. Official Claude Code plugin (`/plugin install coderabbit`), 32,361 installs per claude.com/plugins. Requires separate CodeRabbit CLI + browser auth.
- Credibility: $88M raised ($60M Series B, Scale Venture Partners/NVentures/CRV), $550M valuation, 15,000+ customers claimed, free tier exists (unlimited repos, PR summaries, IDE/CLI review).
- Verdict: **INCLUDE**
- Rationale: **this is the exact tool the founder's own personal setup already depends on** (`/review-loop` skill in this environment pairs internal-agent review with CodeRabbit) — now confirmed live and real, not just a name in a config file.

#### Qodo (formerly CodiumAI) / PR-Agent
- URL: https://www.qodo.ai/ · OSS core https://github.com/The-PR-Agent/pr-agent (12,333 stars, 1,664 forks, MIT, pushed 2026-08-01)
- What it is: commercial PR review (Qodo Merge) on top of an open-source, self-hostable engine. Official Claude Code plugin "Qodo Skills" (11,772 installs) — `get-qodo-rules` (pulls org coding standards into context), `qodo-pr-resolver` (fetch/fix PR review comments from terminal). Remote MCP server for cross-repo RAG.
- Verdict: **INCLUDE (alternative)**
- Rationale: the only competitor with both a genuine OSS core (self-hostable, no vendor lock-in) and its own official Claude Code plugin — good pick for teams wanting to avoid CodeRabbit's hosted-only model.

#### Greptile
- URL: https://www.greptile.com/ · org https://github.com/greptileai
- What it is: full-codebase-indexing reviewer (not diff-only) — traces cross-file breakage. Official Claude Code plugin, 56,611 installs (higher than Qodo's). MCP server available. Free tier (50 reviews/mo, launched June 2026), then $30/seat + $1/review overage.
- Verdict: **INCLUDE (alternative)**
- Rationale: real, live, highest install count of the three — best pick specifically for cross-file bug detection that diff-based reviewers (CodeRabbit, Qodo) can miss.

#### Anthropic first-party: `code-review`, `pr-review-toolkit`, `claude-security`, `security-guidance` (all in `anthropics/claude-plugins-official`)
- Multi-agent PR review w/ confidence scoring, dedicated comment/test/error-handling/type-design review agents, deep self-verifying vuln scanning, pattern+LLM diff review across 25+ vuln classes.
- Verdict: **INCLUDE (first-party alternative)**
- Rationale: zero third-party dependency — worth documenting as the "no external vendor" option alongside CodeRabbit/Qodo/Greptile.

**Decision needed from you:** four real options (CodeRabbit, Qodo, Greptile, Anthropic first-party) — not mutually exclusive, but pick a *default* to avoid decision fatigue in `skills/manifest.yaml`. Recommendation: **CodeRabbit as default** (already your validated practice via `/review-loop`), the other three documented as alternatives.

Rejected (real products, no Claude Code integration surface): **GitHub Copilot Code Review** (GitHub-ecosystem-only), **Graphite Reviewer** (tied to Graphite's stacked-PR workflow). **Sourcery** and **CodeScene** are credible companies but WATCH — no shipped Claude Code plugin yet (CodeScene has an early-access MCP server, not a plugin).

### 7d. Refactoring / simplification

#### `code-simplifier` (Anthropic first-party, `anthropics/claude-plugins-official`)
- Verified: parent repo 32,964–32,965 stars, Apache-2.0, pushed 2026-08-02 (today). Read the actual agent spec: model `opus`, scoped to recently-modified code, explicit anti-overcompression rules (no nested ternaries, don't sacrifice clarity for fewer lines), auto-triggers after edits.
- Verdict: **INCLUDE**
- Rationale: overlaps with Ponytail but is first-party Anthropic tooling — complements rather than replaces it. Ponytail is the broader upfront philosophy (7-rung ladder, intensity levels, root-cause rule); code-simplifier is a scoped post-edit cleanup pass. Ship both.
- Dead-code/complexity-metric tooling beyond this: thin, unverified category (SEO-directory listings only, no real backing repo found) — not padding the manifest with a weak pick.

### 7e. Static analysis (agent-facing layer, beyond this repo's existing raw Semgrep CI step)

#### `semgrep/guardian` (official, distributed via `anthropics/claude-plugins-official`)
- Stars: 10 · Forks: 6 · pushed 2026-07-22 · 19,548 installs on claude.com/plugins
- What it does: real-time post-edit scanning (Code/Supply-Chain/Secrets rulesets) wired into the edit loop — prompts the agent to regenerate until clean, not an end-of-pipeline report.
- Verdict: **INCLUDE**

#### `trailofbits/skills` — `plugins/static-analysis`
- Stars: 6,393 · Forks: 552 · License: CC-BY-SA-4.0 (unusual for code — check compatibility before adopting) · pushed 2026-08-01
- What it does: Trail of Bits (independent security research firm) plugin — CodeQL taint tracking + Semgrep + SARIF dedup, plus a `semgrep-triager` agent that classifies findings as true/false-positive by reading source, not just running the tool.
- Verdict: **INCLUDE (alternative/deeper option)**
- Rationale: real security firm, deeper triage automation than the vendor plugin. `jaeyeom/claude-toolbox`'s `semgrep-review` (1 star) does something similar but with effectively zero adoption — **WATCH**, redundant with this pick.

### 7f. Dependency / tech-debt management

#### `andrew/managing-dependencies`
- Stars: 16 · Forks: 0 · License: CC0-1.0 · pushed 2026-07-17
- Author: Andrew Nesbitt, creator of libraries.io / ecosyste.ms — genuine OSS-ecosystem-data authority (corroborated via his own blog post).
- What it does: verifies package existence before recommending (no hallucinated packages) → checks against stdlib/transitive-dep-count/smaller-alternatives → queries the **ecosyste.ms API** for dependent-repo count, maintainer count, age, license, advisories → typosquatting/homoglyph detection → lockfile-injection-aware PR review guidance → invokes ecosystem-native audit tools (the same npm audit/pip-audit this repo's CI already runs) as a final step, not a replacement.
- Verdict: **INCLUDE**
- Rationale: low star count, high-credibility author, genuinely differentiated judgment layer sitting on top of (not duplicating) this repo's existing CI audit steps.
- `ksimback/tech-debt-skill` (543 stars, 3-file single-commit repo, 0 watchers) — good design (forces file:line citations per finding) but an **anomalous engagement pattern** (high stars, zero iteration, zero watchers) inconsistent with organic adoption. **UNVERIFIED**, not excluded outright, but don't treat the star count as validation.

### 7g. Performance profiling

#### `CodSpeedHQ/codspeed` — `skills/codspeed-optimize`
- Stars: 239 · Forks: 26 · License: Apache-2.0 · created 2023-11-11 (predates the current skills-hype cycle — organic growth curve, no anomaly) · pushed 2026-07-30
- What it does: wraps CodSpeed's real CI benchmark-regression product (<1% variance instrumented CPU simulation) — MCP tools `compare_runs`/`query_flamegraph`/`list_runs` let the agent autonomously compare baseline-vs-optimized runs across Rust/Python/Node/Go/C/C++.
- Verdict: **INCLUDE**
- Rationale: the only candidate found anywhere with a real regression-detection surface rather than "invoke a profiler and eyeball the output." Everything else checked (ComposioHQ, rohitg00, jeremylongshore perf skills) is a thin markdown description with no named tool integration — stated plainly rather than padded.

### 7h. Commit / PR lifecycle

#### `EveryInc/compound-engineering-plugin`
- Stars: 23,698 · Forks: 1,906 · License: MIT · created 2025-10-09 · pushed 2026-08-01
- What it does: `/ce-commit`, `/ce-commit-push-pr` (documents new concepts the change introduces), `/ce-babysit-pr` (watches an open PR, reacts to review/CI until merge), `/ce-resolve-pr-feedback`, `/ce-promote` (release copy). Whole commit→PR→merge→announce lifecycle, not just message formatting.
- Verdict: **INCLUDE**
- Rationale: only candidate treating commit hygiene as part of a closed loop rather than a static template. Fast growth (~10 months to 23.7k stars) flagged per standard practice, but fork ratio (~12.4:1) is healthy and the maintainer (Every.to) has an existing large audience — plausible, not dismissed.
- Generic conventional-commit gists and changelog-generator stubs (ComposioHQ, GLINCKER): **REJECT** — no differentiated capability beyond a prompt template this repo's CLAUDE.md conventions already provide.

### 7i. Marketplace/discovery sources (meta, not individual skills)

`anthropics/claude-plugins-official` (32,965 stars, Apache-2.0, pushed same day as this research) is Anthropic's own live-updated marketplace — **INCLUDE as the canonical source**, it independently corroborates `superpowers`' legitimacy (listed there) and is where `code-review`, `pr-review-toolkit`, `code-simplifier`, `code-modernization`, `commit-commands`, `claude-security`, `security-guidance`, `feature-dev`, `hookify`, `ralph-loop` all live. `anthropics/skills` (165,747 stars) is Anthropic's reference skill repo but confirmed to contain **no dedicated debugging/RCA/code-review-discipline skill** — closest is `webapp-testing`.

Several third-party "awesome-claude-*" aggregator lists were checked (subinium, rohitg00, jeremylongshore, ComposioHQ, travisvn, GetBindu) — all **WATCH**, useful as discovery surfaces but not vetted content sources themselves. Two are flagged for anomalous growth relative to their actual curation depth: `ComposioHQ/awesome-claude-skills` (71,596 stars on a vendor lead-gen list) and `alirezarezvani/claude-skills` (23,648 stars on a 300+-skill mega-repo where the specific engineering skills originally sought — `tech-debt-tracker`, `performance-profiler` — no longer resolve at their indexed paths). Both fork ratios are within normal range (not proof of fraud), but breadth-over-curation makes them unsuitable as direct manifest sources — treat as future hunting grounds, not vetted picks.

### 7 summary — net new INCLUDE candidates

`debug-skill` (AlmogBaku), CodeRabbit, Qodo, Greptile, Anthropic `code-review`/`pr-review-toolkit`, `code-simplifier`, `semgrep/guardian`, `trailofbits/skills`, `andrew/managing-dependencies`, `CodSpeedHQ/codspeed-optimize`, `EveryInc/compound-engineering-plugin`, plus `anthropics/claude-plugins-official` as the canonical marketplace reference. All folded into `skills/manifest.yaml`.

---

## UNVERIFIED — needs human check

- **anti-ui-slop / UIZZE** — no canonical fetchable repo found. Excluded from the manifest pending a real source.
- **Ponytail's star velocity** — RESOLVED, see §8: organic, tied to a verified Hacker News post.
- **superpowers' star velocity** (264,990 stars, 10-month-old repo) — numbers correct, but unlike Ponytail this one was **not** put through the same stargazer-forensics/HN-search pass. Still an open caution, not resolved.
- **Design-tokens MCP** — no candidate clears the "official/high-trust" bar (best options: 4–25 stars). Open category gap.
- **License-less repos** — `obra/the-elements-of-style`, `obra/superpowers-developing-for-claude-code`, `obra/private-journal-mcp`, `figma/mcp-server-guide` all show no LICENSE file via the API. Confirm actual terms before vendoring/redistributing content from these.

---

## §8 — Critical review pass (2026-08-02, advisor-directed)

Founder asked for a deep, adversarial pass to find real gaps/issues in v5 — not generic non-issues. Method: advisor identified the highest-value targets from the full session transcript (not "find more skills" — coverage was already broad); 3 background research agents dispatched against those specific targets; **every load-bearing claim spot-checked directly by hand** (`gh api`, raw source fetches) before being trusted. One agent citation was caught as fabricated in this process (a GitHub issue number attributed content it didn't contain) and excluded — flagging this so the verification discipline itself is visible, not just the conclusions.

### 8a. Memory layer — the one category that was pure design, now load-bearing-checked

Three assumptions in `memory/SPEC.md` were unverified when written. Checked against real Claude Code hook docs (`claude-code-guide` agent, cross-checked):

- **`PostToolUse` (Edit\|Write)**: fires on every single edit, no batching. Default timeout 600s. Docs explicitly warn against *slow* hooks here, though file-writing hooks are normal/supported usage (their own docs show a Prettier-on-every-edit example). → `memory/SPEC.md` updated to note the checkpoint write must stay a cheap append.
- **`PreCompact`**: minimal payload (session_id, cwd, permission_mode — no rich context), 600s timeout. If the hook doesn't finish, compaction proceeds anyway — a real but low-probability risk for a small markdown write given the generous timeout.
- **`SessionEnd`**: **confirmed broken for the design's purpose.** `anthropics/claude-code#35892` ("SessionEnd/Stop hooks should fire on /exit command") is real, closed `not_planned` — a permanent decision, not a bug awaiting a fix. This directly breaks the original "global scope rotates on SessionEnd" design for anyone using `/exit`, the standard exit path. **Fixed in `memory/SPEC.md`**: rotation now happens at the next `SessionStart` (comparing the live checkpoint's `session_id` against the current one), which is guaranteed to fire every session. `SessionEnd` is now best-effort only, nothing depends on it firing.
  - Correction to the correction: the first pass at this citation included a third issue number, `anthropics/claude-code#1395`, attributed the same SessionEnd/Windows content — verified directly and it's real but **completely unrelated** ("Claude Code makes thousands of tool calls to refactor 200 lines"). Excluded. The two issues actually used above (`#34954`, closed `duplicate`; `#35892`, closed `not_planned`) were independently confirmed by fetching each issue's real title, body, and `state_reason`.

### 8b. Manifest conflicts — adversarial pass against 8 entries

Verified directly (hooks.json fetched raw, not summarized) and spot-checked by hand:

- **Ponytail vs `code-simplifier`**: real, third-party-documented duplicate-ownership conflict — a Claude Code config curator dropped `code-simplifier` in favor of Ponytail to stop the two competing for the same job (`bernatmv/ai-rules` PR #9, confirmed **merged**). Neither project is aware of the other in its own docs. Manifest and `rules/engineering.md` corrected: Ponytail is default, `code-simplifier` is an alternative, not a co-installed pair.
- **`semgrep/guardian` vs the "no mechanical gates" premise**: its `hooks.json` (fetched directly from `raw.githubusercontent.com/semgrep/guardian/main/plugin/hooks/hooks.json`) registers a **`PreToolUse` hook on `Write|Edit|Bash`** — the same blocking primitive `phase-gate.js` used (Claude Code's own hook contract: `PreToolUse` exit 2 blocks the call; `PostToolUse` cannot). The advisory scan-and-regenerate behavior lives in `PostToolUse` (fine), but the `PreToolUse` hook's actual enforcement is an undocumented compiled Go binary — unverifiable from outside. Real contradiction of the stated design premise.
- **`semgrep/guardian` on Windows — confirmed broken, this machine's own platform**: `semgrep/guardian#59` (open) — hook silently returns `{}` on every event, no findings ever fire, no cache written. `semgrep/guardian#60` (open) — crashes with a path error when the project is on a different drive than the plugin. Both verified directly (`gh api`, matching titles and open state).
- **`semgrep/guardian` vs `trailofbits/skills` — naming collision**: both ship a skill literally named `semgrep`. Trail of Bits found and tried to fix this exact collision pattern in their *own* plugin (`trailofbits/skills` PR #33, "resolve name collision" — confirmed **closed, not merged**, so the fix didn't land and the collision risk stands). Installing both entries risks silent skill-shadowing.
- **`semgrep/guardian` prompt-injection UX issue**: `semgrep/guardian#46` was real but is closed `state_reason: completed` — i.e., already fixed. Not a live concern; noted for accuracy, not included as an active issue.
- **`obra/superpowers`**: one real, open, non-blocking cosmetic issue — Windows `SessionStart` hook throws a `node:internal/modules/cjs/loader` error every session (`obra/superpowers#1554`, confirmed open). Doesn't block anything, just noisy.
- **CodeRabbit + `semgrep/guardian` + `trailofbits/skills` triple-flagging**: a real *mechanism*-based risk (three independent, uncoordinated invocation paths) but not documented anywhere by any of the three projects — Trail of Bits' own `sarif-parsing` skill exists specifically to dedupe CodeQL+Semgrep findings *within their own plugin*, which is indirect evidence the underlying redundancy problem is real, just not solved across separate plugins.
- **Pairs checked with no real conflict**: Ponytail↔CodeRabbit, Ponytail↔`trailofbits/skills`, Ponytail↔`superpowers`, Ponytail↔`debug-skill`, Ponytail↔`managing-dependencies`, CodeRabbit↔`debug-skill`, CodeRabbit↔`managing-dependencies`, `debug-skill`↔`managing-dependencies`, `semgrep/guardian`↔`superpowers`.

**Resulting manifest changes**: `semgrep-guardian` downgraded from a plain INCLUDE to "not recommended on Windows, do not combine with trailofbits" with all three findings cited; `trailofbits-static-analysis` promoted to recommended default for this environment (its only Windows bug — colon-in-filename, `trailofbits/skills#51`/#52 — is already fixed, unlike guardian's two open ones); `code-simplifier` downgraded from "ship both" to "pick one."

### 8c. Ponytail star-forensics — resolved, not re-flagged

GitHub restricted the fine-grained per-stargazer-timestamp API (`vnd.github.star+json`) platform-wide as of 2026-06-30 (confirmed: the restriction reproduces against `torvalds/linux` and other unrelated major repos with a valid token, and matches GitHub's own changelog post) — so hour-level analysis wasn't directly possible. Worked around it via Wayback Machine-archived snapshots of the repo's public star count over time: a smooth ramp (~250–350 stars/hour at peak) followed by a steady, monotonic week-over-week deceleration (2,730/day → 1,390/day → 590/day) — the textbook shape of organic viral spike-and-decay, not the flat-then-vertical-cliff-then-flat pattern of a bot farm. The ramp's start lines up within ~11 hours of a real, verified Hacker News front-page post (id `48527946`, "Ponytail – make your AI agent think like the laziest senior dev in the room," 98 points, posted 2026-06-14T15:08:17Z — confirmed via a direct fetch of the HN item, title and date match exactly). A 24-account spot-check of stargazers from a dense cluster showed real account-age diversity (2009–2023) and normal follower/repo-count spread, not throwaway accounts. Fork ratio (5.5%) is normal for a popular repo, not the anomalously low ratio bot-inflated repos typically show.

**Verdict: organic.** Ponytail's `required: true` status in the manifest was made on a real signal, not a farmed one.

### 8d. Windows breakage sweep — directly relevant, this session's own platform

Confirmed real, currently-relevant Windows issues beyond what §8b covered: `DietrichGebert/ponytail#645`/`#646` (POSIX/WSL2 hook path issues — the Windows-native hook variant is separately guarded, per the issue titles, so risk to this specific Git-Bash setup is low); `anthropics/claude-plugins-official#3438` (Semgrep/Guardian MCP server fails on native Windows — corroborates §8b independently), `#1366` (a different plugin broken on Windows by a `jq` dependency — matches this session's own experience installing `jq` for `claude-statusline`), `#4589`/`#1693`/`#1432` (bare `npx`/spawn ENOENT on Windows — matches this session's own measured npx slowness). `coderabbitai/claude-plugin` and `AlmogBaku/debug-skill` show zero Windows issues — `debug-skill` because it ships explicit `platform_windows.go`/`platform_unix.go` first-class support (real robustness signal); CodeRabbit because it has almost no issues at all (0 total — low signal either way, though it's the one already running successfully in this exact environment today).

---

## §9 — Mistake-memory / self-learning research (2026-08-02)

Founder reframed v5's core purpose: capture corrections and disproportionate-effort incidents as durable lessons, fully automatic (no `/remember`-style command), with agent-side skepticism (not user-facing approval), zero context-bloat at session start. Trigger for this research: a live incident in this exact session — chasing a statusline emoji fix via external research (plugin greps, changelog search, two subagents) instead of reading the script Claude itself had just written. GitHub-researched, every load-bearing claim spot-checked directly (`gh api`, raw README fetches) before being trusted — same discipline as §8.

### 9a. Platform constraint, verified

No Claude Code hook exposes a semantic "the user just corrected me" signal, and none expose task duration/timing. `UserPromptSubmit`/`PreToolUse`/`PostToolUse`/`Stop` are all mechanical, tool-call-triggered events (confirmed against the same hook docs used for `memory/SPEC.md` in §8a). `/rewind` fires no hook at all. Consequence: detection of a correction or an effort-mismatch has to happen in the agent's own reasoning, in the moment — there is no mechanical substitute. This is consistent with, not a gap in, v5's existing "advisory, not gated" design philosophy (`rules/engineering.md`).

Claude Code's native **Auto Memory** feature (`~/.claude/projects/<project>/memory/MEMORY.md` + per-topic files — this is literally the system governing this session's own `user`/`feedback`/`project`/`reference` memory types) is real, documented prior art for the storage half of this problem, but has no dedicated correction-detector or effort-mismatch trigger of its own.

### 9b. Candidates surveyed

- **`netresearch/retro-skill`** — 3 stars, forks 0, license reported by `gh api` as `NOASSERTION` (repo's own README badge claims "MIT AND CC-BY-SA-4.0" — recording both, discrepancy unresolved, not picking one). `/retro` classifies session friction into one of six destinations (e.g. global memory, project rule, skill PR) with per-proposal human approval before any write — confirmed via direct README fetch. Documents real failure data from its own predecessor, a continuous-hook "Coach" plugin: **1011 pending / 0 approved / 0 rejected candidates, 35MB `events.sqlite`, ~35x duplicate fingerprints of the same issue** — before it was abandoned for the current post-hoc-transcript-read model. **Verdict: closest architectural match for the no-bloat, index-then-detail shape; its failure data is the empirical case for detection happening at correction-time rather than via continuous background hooks. Its per-proposal human-approval gate is NOT adopted — contradicts the founder's explicit "fully automatic" requirement (skepticism must be agent-side, not a user-facing approval step).**
- **`hanfang/claude-memory-skill`** — 46 stars, confirmed real via `gh api`. `core.md` (always-loaded index/pointer) → `topics/*.md` (detail, read on demand) → `projects/*.md`. Plain git-trackable markdown files, no database, no daemon. **Verdict: INCLUDE as the reference file layout** — directly portable to any agent (Cursor/Codex included) that can read markdown, and matches the dual-scope index-then-detail pattern already spec'd in `memory/SPEC.md`.
- **`BayramAnnakov/claude-reflect`** — 1,281 stars, confirmed real. Hooks detect corrections via regex ("no, use X" / "don't do Y" / "actually...") + AI validation. Writes land directly into `CLAUDE.md`/`AGENTS.md`, loaded in full every session; mitigated only by dedup/decay scoring, not lazy-loading. **Corrected in §11 (v2 pass):** this doesn't just fail the no-bloat requirement — its actual source (`scripts/lib/reflect_utils.py`, `commands/reflect.md`, both fetched raw) shows a two-stage pipeline (regex capture, then a real LLM validation call), but *every* item still goes through a human `[a]pprove | [e]dit | [s]kip` gate in `/reflect`, batched rather than per-proposal. It does not solve "fully automatic + non-human skepticism" any better than `retro-skill` did — it just moves the same gate later. **Verdict: CAUTIONARY, not adopted** — fails both the no-bloat requirement and the fully-automatic requirement.
- **`rohitg00/pro-workflow`** — 2,753 stars, confirmed real. `/learn-rule` captures correction-derived rules, but its own README states learnings load in full at `SessionStart`. **Verdict: CAUTIONARY, not adopted** — same failure mode as claude-reflect, at higher star count.
- **`ReflexioAI/reflexio`** — 327 stars, confirmed real, Apache-2.0, pushed same day as this research. A background research agent cited its `EXPERIMENT.md` as showing "~3x better correction-retention than claude-mem" — checked directly, `EXPERIMENT.md` 404s at the expected path, and `benchmark/` contains only an unrelated `gdpval` subdirectory (`gh api repos/ReflexioAI/reflexio/contents/benchmark`). **This specific benchmark claim is excluded as unverified/likely-fabricated** — same treatment as the `#1395` citation caught in §8a. Repo's other facts (existence, star count, license, activity) are independently confirmed and stand.
- **`claude-mem` (`thedotmack/claude-mem`)** — already REJECT-for-default in `skills/manifest.yaml` (crypto-token + curl-pipe-bash red flags). Its search→timeline→detail three-layer retrieval pattern is still a real, worth-citing token-efficiency precedent for general-purpose memory, even though it's not correction-specific and remains rejected as a default install.

### 9c. Resulting design

Two agent-judgment triggers (correction; disproportionate tool-call/turn count relative to apparent task complexity), an explicit agent-side criticality check before any write (is this generalizable, or a one-off/contextual preference the user might have gotten wrong themselves), and storage modeled on `hanfang/claude-memory-skill`'s index-then-detail file layout, layered onto the existing dual-scope (project/global) pattern in `memory/SPEC.md`. Full design in `memory/SPEC.md`'s "Mistake-memory" section. No hooks or working code shipped this pass — spec and manifest entries only.

---

## §10 — mattpocock/skills (aihero.dev), 2026-08-02

Founder-sourced find, via [aihero.dev's "5 agent skills I use every day"](https://www.aihero.dev/5-agent-skills-i-use-every-day). Article fetched and its skill list independently cross-checked against the actual repo (`gh api`, raw `SKILL.md` fetches) — not taken on the article's word alone.

**Repo:** `mattpocock/skills` — 199,684 stars, 17,218 forks (~8.6%, healthy ratio), MIT, pushed 2026-07-31, not archived. Author is Matt Pocock (Total TypeScript / aihero.dev, ~60k-subscriber newsletter) — real, identifiable authority, not anonymous. Ships as an official Claude Code marketplace plugin (`claude plugins install mattpocock-skills`) with decisions tracked in `.agents/adr/`. Confirmed via direct raw fetch: `SKILL.md` frontmatter is exactly Claude Code's real skill spec (`name` + `description`, optional `disable-model-invocation`) — the article's claim about "formatting that confirms 100% usability for Claude Code" checks out against two sampled files (`grill-me`, `tdd`), not just asserted.

Five skills evaluated:

- **`grill-me`** (`skills/productivity/grill-me`) — three-sentence skill, pre-implementation interview to sharpen a plan. **INCLUDE.** No existing manifest entry does this; fills a real gap (nothing forces an explicit pre-implementation alignment step today).
- **`to-spec`** / **`to-tickets`** (`skills/engineering/`) — spec synthesis grounded in real codebase exploration, then vertical-slice ticket breakdown with blocking edges. **INCLUDE**, positioned as the lighter default over `spec-kit`. Notably, this repo's own README independently criticizes GSD/BMAD/Spec-Kit by name for "owning the process" — the same critique this manifest already reached independently for `spec-kit`'s WATCH verdict (§7), from an unrelated author. Cross-corroboration, not just agreement.
- **`improve-codebase-architecture`** — structural-confusion / module-deepening review. **INCLUDE.** Genuinely net-new; nothing else in the manifest reviews architecture, only per-change simplicity (ponytail).
- **`tdd`** (`skills/engineering/tdd/SKILL.md` + `tests.md` + `mocking.md`, ~150 lines total) — evaluated head-to-head against `superpowers`' `test-driven-development` (`SKILL.md` + `writing-good-tests.md`, ~350 lines total), both fetched and read in full, not summarized secondhand.

  **Overlap:** both cover mock-only-at-boundaries, tautological-test detection (near-identical worked example — summing line-item prices), implementation-coupled-test warnings.

  **Unique to `mattpocock-tdd`:** pre-agreed test seams (explicitly confirm the public boundary with the user before writing tests — a real human-in-the-loop step superpowers lacks); mockability-*by-design* (dependency injection, SDK-style interfaces over one generic fetcher with conditional logic) — design guidance, not just mocking discipline.

  **Unique to `superpowers`:** mandatory verify-red/verify-green with literal run commands (not just "watch it fail" as prose); a 10-item rationalization-rebuttal table naming specific excuses ("too simple to test," "already manually tested," "deleting is wasteful") — aimed squarely at agent shortcut-taking under pressure, which is the more relevant failure mode for an autonomous coding agent than for a human; gate-function pre-write checklist pseudocode; a mutation-check correctness bar (mentally mutate the implementation, confirm a test would catch it) with no equivalent in `mattpocock-tdd`.

  **Verdict: keep `superpowers` as the TDD default** — the agent-shortcut-resistant content (mandatory verification, rationalization defenses, mutation check) matters more for this manifest's actual user (an autonomous agent) than repo polish or star count. `mattpocock-tdd` is **not adopted** as a skill swap, but its two distinct ideas (seam confirmation, mockability-by-design) are grafted into `rules/engineering.md`'s new "Designing for testability" subsection. Star count was not the deciding factor either way — `superpowers` (264,996★) actually outnumbers `mattpocock/skills` (199,684★), for what it's worth, though `superpowers`' count still carries the open, unresolved star-forensics caution from §8c that `mattpocock/skills` hasn't been separately put through — roughly a wash, not a tiebreaker.

**Resulting manifest changes:** added `grill-me`, `to-spec`, `to-tickets`, `improve-codebase-architecture` as INCLUDE; added `mattpocock-tdd` as an evaluated-not-adopted entry (kept in the manifest so this comparison doesn't get silently re-litigated by a future pass). `rules/engineering.md` and `WORKFLOW.md`'s "Plan" step updated accordingly.

---

## §11 — Memory architecture v2: closing gaps in `memory/SPEC.md` (2026-08-02)

Founder asked for a deeper review/analyze loop specifically against the memory layer, since both its subsystems (checkpoints, mistake-memory) were still pure pseudocode after two design passes. Method: 3 parallel research agents dispatched against three specific gaps identified by direct read-through first (injection mechanism, dedup/decay, concurrency), each agent's findings independently spot-checked afterward — `gh api` existence/stats confirmed for all six newly-cited repos, and the two most load-bearing claims (`claude-reflect`'s detection code + approval gate, `jayzeng/agentmemory`'s char-budget numbers) verified line-by-line against raw fetches, not taken on the agent's word.

### 11a. The load-bearing finding

**No real prior art solves "fully automatic correction-capture + non-human skepticism + no approval gate" end-to-end.** `netresearch/retro-skill` (§9) gates on human approval. `BayramAnnakov/claude-reflect` (§9, corrected above) turns out to **also** gate on human approval — confirmed via raw fetch of `commands/reflect.md`, every item goes through `[a]pprove | [e]dit | [s]kip`, just batched at `/reflect` time instead of per-proposal. `texastoast/claude-memory-loops` (0★, MIT, confirmed real via `gh api`) has no approval gate but no skepticism step either — verified via raw fetch of `lib/correction.mjs`: its precision lives entirely in detection-time false-positive filtering (strips quoted/code blocks before treating text as a correction, requires a weak cue word to co-occur with a directive verb in the *same sentence*, not just anywhere in the message), then it trusts the model to write whatever it decides to write. Conclusion: the criticality gate in `memory/SPEC.md` can't be imported from anywhere — it has to be fully specified as agent behavior, which is what this pass did (see `memory/SPEC.md`'s "criticality check" section).

### 11b. New repos vetted this pass

- **`coleam00/claude-memory-compiler`** — 1,265 stars, 316 forks, no license set, confirmed real via `gh api`; file tree confirmed to contain `hooks/session-start.py`, `hooks/pre-compact.py`, `hooks/session-end.py`, `scripts/compile.py`, `scripts/flush.py`. Real, working prior art for the exact missing mechanism: a `SessionStart` hook injecting a compiled knowledge index built from prior sessions. **Verdict: INCLUDE as the reference pattern** for the lessons-index injection mechanism — reuse the same `SessionStart` hook already spec'd for checkpoints, don't invent a second one.
- **`jayzeng/agentmemory`** — 13 stars, 2 forks, MIT, confirmed real via `gh api`. Targets Claude Code + Codex + Cursor explicitly (matches this project's own portability requirement). Its `design.md` (fetched raw, grepped directly — not taken on the research agent's summary alone) confirms a real priority-ordered char-budget retrieval model: 16K total context budget, sections built in priority order, "truncated from the start" once the total exceeds budget (open scratchpad items get first priority at 2.0K). **Verdict: INCLUDE as the reference pattern** for bounding the lessons index once it grows past ~50 entries — truncate older entries to pointer-only lines rather than an unbounded flat list.
- **`JustVugg/mnem`** — 44 stars, 9 forks, MIT, confirmed real via `gh api`; `mnem/store.py` confirmed present in the tree. Supersession handled inline in the same markdown file — old value struck through (`~~old~~`) with an HTML-comment timestamp/reason, current-state readers return only non-struck content, full history stays git-diffable. **Verdict: INCLUDE as the reference pattern** for lesson supersession — no delete, no second file, matches this project's plain-markdown-only constraint exactly.
- **`AnastasiyaW/mclaude`** — 6 stars, 1 fork, MIT, confirmed real via `gh api`; README fetched raw (190+ tests claimed, not independently re-run, but the design is concrete and specific enough to trust: `O_CREAT|O_EXCL` lockfiles with stale-lock timeout for mutex, append-only shared logs with unique per-writer filenames, periodic-write files handled via atomic rename). Explicitly tested on Windows 10/11 per its own README. **Verdict: INCLUDE as the reference pattern** for `checkpoint.md`'s read-modify-write concurrency risk.
- **`texastoast/claude-memory-loops`** — 0 stars, 0 forks, MIT, confirmed real via `gh api` (existing, just unpopular — star count is not a red flag here given the specific code was verified directly). See 11a for its detection-precision techniques, adopted as explicit pre-write tests in `memory/SPEC.md`.

**Lower-confidence citations, flagged explicitly, not presented at the same trust level as the above:** a `topoteretes/cognee` claim (auto-routing/session-cache-before-graph-query) came from a WebFetch-summarized README, not a raw fetch or `gh api` call — treat as directionally interesting, not verified. A blog post (`alexandrekhoury.com`, SessionStart hook with hybrid vector+BM25+recency retrieval hard-capped at ~1200 tokens) is similarly WebFetch-summarized — its most useful contribution (the author's own admission that no dedup/decay policy exists and long-term vault noise is an accepted trade-off) is corroborating evidence that this is a known unsolved problem industry-wide, not a pattern to adopt.

### 11c. Concurrency — new ground, not covered by §8-§10

Confirmed via direct fetch of Claude Code's own hooks docs (`code.claude.com/docs/en/hooks.md`, `hooks-guide.md`): hook invocations for the same event run **in parallel**, and Anthropic's own docs acknowledge the resulting race explicitly — concurrent `PreToolUse` hooks returning `updatedInput` resolve non-deterministically, "the last one to finish takes effect." No Claude-Code-specific example of safely serializing writes to a shared state file was found in either doc page. `AnastasiyaW/mclaude` (11b) is the closest real, tested prior art, hence its adoption for `checkpoint.md`'s lockfile pattern. Cross-platform atomic-replace semantics (`os.replace()`) were confirmed directly against `docs.python.org` — but Git Bash `mv` behavior under contention on Windows specifically was **not** independently verified by this research pass, and is recorded as an open item in `memory/SPEC.md` rather than smoothed over, since this project targets Git Bash on Windows as a first-class case.

**Resulting `memory/SPEC.md` changes:** the "Mistake-memory" section's criticality check rewritten from three rhetorical questions into four explicit pre-write tests; a new "Storage" subsection specifying the injection hook, char-budget bound, and supersession pattern; a new top-level "Concurrency" section splitting lessons (append-only, no lock needed) from `checkpoint.md` (lockfile-guarded); an explicit "next step" line naming this as the last spec-only pass before `memory-init.js`/`memory-checkpoint.js` ship. New template: `memory/templates/lesson.md`.

---

## §12 — pdf-inspector (firecrawl) — new `pdf-inspect` skill (2026-08-06)

Founder proposed integrating `github.com/firecrawl/pdf-inspector` after reviewing it for use in `claude-harness` (global skill) and ContraAI (local integration). Method: WebFetch of the repo README/docs, then direct read of the installed npm package's `napi/src/lib.rs`-derived `index.d.ts` (ground truth) rather than trusting the package's own README, plus hands-on verification against real and synthetic PDF buffers before writing any skill instructions.

**What it is:** Rust library (MIT), backed by Firecrawl. Classifies a PDF as `TextBased`/`Scanned`/`ImageBased`/`Mixed` via content-stream sampling (no ML, ~10-50ms), does position-aware text extraction (font + X/Y per item via `extractTextWithPositions`), and converts text-based PDFs to structured Markdown. Single Rust dependency (`lopdf`), no network calls. Node bindings (`@firecrawl/pdf-inspector`, napi-rs, prebuilt binaries for linux x64/arm64, macOS arm64, Windows x64) and a CLI (`pdf2md`/`detect-pdf` via `cargo install pdf-inspector` — **no prebuilt release binaries upstream**, compiles from source).

**Verified discrepancies not in the package's own docs:**
- The npm package's README undercounts its exports — `classifyPdf`, `processPdf`, `detectPdf`, `extractTextWithPositions`, `extractPagesMarkdown`, and a region/table-structure family are all real, current exports per `index.d.ts`, not documented in `napi/README.md`'s own "API" section.
- `PdfType` is declared as `export declare const enum PdfType {...}` — this breaks under TypeScript's `isolatedModules` (a common Next.js/swc setting): `TS2748: Cannot access ambient const enums when 'isolatedModules' is enabled`. Any consumer must compare against the string literal values (`'TextBased'`, `'Scanned'`, etc.), not the enum object.
- `classifyPdf` is **synchronous** — despite being a good candidate to `await`, it executes immediately and can throw on a malformed PDF that a more tolerant parser (Mozilla's `pdf.js`, which `unpdf` wraps) would still accept. Confirmed by direct test: `classifyPdf(Buffer.from('%PDF-1.4\ngarbage'))` throws `classify_pdf: Invalid PDF structure`; an empty buffer throws `Not a PDF: file is empty`. Any integration wrapping this call needs a try/catch that degrades gracefully (fall through to whatever extraction path existed before), not a hard failure.
- Classification confidence is not reliably high on trivial/synthetic input — a hand-built one-page `TextBased` PDF fixture returned `confidence: 0.5` (a coin flip), while a hand-built one-page `Scanned` (image-XObject-only) fixture returned `confidence: 0.95`. This means any consumer using classification to *skip* work downstream (e.g. skip a text-extraction call on a page believed to be non-text) must gate on a confidence threshold, not just the type label — a low-confidence non-text call could be a false positive on a real document, silently discarding retrievable text with no recovery path.

**Verdict: INCLUDE as a new skill, `pdf-inspect`** (`~/.claude/skills/pdf-inspect/SKILL.md`, manifest entry in `skills/manifest.yaml`) — real org, MIT, no red flags, genuinely fills a gap (nothing in this manifest inspects PDF structure/quality before or during extraction debugging). The skill's own "install gate" section documents the CLI's lack of prebuilt binaries explicitly, so a future invocation doesn't assume `cargo install` is a cheap operation.

## §13 — Frontend/design overhaul: gap analysis + two Zarak-submitted repos (2026-08-22)

Triggered by direct feedback that `rules/design-lane.md`'s pipeline still produces "baseless boring" output. Method: `gh api` for every stat cited below (a prior `WebFetch`-based pass on the two submitted repos had been flagged as suspiciously high and treated with distrust pending re-verification — the numbers held up exactly; the caution was warranted as a check, not as a conclusion), direct `SKILL.md`/README fetches for mechanism claims, no secondhand blog citations trusted without a primary-source check.

**Root cause of "still boring," found by reading what's already installed, not by adding a new dependency:** `impeccable` (already adopted, already `required: false` in the manifest) ships `init` ("gather design context... brand vs. product... anti-references") and `bolder` ("amplify boring designs") — but `rules/design-lane.md`'s sequence invoked `ui-ux-pro-max` (a review-against-an-existing-design-system tool) first and only brought `impeccable` in at step 6+ for verification. The fix-capable tool was already in the stack; it just ran after the generic version was already built. `rules/design-lane.md` steps 1–2 reordered to run `impeccable init` and a forced aesthetic-commitment step before any CSS, `ui-ux-pro-max` now runs against that committed direction rather than as the first design input.

**Anthropic's official `frontend-design` skill (`github.com/anthropics/skills`) — real, but blogs cite a retired version as current.** Verified directly against the live `SKILL.md` (not the blog posts describing it): a 2026-06-09 rewrite (commit `2235be7`) removed the 4-question purpose/tone/constraints/differentiation framework, the named-aesthetic-extreme commitment, and the explicit font blocklist (Inter/Roboto/Arial/system fonts/Space Grotesk) that medium.com, chaseai.io, theadpharm.com, and thomas-wiegold.com all describe as its current behavior. The current live version uses looser prose instead. This is the same class of failure this pack's README already logs once (a subagent citing something the source didn't actually contain) — caught here by fetching the primary source directly rather than trusting four independent-seeming blogs that all turned out to describe the same stale snapshot. **Resolution:** the mechanism itself was good and worth keeping, so it's adopted as native prose in `rules/design-lane.md` step 2 rather than as an installable dependency on the skill — depending on the live skill would mean silently losing the mechanism a second time if Anthropic's version drifts again. See `skills/manifest.yaml`'s `reviewed_rejected` entry for the full citation trail. Third-party install-count claims ("277k+," "796k+") could not be verified against any primary source Anthropic exposes and are not repeated as fact.

**`miqdadbadjuber/anti-slop` — real, MIT, complementary, cited via content-fingerprint match, not via the mcpmarket.com listing that surfaced it.** The submitted URL (`mcpmarket.com/tools/skills/anti-slop-frontend-design`) returned a Vercel bot-protection checkpoint on every fetch attempt (WebFetch and curl both) — never loaded directly. Matched to this repo instead by verbatim language overlap between the listing's search-engine summary ("R-01 to R-38... Hard Gate/Purpose-Gate/Quality Locks... Delivery Gate") and this repo's actual README, fetched directly. Its own README frames it as "a filter, not a style guide" — a rule-tiered PASS/FAIL gate with no prescribed colors/fonts/layout of its own, which is why it's additive to `impeccable` rather than a third overlapping choice like `hallmark`. Young (created 2026-08-07, ~2 weeks old at vet_date) — flagged for re-audit at the next check-in rather than treated as a permanently-settled vet the way a multi-year repo would be. mcpmarket.com itself reads as a programmatic SEO directory (near-duplicate listing pages for the same concept under different names) — not cited as a source anywhere; the GitHub repo is.

**`cathrynlavery/diagram-design` — Zarak-submitted, clean pass, added.** 25,238★/1,546 forks/25 contributors (`gh api`-verified, matching the earlier secondhand numbers exactly). No npm/install surface — Python/HTML/SVG, offline, Playwright only for optional PNG export — the lowest-risk candidate audited this pass. Genuinely different content type from `dataviz`/`bklit-ui` (architecture/flowchart/sequence diagrams vs. charts), not a duplicate. Not wired into `rules/design-lane.md` (UI-code-specific); triggers on diagram-shaped tasks directly.

**`heygen-com/hyperframes` — Zarak-submitted, clean security pass, NOT added — out of scope, not unsafe.** 42,058★/4,027 forks/30 contributors, CodeQL running, proper `SECURITY.md`, no pre/postinstall lifecycle scripts (`gh api` + direct `package.json` fetch). It's an HTML→MP4 video-rendering framework (FFmpeg, Puppeteer/Chromium, Git LFS, Docker, ~400MB monorepo) for motion-graphics generation — a different problem domain than the UI-slop issue this pass was run to fix, and this pack has no video/motion-graphics task shape to trigger it on. Documented in `reviewed_rejected` as an out-of-scope disposition, not a safety one, so it isn't silently dropped or re-litigated without cause.

**Applied downstream (ContraAI, not part of this repo but recorded here since it's the vetting record referenced by that integration):** `lib/file-parser.ts`'s classify-before-parse change adopted both guards found above — a `>= 0.9` confidence threshold before skipping `unpdf`, and a try/catch around the synchronous `classifyPdf` call that falls back to direct extraction on any classification error. Neither guard was in the first draft of that change; both were added after a review pass caught the gaps this research section documents.
