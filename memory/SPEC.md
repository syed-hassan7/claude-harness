# Claude Harness memory layer — automatic, dual-scope

**Status:** implemented, opt-in. Working hooks ship at `memory/hooks/*.js`, installed via `./install.sh --with-memory-hooks` (default off — see that file's usage comment for why). This document is still the design record; where it now differs from the pseudocode below, `memory/hooks/*.js` is the source of truth. One real gap found and fixed during implementation, kept here rather than smoothed over: `walkForGitRoot`'s scope-detection walk originally had no upper bound, so a git-tracked home directory (dotfiles-as-repo — yadm, chezmoi, bare `git init ~`, all common) would make **every** global-scope session anywhere on disk resolve as project scope rooted at the home directory, once the walk reached `~/.git`. Fixed by capping the walk at (and never counting) the home directory itself — see `memory/hooks/_lib.js`. Caught by testing against a real machine with a git-tracked home dir, not by inspection.

## Problem this replaces

- **v4 (`claude-mem`/`graphify`):** optional, full-profile-only, manual start, no background worker by default. Per `harness.md` §7: "Install via `make profile-setup PROFILE=full`... not installed by default." No real continuity for the common case.
- **Cursor's existing pattern** (already live in this repo at `.cursor/session/checkpoint.md`): works, and is the direct model for v5 — but keyed to Cursor's own compact/hook mechanism, and the user must still be aware a compact is happening (watch the HUD, or run `/compact`).

**Goal:** zero manual memory commands in normal use. Project work persists across sessions; terminal-only (no-repo) work gets a lighter, self-pruning global lane.

## Verified constraint (checked against real Claude Code hooks, 2026-08-02)

Claude Code hooks do **not** expose a context-usage percentage to any hook input — there is no way to threshold-gate on "~50% full." What *does* exist: `PreCompact` (fires before Claude Code's own auto-compaction) and `PostCompact` (fires after). The source plan's "context ~50%: auto-compact" trigger is retargeted honestly to **`PreCompact`** — the hook fires whenever Claude Code itself decides to compact, and that is the correct moment to archive the live checkpoint before context is lost, regardless of the percentage that triggered it. This is a stronger guarantee than a hand-rolled threshold: it fires exactly when loss would otherwise occur.

Real hook events used below (confirmed against Claude Code docs): `SessionStart`, `PostToolUse` (matcher `Edit|Write`), `PreCompact`, `PostCompact`, `SessionEnd`. All five exist today; no fabricated event names.

**Correction, 2026-08-02 (critical-review pass):** the design below originally relied on `SessionEnd` to rotate the global-scope checkpoint. That's broken for the common case — confirmed via a real, closed-`not_planned` GitHub issue that `SessionEnd`/`Stop` hooks do **not** fire on the `/exit` command, the standard way to end a session (`anthropics/claude-code#35892`). Anthropic isn't fixing this; it's a permanent gap, not a bug in flight. Relying on `SessionEnd` for global-scope rotation would mean "only last session live" silently never rotates for anyone who types `/exit`.

**Fix:** do the rotation check at `SessionStart` instead, which is guaranteed to fire every session (that's how a session begins). The live checkpoint carries the `session_id` it was written under (a real field already present in hook input); on the next `SessionStart`, if a live global checkpoint exists and its `session_id` differs from the current one, that checkpoint belongs to a session that has already ended — inject it once (as "previous session" context), then immediately archive it, so the new session's `PostToolUse` writes start a fresh live checkpoint. `SessionEnd` is kept only as a best-effort final write (nice-to-have if it does fire), never load-bearing. See the updated hook table and pseudocode below.

Two other assumptions in this design were checked, not just assumed, in the same pass: `PostToolUse` firing on every single Edit/Write (confirmed, no batching — Claude Code's own docs warn against *slow* hooks on this event, which is why the checkpoint write below must stay a cheap append, not a full re-render) and `PreCompact`'s payload/timeout (confirmed minimal payload, 600s default timeout — generous enough that a small markdown write is not at real risk of being killed mid-write, unlike the SessionEnd case).

## Two scopes

| Scope | When | Live file | Archive policy | Inject on start |
|-------|------|-----------|-----------------|------------------|
| **Project** | cwd inside a git repo | `<repo>/.claude/session/checkpoint.md` | Last 10 checkpoints, 7 days max (matches the existing Cursor pattern in this repo) | Live checkpoint + compact archive index (paths + one-line summaries, not full archive contents) |
| **Global** | cwd not in a repo (home, scratch dir) | `~/.claude/session/checkpoint.md` | Only the **last session** kept live; everything older rotates to archive | Live checkpoint only |

Scope detection at `SessionStart`: walk cwd → ancestors for a `.git` directory. Found → project scope. Not found → global scope. (Same resolution shape as v4's `resolveHarnessRoot()` in `harness-lib.js`, minus the harness state it was resolving.)

## Automatic triggers — hook table

| Hook event | Matcher | Action |
|------------|---------|--------|
| `SessionStart` | — | Detect scope (git-root walk). Read live checkpoint if present; inject it + archive index into context. **Global scope only:** if the live checkpoint's `session_id` != current `session_id`, it belongs to an already-ended session — inject it, then archive it immediately (this is the rotation trigger, not `SessionEnd` — see correction above). |
| `PostToolUse` | `Edit\|Write` | Rolling update to the live checkpoint: append/update `files touched`, refresh `goal`/`next` if materially changed, timestamp `updated`. Keep this a cheap append, not a full re-render — this event fires on every single Edit/Write, no batching. |
| `PreCompact` | — | Archive the current live checkpoint (timestamped copy into scope's archive dir) *before* Claude Code compacts, so nothing is lost. Then refresh the live checkpoint with a compressed summary of what's about to be compacted away. |
| `PostCompact` | — | Optional: re-inject the freshly archived checkpoint reference so post-compaction context has an explicit pointer back to it. |
| `SessionEnd` | — | Best-effort final write only, not load-bearing (confirmed unreliable — doesn't fire on `/exit`, see correction above). Project scope: live checkpoint simply persists regardless (subject to the 10-checkpoint/7-day trim, which runs on `PreCompact`/next `SessionStart`, not `SessionEnd`). |
| `UserPromptSubmit` | — (no matcher support for this event) | `memory-recall.js` — architecture-memory only, not checkpoints/lessons. Mechanically greps the raw prompt text against every architecture note's `tags`/`project` columns (project + global index, both scopes); on a match, injects the matched note's full `## Summary`/`## Detail` content via `hookSpecificOutput.additionalContext`. Fires on every single prompt — verified against Claude Code's own hooks-guide.md that this event has no matcher and always fires, so this hook must stay cheap (index reads only, no directory scans). |
| `PostToolUse` (2nd registration) | `Read\|Edit\|Write` | `memory-architecture.js` — architecture-memory only, separate hook file and separate matcher from the checkpoint hook's `Edit\|Write` registration above (Claude Code runs both; they don't conflict). Looks up the touched file's repo-relative path in `watch-map.json`; on a match, injects the linked note's `## Summary` via a **flat top-level** `additionalContext` field (verified: PostToolUse's output shape is NOT nested under `hookSpecificOutput`, unlike `SessionStart`/`UserPromptSubmit` — confirmed against code.claude.com/docs/en/hooks.md). On `Edit`/`Write` specifically (not `Read`), also flags the note `possibly-stale` and prefixes its `architecture/index.md` line with `[STALE?]`. Global scope is a no-op here (`watch_files` are repo-relative; no meaningful match without a repo). |

**Design principle:** hooks do the work; rules (`WORKFLOW.md`, this file) tell the agent what was injected and how to use it. The user never runs a memory-specific slash command in normal use.

### Pseudocode

```
// memory-init.js  (SessionStart) — rotation happens HERE, not in SessionEnd
scope = walkForGitRoot(cwd) ? "project" : "global"
dir = scope == "project" ? "<repo>/.claude/session" : "~/.claude/session"
if exists(dir/checkpoint.md):
  cp = read(dir/checkpoint.md)
  inject(cp)
  inject(archiveIndex(dir/archive))  // filenames + one-line goal each, not full contents
  if scope == "global" and cp.session_id != current.session_id:
    // live checkpoint belongs to an already-ended session (SessionEnd may
    // never have fired for it — that's fine, we don't depend on it).
    // It was just injected above; now retire it so this session's writes
    // start a fresh live checkpoint.
    archive(dir/checkpoint.md -> dir/archive/<timestamp>.md)
    delete(dir/checkpoint.md)

// memory-checkpoint.js  (PostToolUse, matcher: Edit|Write)
cp = readOrInitCheckpoint(dir/checkpoint.md)
cp.session_id = current.session_id
cp.files = mergeTouched(cp.files, toolInput.file_path)
cp.updated = nowISO8601()  // supplied by hook input, not Date.now()
cp.next = maybeRefresh(cp.next, recentAssistantIntent)
stripSecretPatterns(cp)  // never persist secret values, only "key X set: yes/no"
write(dir/checkpoint.md, cp)  // cheap append-style write — fires on every Edit/Write, keep it fast

// memory-compact.js  (PreCompact)
archive(dir/checkpoint.md -> dir/archive/<timestamp>.md)
trimArchive(dir/archive, scope)  // project: keep 10 / 7 days; global: keep 0 (all older than the one being archived now)
write(dir/checkpoint.md, compressedSummary(cp))

// memory-flush.js  (SessionEnd) — best-effort only, nothing downstream depends on this firing
finalizeCheckpoint(dir/checkpoint.md)
```

## Forensic lookup (user asks about past work)

Rule, not a hook: when the user asks "what did we do yesterday" / "what was the state of X last week," the agent globs the scope's `archive/` directory, reads **one file at a time** (never dumps the whole archive into context), and cross-checks against `git log`/`git blame` for anything time-sensitive. This mirrors the existing note in the Cursor checkpoint file at `.cursor/session/checkpoint.md`: *"Do not re-explore the repo from scratch."*

## Checkpoint schema

See `memory/templates/checkpoint.md` for the literal template. Fields: `scope`, `repo`, `updated`, `goal`, `done`, `next`, `files`, `decisions`, `blockers`.

## Comparison vs. the existing Cursor pattern (`.cursor/session/checkpoint.md`, live in this repo today)

| Field / behavior | Cursor (existing, this repo) | Claude Harness v5 (this spec) |
|---|---|---|
| Trigger | Cursor's own compact mechanism + manual `/compact` awareness | Fully automatic: `SessionStart`/`PostToolUse`/`PreCompact`/`SessionEnd` — no manual command in normal use |
| Scope | Single file, implicitly project-scoped (`workspace:` field) | Explicit dual-scope: project (persistent, 10/7-day trim) vs. global (last-session-only) |
| Fields | `updated_at`, `compact_at`, `workspace`, `branch`, Goal, Files touched, Git delta, "After compact" note, Recent user messages | `scope`, `repo`, `updated`, `goal`, `done`, `next`, `files`, `decisions`, `blockers` — adds explicit `decisions` (non-obvious choices) and `blockers`, drops raw `Recent user messages` transcript in favor of a distilled `next`/`blockers` |
| Archive | Not observed in the current file (no `archive/` dir present alongside it) | Explicit archive dir per scope, with an explicit trim policy (10 checkpoints / 7 days project; last-session-only global) |
| What's better than Cursor's `/compact` habit | User must notice/trust the HUD or run `/compact` | Trigger is `PreCompact` — fires exactly when Claude Code itself is about to compact, guaranteed, not dependent on the user noticing a percentage |

**What is explicitly better than manual `/compact`:** the trigger is tied to the real compaction event (`PreCompact`), not a percentage the user has to watch for and act on. The archive-before-compact write happens whether or not the user is paying attention.

## Evaluate vs. adopt (Phase 8 requirement)

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **A. File-based hooks** (this spec) | Simple, no daemon, gitignored, fully portable across Claude Code/Cursor/Codex, no install friction | No semantic search — forensic lookup is glob + read, not query | **Recommended default for v5 ship** |
| **B. claude-mem MCP** | Semantic recall, timeline queries | Background worker, install friction, per `harness.md` §7 was optional/full-profile-only in v4 and not installed by default — maturity unverified pending `skills/RESEARCH.md` | Document as optional power-user adapter only, not default |
| **C. Hybrid (A + claude-mem)** | Files for continuity + semantic query for "what did we decide about X" | Two systems to maintain; only worth it once A's forensic-lookup glob proves insufficient in practice | Document as `memory/claude-mem.md` optional adapter, not built by default |
| **D. Ponytail-style AGENTS.md only** | Zero infra | No real session memory — the exact gap this whole layer exists to close | Rejected |
| **E. SQLite FTS5 for forensic lookup** (mined from `NousResearch/hermes-agent`'s session-search design, 2026-08-11) | Real full-text search (~20ms), no daemon — a library + file, not a running server, so it doesn't reintroduce the background-worker friction that sank **B** or `moi.computer` | New dependency against `_lib.js`'s current zero-dependency stance; Node's built-in `node:sqlite` was Stability 1.2 (release candidate, not fully stable) as of Node 25.7 per Node's own docs checked this date — verify current status before adopting, don't assume; `better-sqlite3` avoids that but needs a native build toolchain, the exact friction `pdf-inspect`'s entry in `skills/manifest.yaml` is praised for avoiding. Also unclear this is a real problem yet at current archive scale (10 checkpoints/7-day trim, single lessons index) — YAGNI rung 1 | **WATCH, not adopted.** Revisit only if/when glob-and-read-one-file-at-a-time forensic lookup actually becomes slow or unwieldy in practice — a real bottleneck, not a hypothetical one. If that day comes, prefer `node:sqlite` over `better-sqlite3` once it's fully stable, specifically to avoid the build-toolchain requirement. |

**Recommendation:** ship **A** (this spec) as the v5 default. Document **C** as an optional adapter note for power users once claude-mem's current maintenance status is confirmed in `skills/RESEARCH.md`. **E** is documented for the same reason as **C** — a real, named upgrade path, not built until its trigger condition is actually met.

## Mistake-memory (self-learning from corrections and wasted effort)

**Status:** split, precisely. **Detection and writing are spec + rules only, by design** — no hook fires on "the user just corrected me" (see below), so a lesson only ever gets written by the agent's own judgment passing the criticality check. **Injection is implemented**: `memory/hooks/memory-init.js` reads `<scope>/lessons/index.md` at `SessionStart` and injects it alongside the checkpoint, same as this section's "Injection" bullet below describes — that part is no longer spec-only, it shipped with the checkpoint hooks. Research trail: `skills/RESEARCH.md` §9 and §11 (§11 is a v2 pass that found and closed four real gaps in this section — read it if you want the "why," not just the "what"). Manifest reference entries: `skills/manifest.yaml`.

This is distinct from the checkpoint system above — checkpoints persist *session continuity* (what was I doing); this persists *lessons* (what did I get wrong, and why won't I repeat it). Same dual-scope split, different content and a different write trigger.

### Why this isn't hook-driven

No Claude Code hook exposes a semantic "the user just corrected me" signal, or task duration/timing (verified against the same hook docs used above). Detection has to happen in the agent's own reasoning, at the moment it occurs — not a background process. `netresearch/retro-skill`'s own README makes the empirical case for this: its predecessor, a continuous-hook friction-detector, produced **1011 pending / 0 approved / 0 rejected candidates and a 35MB SQLite of ~35x duplicate fingerprints** before being abandoned. Continuous background detection accumulates noise; judgment at the moment of the incident does not.

### Two triggers, both agent-judgment

1. **Correction** — the user redirects an approach mid-task.
2. **Effort-mismatch** — at task completion (or correction): did tool-call count and turn count wildly exceed what this task's apparent complexity warranted? Worked example, from this project's own session history: identifying a fire-emoji statusline glyph took ~10 tool calls and two subagents (plugin greps, changelog search, doc fetches) for what was, in the end, a one-line emoji swap in a script written by the same agent minutes earlier. The useless lesson would be "check statusline.sh" — too narrow to ever fire again. The correct distillation: **"when debugging output from code written this session, read that code directly before researching externally."** That distinction — incident log vs. extracted, generalizable rule — is what separates a useful lesson from the noise `claude-reflect`/`pro-workflow` accumulate (both load every captured lesson in full at session start — see `skills/manifest.yaml`).

### The criticality check — an actual gate, not rhetorical questions

**No prior art solves "fully automatic + non-human skepticism + no approval gate" end-to-end** (checked directly, `skills/RESEARCH.md` §11): `retro-skill` and `claude-reflect` both gate on human approval — `claude-reflect`'s is just batched later at `/reflect` (`[a]pprove | [e]dit | [s]kip`) rather than per-proposal, not actually different in kind. `claude-memory-loops` has no approval gate but no skepticism step either — its precision is entirely in detection-time regex, then it trusts the model to write whatever it wants. So this gate has to be fully specified here, not imported. Before writing a correction down, run these as explicit pre-write tests, in order:

1. **Strip quoted/code blocks** from the triggering message first — a pasted error log or quoted file content is not a correction (borrowed technique, `texastoast/claude-memory-loops`).
2. **Veto on non-correction phrases** — "no problem," "never mind," "don't worry," "no worries," a message ending in `?` — these read like correction openers but aren't (borrowed list, `claude-reflect`'s `NON_CORRECTION_PHRASES`).
3. **Require co-occurrence in the same sentence**, not just anywhere in the message: a weak cue ("actually," "instead") only counts if it sits next to a directive verb in the same sentence (`claude-memory-loops`).
4. **Generalizability test** — would this same approach actually be wrong in a *different* context, or was this situation-specific? The founder named the failure mode this guards against explicitly: "I could wrongfully correct you while your approach was right." If genuinely uncertain and it matters, say so in the moment instead of silently encoding a lesson that might be wrong.
5. **Duplicate check** (added 2026-08-11, mined from `NousResearch/hermes-agent`'s memory tool — it rejects exact-duplicate entries at write time). Before writing, read the current scope's `lessons/index.md`; if a line with substantially identical content (same `id`, or the same generalizable rule already stated) already exists, do not write a new entry. This is not a fifth veto on whether a correction is genuine — items 1–4 already settled that — it's a final backstop specifically against the failure mode `retro-skill`'s own predecessor hit (~35x duplicate fingerprints accumulating because nothing checked before writing, not because detection was too loose).

Only a correction that survives all five gets written down. This is agent-judgment applied through explicit tests, not a vibe — the tests exist specifically because nothing else does this and false positives silently poison the lesson store.

### Storage — schema, injection, and what happens past ~50 lessons

- **Schema:** `memory/templates/lesson.md` — same concreteness as the checkpoint template, not a vague pointer to someone else's file layout.
- **Injection:** the lessons index rides the **same `SessionStart` hook** already spec'd for checkpoints above — add a second injection block there, don't invent a separate mechanism. (This was a real gap until this pass: the index was called "always-loaded" but no hook actually loaded it. Validated pattern: `coleam00/claude-memory-compiler`, `hooks/session-start.py`.)
- **Bounded injection:** priority-ordered char budget on what actually gets injected, not an ever-growing flat list — verified pattern, `jayzeng/agentmemory`'s `design.md` (16K total budget, tiered by section, truncated from the start once over budget). Once the lessons index would exceed its budget, truncate older entries to pointer-only lines (id + one-liner + file path), never drop them outright.
- **Supersession, not deletion:** when a later session invalidates an old lesson, strike it through inline in the same file (`~~old lesson text~~` + an HTML-comment timestamp/reason) rather than deleting it — verified pattern, `JustVugg/mnem`. Keeps history git-diffable, no second file to reconcile.
- Same scope split as the checkpoint system: project-specific lessons live in the repo, general/cross-project ones live globally.
- **Explicit non-goal:** no continuous background hook accumulates candidates. Detection and the criticality gate both happen inline, in the agent's own turn, at the moment a correction or effort-mismatch is recognized — never as a batch pass over a transcript log.

### Considered and deferred: a durable user-profile file

`NousResearch/hermes-agent` splits its memory into `MEMORY.md` (agent notes) and `USER.md` (durable user profile — preferences, communication style — distinct from both session-scoped checkpoints and correction-scoped lessons). Considered adding an equivalent global-only sibling file here, 2026-08-11, and deferred: for a Claude-Code-only user, this would be a third store for content already covered by Claude Code's own native per-user memory and by `~/.claude/CLAUDE.md`'s standing preferences section, with no write trigger distinguishing it from either. The portability case (Cursor/Codex don't get Claude Code's native memory) doesn't hold today — those adapters are named as a future ambition in this repo's own README, not shipped. Revisit if/when a non-Claude-Code adapter actually ships; don't build the file or its `memory-init.js` injection block before then.

## Project-architecture memory (self-improving structural knowledge)

**Status: designed 2026-08-22, hooks implemented same day** (`memory-recall.js`, `memory-architecture.js`, plus the injection blocks in `memory-init.js` — see the hook table above). Design produced by a 4-lens judge-panel workflow (durability-first, retrieval-precision-first, YAGNI-first, architecture-drift-first — one agent per lens, independently, then synthesized), finalized against Zarak directly on the open questions the synthesis left. One of the four lens agents (durability-first) returned no usable content and was excluded rather than smoothed over; the design below rests on the other three, which converged. All file:line citations below were spot-checked directly against `_lib.js`/`memory-init.js`/`memory-compact.js`/`lesson.md` before being written down here — not taken on the synthesis agent's word (this pack's own "vetted, not vibed" standard applies to internal design work, not just external repos). Note creation/supersession (the write side) stays agent-judgment-only, same as lessons — no hook authors note content; only recall and staleness-flagging are mechanical.

**Correction vs. the original design, made while implementing:** the original synthesis assumed recall had to be a `WORKFLOW.md` prose rule (inline agent judgment on every message), because no hook was believed able to see the user's message text or inject context mid-conversation beyond `SessionStart`. That assumption was wrong — checked directly against Claude Code's own hooks documentation before writing any code: `UserPromptSubmit` *can* return `hookSpecificOutput.additionalContext` on every single turn (input field is literally named `prompt`), and `PostToolUse` *can* return a flat top-level `additionalContext` after any tool call, including `Read`. Both are implemented as real hooks (`memory-recall.js`, `memory-architecture.js`) instead of a prose rule — recall for this store is now **mechanical, not agent-judgment**, closing the reliability gap ("agent happened to notice") more completely than the original synthesis thought was possible. The directory-grep fallback described below is now a true fallback (index/hook missed it), not the primary mechanism.

**The gap this closes:** none of checkpoints, lessons, or Zarak's separate native Claude Code auto-memory (typed `user`/`feedback`/`project`/`reference` files indexed in his own `MEMORY.md`) capture project *architecture* — the shape of a codebase, why a structural decision was made, a standing invariant — in a form that (a) survives past a checkpoint's trim window, (b) has a defined correction path as the real code changes instead of going stale silently, and (c) gets recalled in non-project/global scenarios via something more rigorous than an agent noticing a prose description was relevant.

**Why a new store, not an extension of #1/#2/#3:** checkpoints are *deliberately* trimmed (10 checkpoints/7 days project, last-session-only global — this file's "Two scopes" table above) — architecture facts must outlive that trim by design, so they structurally cannot live there. Lessons are *definitionally* corrections about agent behavior, and the write gate's first three tests (this file's "Two triggers" section above) require a triggering user-message to run against — a fact learned by reading code has no such message, so forcing it through would blur a gate tuned specifically to catch corrections. Zarak's native global auto-memory has no verified write contract a third-party hook can safely mutate (no confirmed guarantee against Claude Code's own memory management reading/writing concurrently) and no explicit keyword/tag field today — kept as an optional read-side pointer only (see "Cross-link," below), never the store. The new store reuses every existing mechanism verbatim (`resolveScope()`, `atomicWrite`/lock, `SessionStart` injection, byte-cap-with-loud-truncation, strikethrough supersession) — new content and a new directory, not new machinery.

### Schema

Sibling to `session/` and `lessons/` under the same `base` `resolveScope()` already returns (`_lib.js`'s `resolveScope`, confirmed lines 53-58):

```
<base>/architecture/
  index.md              # flat, one line per note, byte-capped injection (see Recall, below)
  watch-map.json         # sidecar: {"relative/path.ts": ["note-id-1", "note-id-2"]} — kept in
                          # sync whenever a note's watch_files changes, so the PostToolUse
                          # staleness hook does one O(1) lookup, never a directory scan
  notes/
    <id>.md              # one file per note
```

Note frontmatter + body:

```
# Architecture note
id: <short-kebab-slug, unique within scope>
scope: project | global
repo: <name or null>
project: <canonical project name, e.g. VenderScope, ContraAI, tender-review-assistant,
          claude-harness — REQUIRED even at scope:project, so global cross-project recall
          has a stable string independent of the local repo dirname>
component: <optional short label, e.g. auth, db-layer — organizing hint, not the recall field>
tags: <comma-separated literal keywords: codebase names, aliases, common misspellings — drawn
       from the codebase itself where possible, not invented vocabulary. The only field the
       recall rule matches against.>
watch_files:
  - <repo-relative path; editing this path mechanically flags this note possibly-stale>
created: <ISO8601>
updated: <ISO8601>
status: current | possibly-stale | superseded
index_line: <exact line injected: id | project | tags | one-line summary | path>

## Summary
<the structural fact / invariant / why-decision, 1-2 sentences>

## Detail
<fuller explanation, read on demand only — same injected-index/full-file-on-demand split as
lesson.md's index_line/## Incident>

## Verified against
<encouraged, not gating: file:line(s) or commit sha where this was confirmed true when
captured — gives a later session something concrete to spot-check instead of a disclaimer>

## Staleness check
<blank until PostToolUse flags it:>
<!-- possibly-stale-since: <ISO8601> — edited: <path> -->

## Superseded
<omitted unless invalidated. Identical discipline to lesson.md:17-20:>
<!-- superseded: <ISO8601> — reason -->
~~<original summary text>~~
```

### Write trigger

Content (`id`/`tags`/`project`/`Summary`/`Detail`) is agent-judgment only, inline at the moment — identical posture to why lessons are agent-judgment (no hook receives conversation content, so nothing but the agent's own reasoning can tell "architecture-worthy" from "routine"). Four pre-write gates, adapted from the lesson gate's shape but pointed at this content type:

1. **Differentiation test** — is this ACTIVITY (→ `checkpoint.md`) or a CORRECTION about agent behavior (→ a lesson)? Either → redirect, don't write here.
2. **Durability test** — will this still be true next month, not just this session.
3. **Duplicate check** — grep this scope's `architecture/index.md` before writing; if an existing note covers the same subsystem, supersede in place rather than duplicate.
4. **Tag-collision check** — grep the *global* index for a tag already claimed by a different `project` value; require disambiguation before writing. Without this gate, a near-duplicate tag (e.g. "postgres" loosely covering both VenderScope's and a future ContraAI project's Postgres setup) doesn't produce a missed recall — it produces a note read and answered from with full confidence, for the *wrong* project. This gate is agent-judgment, not hook-enforced; it catches exact-string collisions via grep but not near-duplicates or synonymous-but-differently-spelled tags — a residual risk, not a solved one.

**When a note lists `watch_files`, the agent must also add each path to `architecture/watch-map.json`** (`{"relative/path.ts": ["note-id", ...]}`) in the same write — this sidecar is not hook-maintained, nothing else keeps it in sync, and `memory-architecture.js` (below) silently finds nothing to flag if it's skipped. Same failure shape as the keyword-discipline risk already named in Risks: nothing mechanically enforces this either.

**Mechanical (`PostToolUse`, matcher `Read\|Edit\|Write`, implemented as `memory-architecture.js`) — staleness flagging AND file-touch recall, never content-authoring:** reads `watch-map.json`, string-matches `tool_input.file_path` (converted to repo-relative) against its keys — an O(1) lookup, not a per-edit scan of every note's `watch_files`, same hot-path constraint that already shaped why `goal`/`next`/`decisions` aren't auto-refreshed. On any matched `Read`/`Edit`/`Write`, injects the linked note's `## Summary` as context (see Recall, below). On `Edit`/`Write` specifically, additionally appends a `possibly-stale-since` HTML comment to each matched note via the existing `atomicWrite`/lock path and flips its `status` to `possibly-stale`, then prefixes its `architecture/index.md` line with `[STALE?]` (`lib.flagIndexLineStale`) so the flag is visible at the next ambient injection without a live status read.

### Recall (read trigger) — three layers, implemented

**Layer 1 — ambient index (`SessionStart`, `memory-init.js`).** Project scope: a fourth injection block, alongside the existing checkpoint/archive-index/lessons-index blocks, reads `<repo>/.claude/architecture/index.md` the same way the lessons index is read today — byte-capped at **8000 bytes**, matching `LESSONS_INDEX_CAP_BYTES`, same loud-truncation-note behavior on overflow. Global scope: same mechanism, one file (base already is the home dir), same 8000-byte cap since there's no split cost with a project index in this scope. `possibly-stale` entries are prefixed `[STALE?]` inline so distrust is visible without opening the file; `superseded` entries are never in `index.md` at all (see Retention, below), so they can't surface here. Project scope *also* injects the global `~/.claude/architecture/index.md` unconditionally — capped at a **smaller 2000 bytes**, not the 8000-byte project cap, because this one is paid every session regardless of whether the current task needs cross-project recall at all (worked example below). This layer gives ambient awareness of what exists; it does not by itself answer a question.

**Layer 2 — mechanical per-prompt recall (`UserPromptSubmit`, `memory-recall.js`, implemented).** On every single prompt, greps the raw message text against every pooled index entry's `tags`/`project` columns (project index + global index, both scopes — same pooling as Layer 1). On a match, reads the matched note(s) directly off disk and injects their full `## Summary`/`## Detail` content via `hookSpecificOutput.additionalContext` — not just the one-line index summary. Bounded to 3 notes per prompt. This is the mechanism that actually answers Zarak's original ask ("recall shouldn't depend on the agent happening to notice") — it is deterministic and hook-enforced, not agent-judgment.

**Layer 3 — mechanical file-touch recall (`PostToolUse`, matcher `Read\|Edit\|Write`, `memory-architecture.js`, implemented).** On every `Read`/`Edit`/`Write`, looks up the touched file's repo-relative path in `<repo>/.claude/architecture/watch-map.json`; on a match, injects the linked note's `## Summary` via a flat top-level `additionalContext` (PostToolUse's output shape — confirmed NOT nested under `hookSpecificOutput`, unlike Layers 1–2). This is the "touching a file surfaces its architecture note" behavior Zarak asked about directly — genuinely new versus the original synthesis, which had no mechanism for this at all (see the correction note above). Project scope only; `watch_files` are repo-relative and have no meaningful match without a repo.

**Fallback — agent judgment (`WORKFLOW.md`-level, not a hook), only reached when Layers 1–3 miss.** If none of the mechanical layers surfaced a plausible match (e.g. the user's phrasing shares no literal token with any `tags`/`project` value), fall back to grepping `architecture/notes/`'s frontmatter directly before concluding nothing exists — but **skip any note with `status: superseded`** in that fallback grep, the same way superseded entries are excluded from `index.md`, or a struck-through fact can still surface as a false-confident answer via the directory fallback alone. This is now a true fallback for the mechanical layers' blind spot (non-literal phrasing), not the primary recall path the original synthesis assumed it had to be.

**Token-cost worked example, at the caps above:** project index (8000 bytes) + global index (2000 bytes) adds up to ~10000 bytes (~2500 tokens, rough 4-chars/token estimate) to every `SessionStart` in project scope, on top of the checkpoint + archive index + existing 8000-byte lessons cap already injected today. `memory-recall.js`'s per-prompt matches add on top of that only when something actually matches (bounded to 3 notes). Actual injected size will be far under cap early on (few notes), so this is a worst-case ceiling, not a typical cost — but it's the number the "is this worth it" call in the open-questions round was actually about.

**WATCH — global-index injection cost, not yet a problem, named revisit trigger (same house style as this file's SQLite-FTS5 entry above):** revisit *whether* the global index should stay unconditional (vs. gated behind some cheaper heuristic) only if real cross-project note volume grows enough that the 2000-byte cap starts truncating regularly, or if the fixed per-session cost is reported as noticeable in sessions that never use cross-project recall. Not built as adaptive/conditional injection speculatively — that's the same YAGNI discipline this file already applies to SQLite-FTS5.

### Staleness — v1 only, v2 deferred

**v1 (this spec, build now):** the `watch_files` → `possibly-stale-since` mechanical flag described above, surfaced as `[STALE?]` at injection. On next contact with a flagged note, the agent resolves it — never a hook — by re-reading the current state of the watched file(s), then either clearing the flag (bump `updated`, drop the marker) if the fact still holds, or superseding it with the exact strikethrough + HTML-comment discipline lessons already use: never a silent overwrite, never a deletion.

**v2 (named, deferred, not built):** an optional `verify:` block (`method: file_exists | grep_count | glob_count | grep_absent`, `target`, `pattern`, `expect`) that would re-run automatically every `SessionStart` for claims that reduce to a mechanical check, flipping a `verified | drifted | unchecked` status with an appended history line — strictly stronger than v1's reactive flag (catches drift even when no edit touched a `watch_files` path), but requires building full recipe-execution machinery before any of this ships. **Revisit condition:** adopt v2 if v1's flag is repeatedly observed either firing without real signal (trips on every edit to a broad watched file, but the invariant never actually breaks) or missing real drift (the invariant breaks without any watched file changing) often enough in practice to justify the build. A shipped `verify:` recipe is also a known risk in its own right, not just an upgrade: a shallow grep/glob pattern can report `status: verified` while the actual invariant is violated through a path the pattern never anticipated (a renamed helper, a differently-aliased client) — a green check reads as *more* trustworthy than an unverified doc precisely because it looks actively checked, so nobody thinks to distrust it the way they would a stale doc with no verification story at all. Worth knowing before v2 is ever built, not just after.

### Retention

No time-based trim, no rotation code — disk size isn't the real cost here (notes are read on demand; they cost nothing sitting on disk). The actual risks are (a) a superseded note still matching a keyword grep → confidently wrong recall, and (b) index-line proliferation eating the byte cap → `tags` clauses get truncated off older entries, degrading recall. Both are closed by one rule, folded into the supersession action that already has to happen: **on supersession, remove the note's line from `index.md`; keep the `.md` file on disk forever** (git-diffable history, consistent with this file's existing supersession-not-deletion discipline for lessons). This is why the recall fallback above explicitly excludes `status: superseded` from the directory grep — removing the index line alone isn't sufficient once a fallback path exists that reads the directory directly.

### Cross-link to Zarak's native auto-memory

An architecture note may be pointed at from an existing entry in Zarak's global `MEMORY.md` (one extra line naming the note's id/path, using that system's own `[[name]]` cross-reference convention) — **agent-authored only, at note-creation time, through the same write path the agent already uses to edit `MEMORY.md` today.** Never written by `memory-checkpoint.js`, `memory-init.js`, or any other hook in this pack — that hook-mediated path is what carried the real risk (no verified guarantee against Claude Code's own memory management concurrently reading/rewriting that file), and this scopes the cross-link to avoid it entirely rather than skip the feature outright.

## Concurrency

Confirmed directly against Claude Code's own hooks docs: hook invocations for the same event run **in parallel**, and Anthropic's own docs acknowledge the resulting race explicitly (concurrent `PreToolUse` hooks returning `updatedInput` resolve non-deterministically — "last one to finish takes effect"). `PostToolUse` fires on every Edit/Write and could plausibly fire concurrently from parallel subagents touching the same repo. Two file types, two policies — this does not generalize into a broad concurrency framework:

- **Lessons index: append-only.** Hazard eliminated by construction — no read-modify-write ever happens, so no lock is needed (validated pattern, `AnastasiyaW/mclaude`, Windows-tested).
- **`checkpoint.md`: the one file with real read-modify-write risk.** Lockfile via `O_CREAT|O_EXCL` + a stale-lock timeout, wrapping a temp-file-then-atomic-replace write (same `mclaude` pattern).
- **Resolved:** the caveat this section originally raised was Git Bash `mv` behavior under contention on Windows, never independently verified. The shipped implementation sidesteps it rather than resolving it as originally framed — hooks run as native `node.exe`, not through Git Bash, so the write path is Node's `fs.renameSync` (Win32 `MoveFileExW`), not a shell `mv`. Verified empirically: 20 concurrent `node memory-checkpoint.js` processes racing the same lockfile + checkpoint file, repeated runs, valid output every time, no leftover lock or temp files. See `memory/hooks/_lib.js`'s `acquireLock`/`atomicWrite`.

## Implementation notes (vs. the pseudocode above)

`memory/hooks/*.js` follows this spec with two intentional, stated simplifications rather than silent scope-narrowing:

- `goal`/`next`/`decisions`/`blockers` are **not** auto-refreshed from "recent assistant intent" the way `maybeRefresh(cp.next, recentAssistantIntent)` above sketches — a `PostToolUse` hook only receives `tool_input`, not conversation content, and parsing the transcript on every single Edit/Write was judged too much risk on the hottest-path hook in this repo. The hook mechanically keeps `files` and `updated` fresh; the agent edits `goal`/`next`/`decisions`/`blockers` directly when something material changes.
- The lessons-index injection budget is a flat byte cap (8000 bytes, truncate-with-note past it), not the full priority-tiered scheme sketched in the Mistake-memory section below. Documented as a pragmatic first cut, not the final design.

## Security

- Checkpoints **never** store secret values, env var contents, or key material — only paths touched and "key X is set: yes/no." `memory-checkpoint.js` (pseudocode above) runs a secret-pattern strip before every write, same pattern set as `rules/security-invariants.md` Tier 0.
- Project checkpoints are gitignored via a template `.gitignore` snippet shipped by the installer (mirrors the existing `.cursor/session/.gitignore` already in this repo).
