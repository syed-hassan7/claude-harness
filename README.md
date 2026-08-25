<div align="center">

# Claude Harness

**A portable skill-and-rules pack for AI coding agents — advisory, not a state machine.**

[![License: MIT](https://img.shields.io/badge/license-MIT-3b82f6.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-6.1.0-3b82f6.svg)](skills/manifest.yaml)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-fully%20installed-3b82f6.svg)](#12-using-it-today)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-3b82f6.svg)](statusline/README.md)

</div>

> [!NOTE]
> **Claude Code is the fully-installed target** — `install.sh` wires rules, skills, memory, and the statusline into `~/.claude`. Cursor and Codex aren't wired up yet: no `adapters/cursor/`, no root `AGENTS.md` ship in this repo today. Everything under `rules/` is plain markdown, though — paste `rules/security-invariants.md` into `.cursor/rules/` or an `AGENTS.md` yourself if you're on one of those.

## Quick start

```bash
git clone https://github.com/syed-hassan7/claude-harness
cd claude-harness
./install.sh
```

Idempotent — safe to re-run after `git pull`. Rules, skills catalog, memory spec, and the statusline, all wired into `~/.claude` in one command. Add `--with-memory-hooks` when you're ready for automatic session checkpoints (opt-in — see [12](#12-using-it-today)).

---

## Contents

01. [What this is](#01-what-this-is)
02. [Why this exists](#02-why-this-exists)
03. [The loop](#03-the-loop)
04. [What's new](#04-whats-new)
05. [Four things that make this different](#05-four-things-that-make-this-different)
06. [Project-architecture memory](#06-project-architecture-memory)
07. [Mechanical backstops](#07-mechanical-backstops)
08. [In practice — receipts, not claims](#08-in-practice--receipts-not-claims)
09. [Statusline](#09-statusline)
10. [What's inside](#10-whats-inside)
11. [Why not gated harness / claude-mem / claude-reflect](#11-why-not-gated-harness--claude-mem--claude-reflect)
12. [Using it today](#12-using-it-today)
13. [Provenance](#13-provenance)

---

## 01 What this is

Most agent harnesses try to control the agent: phase gates, edit ceilings, verifier artifacts you have to produce to prove you didn't skip a step. Claude Harness assumes the opposite — a well-briefed agent doesn't need a cage, it needs good judgment, good defaults, and a memory that gets smarter instead of bigger. Nothing here is a plugin you install to get "control back." It's context you hand the agent.

## 02 Why this exists

This wasn't the starting design — it's the correction. The predecessor (`machina`, still live as a separate repo) was exactly the cage described above: a 12-phase state machine with a rigor dial, a 5-edit pass ceiling, and mechanical Edit/Write blocking until you produced a verifier artifact proving you'd followed the phases in order.

It worked, in the narrow sense that it enforced sequence. It didn't make the agent better at the task — it made the agent better at satisfying the harness, which is a different and less useful thing.

This pack is what's left after asking, file by file, "does removing this make the agent worse at the actual work, or just less supervised?" — the full file-by-file answer lives in `CLAUDE_HARNESS_ANALYSIS.md`, kept as the historical record of that demolition. What survived the cut: `secret-guard.js` (the one hook that blocks something, because "never write a live credential to disk" isn't a judgment call worth leaving to judgment) and everything below, restructured as things an agent reads and reasons about instead of things a state machine enforces.

## 03 The loop

```
Understand -> Plan -> Build -> Verify -> (security-relevant?) -> Security -> Understand
```

No step is mechanically blocked. Skip what doesn't apply, revisit what needs it, do two steps in one turn — judgment, not a phase stored in a state file. Security is the one thing that's never optional: it runs on every turn regardless of where you are in the loop. Full detail: `WORKFLOW.md`.

## 04 What's new

### 6.1.0 — the mechanical layer becomes a family, and it catches its own bugs

A live audit asked one question of every `required: false` entry in `skills/manifest.yaml` (52 of them): does this actually fire as default behavior, or does it just sit as well-written markdown nobody reads at the right moment? Two real gaps turned up, both closed the same way the drift canary already handled its own — an after-the-fact, non-blocking hook, not a rule that hopes to be remembered:

- **[`review-gate-check.js`](memory/hooks/review-gate-check.js)** — a commit ships with no `/review-loop`/`security-audit` evidence anywhere in the session? Logged, surfaced once on the next turn, never blocked. Prompted by a real incident: a prior session shipped exactly that.
- **[`design-lane-gate-check.js`](memory/hooks/design-lane-gate-check.js)** — a commit ships a touched UI file with no screenshot/Playwright evidence in-session? Same treatment. Detection here is almost entirely structural (`tool_name`/`file_path`, not transcript text) — a free-text scan for "done"/"verified" was designed first, then rejected, specifically because caveman-ultra's own house style uses those words constantly for unrelated work in the same session.
- **The canary caught a bug in itself.** Replaying `canary-check.js`'s own detection logic against a real transcript found it batching an entire multi-turn span into one check — one early name-drop was silently covering eight later unnamed citations. Fixed: detection now partitions on real user-turn boundaries, not hook-invocation boundaries. Full story in [08](#08-in-practice--receipts-not-claims).
- Both new hooks went through a real `/review-loop` pass on their own diff before shipping — internal review plus an actual `coderabbit:code-reviewer` pass, not skipped this time. Five findings, four fixed inline, one deferred with a named follow-up (`memory/SPEC.md`).

See [07](#07-mechanical-backstops) for the shape all three hooks share, and `skills/manifest.yaml`'s `known_issues` list for a fourth finding from the same audit that isn't a hook at all — a Claude Code platform constraint (a freshly-added skill can't be dispatched by name until a fresh session reloads the index), routed around instead of chased.

### 6.0.0 — design lane, benchmarked against an external methodology

The design lane was benchmarked against an external "How to Design With AI" methodology — component-library-first, moodboard-over-prose, many-variants-over-one. The existing shadcn-first component search already matched it; three real gaps got closed:

- **[React Bits](https://github.com/DavidHDev/react-bits)** — pre-built animated/personality components, checked before hand-assembling motion from raw primitives. `rules/design-lane.md`, step 5.
- **[Agentation](https://github.com/benjitaylor/agentation)** — click a rendered element, hand the agent its exact selector/position instead of a prose description. `rules/design-lane.md`, step 7.
- **Moodboard-first reference input** — real reference images are now the primary input for the named-aesthetic commitment, not just a verbal style list. Steps 1–2.
- **N-variant judge-panel for open-ended briefs** — generate several genuinely different directions in parallel and score them, instead of one build iterated on rejection. Step 9 — gated behind explicit user opt-in into multi-agent orchestration; it never fires on its own.

The memory layer grew a new store the same release — see [06](#06-project-architecture-memory).

## 05 Four things that make this different

**Learns from being wrong.** Corrections and disproportionate-effort incidents ("this should've taken 30 seconds, it took 10 tool calls") become durable lessons — but only after the agent runs a criticality check on itself first. A wrong correction from you doesn't get silently encoded as gospel.

**Vetted, not vibed.** Every skill in `skills/manifest.yaml` carries a star count, license, and vet date — and the failures are logged too: two fabricated citations caught and excluded mid-research, real Windows bugs cited by issue number, popular tools named as cautionary anti-examples where they deserved it.

**Zero context bloat.** Session memory, lesson memory, and project-architecture memory are all index-then-detail: a one-line pointer loads every time, full content loads only when something actually needs it. Compare to harnesses that dump every learned rule into context at session start.

**Portable by construction.** Rules are plain markdown, skills are a YAML contract, memory is files-on-disk. No daemon, no database, no vendor lock-in to one agent's plugin format.

## 06 Project-architecture memory

Checkpoints capture session continuity. Lessons capture corrections. Neither captures the shape of the codebase itself — a structural decision and why it was made, an invariant worth knowing before touching a file — in a form that survives a checkpoint's trim window and gets recalled without depending on the agent happening to notice a prose description was relevant. This store closes that gap. Full design: `memory/SPEC.md`, "Project-architecture memory."

Recall is mechanical across three hook layers, not agent judgment:

```
Layer 1   SessionStart       ambient index injected every session (project + global, byte-capped)
Layer 2   UserPromptSubmit   keyword match against every prompt; full note injected on a hit
Layer 3   PostToolUse        file-touch match on Read/Edit/Write; flags staleness on Edit/Write
```

Note-*content* — the id, tags, and the fact itself — stays agent-judgment to write, gated the same way lessons are (durability test, duplicate check, tag-collision check). Only recall and staleness-flagging are hook-mechanical: editing a watched file automatically flips its note to `possibly-stale` and prefixes the note's line in `architecture/index.md` with a visible flag, so distrust shows up at the next read without anyone having to check a status field by hand.

## 07 Mechanical backstops

Three rules in this pack are written as "hard," not advisory — and all three used to rely entirely on the agent remembering to follow them, with nothing checking whether it actually did. Each now has the same shape of backstop: a hook that notices after the fact, logs it, surfaces a reminder once, and never blocks anything.

| Rule | Hook | Fires on | Doesn't check |
|---|---|---|---|
| Name Zarak when applying a pack rule (`WORKFLOW.md`) | `canary-check.js` | pack-file citation + name co-occurrence, evaluated per real turn | whether the rule's *substance* was actually followed |
| Run `/review-loop`/`security-audit` before a commit (`CLAUDE.md`) | `review-gate-check.js` | a `git commit`, with no review-marker evidence anywhere in-session | the review's own quality — only that one ran |
| Render-before-judging on UI work (`rules/design-lane.md`) | `design-lane-gate-check.js` | a `git commit` touching a UI file, with no screenshot/Playwright evidence in-session | whether the screenshot was actually looked at |

Same design across all three, deliberately: a sticky per-session flag rather than re-arming on every single action (matches how these rules are actually used — verify once, ship several times); a crisp structural trigger where one exists (a commit) instead of fuzzy language-matching; log-and-surface-once, never gate. All three are opt-in, ship inside `--with-memory-hooks`, and none of them install themselves without you asking.

## 08 In practice — receipts, not claims

The points above are easy to assert and hard to verify from the outside. There's no formal before/after benchmark yet — an earlier attempt (for the old `machina` v4 harness) turned out to measure the wrong thing entirely: single-shot stateless subagents with no tool calls and no hooks firing, so it only tested whether injected prose changed output, never whether the mechanical layer did anything. That attempt is documented, not repeated. A real one needs a clean machine, N≥5 runs per task, and genuine multi-turn sessions where hooks actually fire — an open item, not swept under the rug.

What exists instead is real incidents from actual sessions, the kind a benchmark would be trying to approximate anyway.

**A fabricated citation, caught before it shipped.** During the 2026-08-02 adversarial research pass, a subagent attributed content to a GitHub issue number that the issue didn't actually contain. Caught because every load-bearing claim in that pass got spot-checked directly (`gh api`, raw source fetches) instead of trusted on the subagent's word — see `skills/RESEARCH.md`, §8.

**Five commits to make CI tell the truth.** `.github/workflows/test.yml` shipped once, then broke four more times on real OS differences before it passed clean on Windows, macOS, and Ubuntu: `set -e` aborting the whole suite on a clean runner, `touch -d` being GNU-only, a hardcoded `PATH` dropping `jq` on `ubuntu-latest`, and that runner's `jq` turning out to be a Chocolatey shim, not a copyable binary. Each fix is its own commit, titled honestly ("Fix CI failure #4," not "improve CI").

**The mistake-memory system's first real lesson, written the hard way.** The self-learning design in `memory/SPEC.md` shipped with a schema and a criticality gate but zero lessons ever actually written — until a session where a confident advisor recommendation got chained straight into an unauthorized edit of `skills/manifest.yaml`, the user caught it immediately, and the resulting lesson became the mechanism's first real write. The point isn't that the mistake happened — it's that the pack has a place for it to go that isn't "forgotten by next session."

**The drift canary caught a bug in itself, the same day it gained two siblings.** A routine health-check replayed `canary-check.js`'s own regex logic against the live session transcript and found it silently missing eight citations in a row — not a flaw in the concept, but in the batching: an entire multi-turn span with no user message in between got treated as one check, and a single early name-drop satisfied the whole batch. Fixed same-session, two regression tests added — one reproducing the exact incident, one confirming the original within-one-turn merge behavior still holds. "Vetted, not vibed" turned out to include vetting the pack's own mechanisms, not just third-party skills.

None of this substitutes for the benchmark that doesn't exist yet. It's what "learns from being wrong" and "vetted, not vibed" cash out to when something actually goes sideways.

## 09 Statusline

Everything else here is context an agent reads. This is the one thing *you* look at: model, color-coded context %, directory + git branch, session duration, effort level, and both rate-limit windows — each with a plain countdown to when it resets, not just a bar that fills up with no sense of when it lets go.

```
Sonnet 5 │ Context Window: 34% │ claude-harness (main*) │ ⏱ 1h12m │ ● high

current ●●●●○○○○○○  34% ⟳ resets in - 2 hrs 3 mins
weekly  ●●○○○○○○○○  28% ⟳ resets in - 5 days 3 hrs
```

`./install.sh` wires this up automatically. Full field-by-field breakdown, the jq dependency, and what happens if it's missing (an honest one-line error now, not fabricated-looking data) in [`statusline/README.md`](statusline/README.md). Two minutes, immediately visible, no adoption curve.

## 10 What's inside

<details>
<summary><strong>Expand the full directory layout</strong></summary>

```
rules/
├── engineering.md          Ponytail YAGNI baseline + debugging, review, static
│                           analysis, dependency hygiene, perf, planning,
│                           architecture review, testability design
├── design-lane.md          UI/UX sequence — triggered by task shape, not
│                           always-on; render-before-judging step is now
│                           mechanically backstopped (07)
└── security-invariants.md  One always-on invariant set, every session, every surface

memory/
├── SPEC.md                 Automatic dual-scope session checkpoints,
│                           mistake-memory, project-architecture memory
│                           (mechanical recall via UserPromptSubmit +
│                           PostToolUse), and three mechanical backstops —
│                           canary-drift, review-gate, design-lane gate (07)
├── templates/              checkpoint.md, lesson.md, architecture.md schemas
└── hooks/                  Working, opt-in hook implementation — see
                             "Using it today" below (install.sh --with-memory-hooks)
    └── test/run.sh         49-case suite incl. Windows lockfile concurrency,
                             archive trim boundaries, stale-lock reclaim,
                             architecture-memory recall/staleness, canary-miss
                             open/resolve/escalate/expire-on-prune/per-turn
                             granularity, review-gate miss/clean/reminder/
                             expire-on-prune, and design-lane-gate miss/clean/
                             reminder/expire-on-prune/early-return — run
                             after touching anything under memory/hooks/

skills/
├── manifest.yaml           55 skills, 12 categories, portable contract
└── RESEARCH.md             The sourced, spot-checked research trail — read this
                            when you don't want to take the manifest on faith

caveman/                    Default-on terse communication mode — hooks + skill,
                            see WORKFLOW.md's Communication baseline

onboarding/                 First-run install wizard, 2 surfaces sharing 1 source
├── steps.json               of truth: question wording (both surfaces) +
├── verify.js                mechanical post-install check (both surfaces)
├── skills/onboarding/       in-CLI counterpart to install.sh --onboard
└── test/run.sh              sandboxed suite — CLAUDE_HARNESS_TARGET + XDG_CONFIG_HOME

visual-plan-local/          Default plan-mode output: structured doc + Artifact,
├── skills/visual-plan-local/ not a long chat paragraph. Zero MCP/daemon —
├── references/               see the manifest entry for why, vs. BuilderIO's
├── template.html              hosted visual-plan
└── vendor/diagram-design/    vendored MIT diagram engine, see its NOTICE.md

audit-log/
└── SECURITY_SPEC.md         Spec only, not yet implemented — opt-in PostToolUse
                             hook design for GRC/compliance data-access logging

statusline/
├── statusline.sh            Drop-in ~/.claude/statusline.sh — see section above
├── README.md                Setup + what each field means
└── test.sh                  Regression test — run after touching statusline.sh

install.sh                  Idempotent installer — pack files -> ~/.claude/claude-harness/,
                             statusline -> ~/.claude/statusline.sh, marked pointer
                             block -> ~/.claude/CLAUDE.md. See "Using it today" below.
WORKFLOW.md                 The loop above, in full
CLAUDE_HARNESS_ANALYSIS.md  Historical planning doc — analyzes the separate
                             machina v4 repo's demolition (never executed);
                             not this repo's own file history
```

</details>

## 11 Why not gated harness / claude-mem / claude-reflect

| | Phase-gated harnesses | Context-dumping memory tools | Claude Harness |
|---|---|---|---|
| Blocks a tool call on a missing artifact | Yes | No | **Never** |
| Loads every learned rule at session start | No | Yes | **No** — index first, detail on demand |
| Silently trusts every correction as valid | No | Usually | **No** — criticality check before it's written down |
| Every pick independently vetted | Rarely | Rarely | **Yes** — `skills/RESEARCH.md` |

## 12 Using it today

```bash
./install.sh                      # rules + skills catalog + memory spec + statusline
./install.sh --with-memory-hooks  # ^ plus automatic session checkpoints (opt-in)
./install.sh --onboard            # interactive wizard for the 2 real choices above, ends with a mechanical verify
./install.sh --dry-run            # preview every write any of the above would make, write nothing
```

Copies `rules/`, `skills/`, `memory/`, and `WORKFLOW.md` into a namespaced `~/.claude/claude-harness/` (never touches `~/.claude/skills/` or `~/.claude/memory/` directly — those are host-owned, live directories), installs the statusline script, and writes a single marked, re-runnable pointer block into `~/.claude/CLAUDE.md` — the one file Claude Code actually auto-loads every session.

`--onboard` is the cold-start, bash-only path — it prompts for memory hooks + caveman intensity, then proves both landed via `onboarding/verify.js` instead of trusting its own stdout. Already mid-session instead? Say **"onboard me to claude-harness"** or `/harness-onboard` — the in-CLI counterpart asks the same 2 questions through `AskUserQuestion`, offers a scratch-directory dry run first, and renders the verify result as a lit-up status page. Both surfaces read `onboarding/steps.json` for their wording, so they never drift apart — see the `onboarding` entry in `skills/manifest.yaml`.

Plan mode's own output is also covered: `visual-plan-local` renders non-trivial plans as a structured document plus a rendered `Artifact` companion (diagrams, real hierarchy, scannable structure) instead of a long chat paragraph — the default for plan mode's "Final Plan" step, not something you have to name. It's a local, zero-MCP counterpart to BuilderIO's `visual-plan`, built after finding that skill's real actions all require a hosted third-party connector with no offline fallback — see the `visual-plan-local` entry in `skills/manifest.yaml` for the full gap analysis and its vendored `diagram-design` (MIT) rendering engine.

> [!IMPORTANT]
> What it deliberately does **not** do:
>
> - **Doesn't touch `settings.json`.** That file holds your existing hooks config — auto-editing structured JSON next to hooks you already depend on is a real corruption risk for no real benefit. If no `statusLine` block is found, the script prints the exact JSON to add by hand (see `statusline/README.md`). The same applies to `--with-memory-hooks`: it copies the hook files and prints the settings.json snippet, but you paste it in yourself.
> - **Doesn't copy `rules/security-invariants.md` verbatim into `CLAUDE.md`.** If your `CLAUDE.md` already has hand-written security rules, a blind verbatim append duplicates them under different wording — the opposite of this pack's zero-context-bloat pitch. The pointer block links to the canonical file instead; dedupe your existing prose against it yourself, on your own schedule.
> - **Doesn't install memory hooks by default even with the flag copied.** They fire on every single Edit/Write once wired — new code, tested (49 cases incl. Windows lockfile concurrency, archive trim boundaries, stale-lock reclaim, architecture-memory recall/staleness, canary-miss open/resolve/escalate/expire-on-prune/per-turn granularity, review-gate miss/clean/reminder/expire-on-prune, design-lane-gate miss/clean/reminder/expire-on-prune — see `memory/SPEC.md`), but "tested" and "proven in production" aren't the same claim. Wire them when you're ready, not because a flag exists.

For Cursor/Codex, or if you'd rather not run a script: everything above still applies by hand — point `AGENTS.md`/`.cursor/rules/` at `rules/security-invariants.md`, reference `rules/engineering.md` + `rules/design-lane.md` + `skills/manifest.yaml`, and treat `memory/SPEC.md` as the memory-layer spec.

## 13 Provenance

Nothing in `skills/manifest.yaml` or `rules/` is asserted without a source. `skills/RESEARCH.md` has the full trail — stars, licenses, issue numbers, and the citations that didn't survive verification and were cut. If you're going to trust a pack of rules an agent reads every session, that trail is the part worth reading first.

<div align="center">

---

Licensed under [MIT](LICENSE) · Built for Claude Code, adaptable everywhere else

</div>
