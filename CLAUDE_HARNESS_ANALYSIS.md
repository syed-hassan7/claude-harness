# Claude Harness v5 — God-Prompt Analysis (Phases 0, 1, 5, 6, 9)

**Status:** Analysis only. No file in this repo has been deleted, moved, or edited to produce this document — everything below is new. Demolition/archival is a **separate, future implementation PR** requiring its own approval.

**Source directive:** `~/.cursor/plans/machina_god-prompt_2ec20c3e.plan.md` ("Claude Harness v5 — Strip the Harness, Ship the Stack").

---

## Executive summary

Claude Harness v4 ships as a mechanical harness: a 12-phase state machine, a ship/rigor dial, a 5-edit pass ceiling, phase-gated Edit/Write blocking, and verifier-artifact proof-of-work. The founder directive is explicit: this identity is wrong and should be **demolished, not simplified**. v5 repositions Claude Harness as a **portable skill + rules pack** — engineering discipline (Ponytail), design intelligence, automatic dual-scope memory, lightweight spec planning, and always-on security invariants — installable into Claude Code, Cursor, or Codex without a state machine.

**Verdict: no gaps large enough to require a god-prompt v4.** The v3 god-prompt's structure (Phases 0–9) is sound. The only correction needed is completeness of Phase 0's inventory — the source plan's demolition table (16 rows) missed ~19 real files in this repo, all still classifiable under the same DELETE/ARCHIVE/KEEP scheme with no new categories required. See §9 for the one-line addendum this produces; no v4 rewrite is warranted.

---

## §0 — Full inventory: every harness-adjacent file, classified

Legend: **DELETE** = safe to remove outright once v5 ships (no reference value). **ARCHIVE** = move to `archive/v4-harness/` (reference/history value, e.g. for the CHANGELOG or benchmark comparisons). **KEEP** = stays in place, unchanged, becomes part of v5.

### `.claude/hooks/` (2,229 lines total)

| Path | Lines | Classification | Reason |
|------|------:|----------------|--------|
| `harness-lib.js` | 905 | ARCHIVE | Core 12-phase state machine — the thing being demolished |
| `phase-gate.js` | 51 | ARCHIVE | Edit/Write blocker by phase |
| `pass-ceiling.js` | 70 | ARCHIVE | 5-edit blocker |
| `verifier-capture.js` | 143 | ARCHIVE | Writes `.machina/verifiers/*` proof artifacts |
| `machina-advance.js` | 48 | ARCHIVE | `/machina next` mechanical phase advance |
| `done-signal-guard.js` | 25 | ARCHIVE | Legacy v2.5 done-signal hook (already dead-hot-path per harness.md) |
| `mode-init.js` | 122 | ARCHIVE | Legacy v2.5 mode system |
| `harness-hook-utils.js` | 50 | **KEEP — corrected 2026-08-02** | Live global install (`~/.claude/hooks/`) traced directly: `secret-guard.js` (a KEEP hook) requires it for `readHookInput`/`block` — two generic, harness-agnostic Claude Code hook I/O helpers, not Claude Harness-specific logic despite the filename. Archiving it breaks secret-guard. Original ARCHIVE call assumed no live callers outside the harness; that assumption was wrong. |
| `harness-init.js` | 65 | ARCHIVE | SessionStart hook injecting phase/rigor state — replaced by v5's minimal `session-init.js` (injects AGENTS.md + security invariants only, no phase state) |
| `secret-guard.js` | 29 | **KEEP** | Mechanical secret-write blocker — explicitly retained by founder directive as the one hook that survives |

### `.claude/commands/` (Claude Harness slash commands)

| Path | Classification | Reason |
|------|----------------|--------|
| `machina-rigor.md`, `machina-ship.md`, `machina-status.md`, `machina-reset.md`, `machina-next.md`, `machina-rules.md`, `machina-ux.md`, `casual.md`, `project.md` | ARCHIVE | Rigor-dial / phase-advance UI — no dial in v5 |
| `security-review.md` | **KEEP** | Maps 1:1 to the `security-audit` skill already seeded in the v5 manifest (read-only pre-merge review, not phase-gated) |
| `security-spec.md` | **KEEP** | Maps 1:1 to the security-invariants workflow — writing a security spec is still good practice, it's just advisory now, not a mechanical gate blocker |

### `.claude/` — other

| Path | Classification | Reason |
|------|----------------|--------|
| `statusline.js`, `statusline.sh` | ARCHIVE | Renders phase/rigor/pass-ceiling state — nothing left to render once those concepts are gone. v5 may ship a much simpler statusline later (out of scope this doc) |
| `settings.example.json` | ARCHIVE | Wires `harness-init.js` + `secret-guard.js` + `phase-gate.js` + `pass-ceiling.js` + `verifier-capture.js` into hook events. v5 needs its own minimal settings example (secret-guard + memory hooks only) — new file, not a rewrite of this one |

### `scripts/` (12 harness-era scripts, 3,209 total lines across hooks+commands+scripts)

| Path | Lines | Classification | Reason |
|------|------:|----------------|--------|
| `harness-smoke-test.js` | 80 | ARCHIVE | v4 smoke test (named explicitly in source plan) |
| `test-harness.sh` | 135 | ARCHIVE | v4 acceptance tests, run by CI job `harness-test` (named explicitly in source plan) |
| `machina-report.sh` | 66 | ARCHIVE | Telemetry for harness state (named explicitly in source plan) |
| `detect-profile.sh` | 93 | ARCHIVE | lean/standard/full profile detection (named explicitly in source plan) |
| `global-setup.sh` | 152 | ARCHIVE | Installs harness hooks + `/machina` commands to `~/.claude/` — superseded by v5 `install.sh`/`install.ps1` |
| `bootstrap.sh` | 116 | ARCHIVE | Per-project `.machina/` scaffold — no `.machina/` in v5 |
| `profile-setup.sh` | 93 | ARCHIVE | Installs profile-gated tools (claude-mem, graphify, spec-kit) — v5 has no profile tiers; optional-tool install becomes part of `install.sh` |
| `update.sh` | 88 | ARCHIVE | Syncs installed harness files from repo — no harness files to sync |
| `migrate-v3.sh` | 60 | ARCHIVE | v2.5 → v3.1 one-time migration — historical, not reusable |
| `verify.sh` | 111 | ARCHIVE | "Fail-loud preflight" — checks harness scaffold integrity; concept may return in v5 `install.sh --verify` but this implementation is harness-specific |
| `audit-configs.sh` | 57 | ARCHIVE | Read-only audit of `~/.claude` configs — harness-shaped, not reusable as-is |
| `check-pins.sh` | 28 | ARCHIVE | PINNED vs LATEST for harness-managed deps |
| `install-cursor.sh` | 113 | ARCHIVE | Cursor v2.5 integration — already "parked" per harness.md; v5 replaces with `adapters/cursor/` |
| `wire-settings.js` | 133 | ARCHIVE | Injects harness hook config into `settings.json` — the mechanism that makes `settings.example.json` load-bearing. Removing hooks without retiring this script leaves a dangling wiring path; must be archived together with `settings.example.json` |
| `dependency-pins.sh` | 12 | ARCHIVE | Small helper for `check-pins.sh` |
| `harness-init-project.sh` | 30 | ARCHIVE | Per-project harness init helper |
| `check-spec-security.sh` | 36 | **ARCHIVE (needs CI rework, see §5)** | Called directly by `.github/workflows/ci.yml` → `security` job as the "Spec abuse-cases gate." This is a **live CI dependency**, not dead code — archiving it without editing `ci.yml` breaks CI. Flagged for the migration plan, not silently dropped. |

### `templates/`

| Path | Classification | Reason |
|------|----------------|--------|
| `templates/machina/state.json` | ARCHIVE | Named explicitly in source plan |
| `templates/machina/global-state.json` | ARCHIVE | Same concept, global-scope variant — **missed by source plan's table** |
| `templates/machina/harness.yaml` | ARCHIVE | Phase/rigor config template — **missed by source plan's table** |
| `templates/cursor/.cursor/hooks/*` | ARCHIVE | Named explicitly in source plan ("Mechanical Cursor harness") |
| `templates/cursor/.machina/` | ARCHIVE | Cursor-side `.machina` scaffold mirror |
| `templates/cursor/README.md` | ARCHIVE or rewrite | Documents the parked v2.5 Cursor integration; v5's `adapters/cursor/README.md` replaces it |

### Root-level files

| Path | Classification | Reason |
|------|----------------|--------|
| `harness.md` | ARCHIVE | Full v4 harness spec — replaced by `WORKFLOW.md` per source plan |
| `rules.md` | ARCHIVE | Legacy-alias copy of harness.md (its own header says "legacy alias — canonical: harness.md") |
| `orchestrator_config.yaml` | ARCHIVE | `harness_phases` (12-phase list), `profiles` (lean/standard/full + tool gating), `spec_kit_sequence` tied to phase names — all demolished concepts. Its `ci_gates.required` list (npm test/typecheck/lint/build) is generic and worth preserving as prose in `WORKFLOW.md`, not as this YAML |
| `AGENTS.md` | **REWRITE (not this session)** | Currently describes v4 profile/rigor dial as the cross-agent entry point. Becomes the v5 universal entrypoint per source plan's target tree — scoped to the *next* implementation session, left untouched now |
| `AGENT_INSTRUCTIONS.md` | **REWRITE (not this session)** | Same reasoning — full of Tier A/B hook-enforcement language tied to phase-gate.js |
| `README.md` | **REWRITE (not this session)** | Markets "Claude Code loop harness — mechanically enforced engineering discipline"; needs the "curated agent workflow stack" pitch from source plan §Expected outcomes |
| `CLAUDE.md` (repo root) | **REWRITE (not this session)** | Session bootstrap pointer into `AGENT_INSTRUCTIONS.md`/harness state — needs updating once those are rewritten |
| `Makefile` | **REWORK (not this session, flagged here)** | Every target (`global-setup`, `bootstrap`, `profile-setup`, `harness-test`, `smoke-test`, `check-pins`, `cursor-install`) invokes an ARCHIVE-classified script. v5's Makefile likely reduces to `install`, `verify` (CI-shaped, not harness-shaped), and `report` (if telemetry survives in any form) — **not addressed in this document beyond flagging it; do not delete this session** |
| `.github/workflows/ci.yml` | **KEEP, with one required edit (not this session)** | `secret-scan` and `verify` jobs and the SAST/dependency-audit steps in `security` are repo-hygiene, not harness — keep as-is. The `harness-test` job (runs `scripts/test-harness.sh`) must be removed once that script is archived. The `security` job's "Spec abuse-cases gate" step (runs `scripts/check-spec-security.sh`) must be removed or replaced — both are **future-PR edits**, not this session's |
| `.pre-commit-config.yaml` | **KEEP unchanged** | gitleaks, trailing-whitespace, conventional-commit hooks — pure repo hygiene, no harness coupling |
| `.semgrepignore` | **KEEP unchanged** | SAST exclusions, no harness coupling |
| `benchmarks/README.md` | **KEEP as reference** | "Vanilla vs Claude Harness rigor" methodology — useful historical/marketing artifact once rigor is gone; no code dependency, low cost to keep as-is |
| `.cursor/session/checkpoint.md`, `.gitignore`, `hook-audit.log` | **KEEP, unrelated to harness** | This is Cursor's *own* existing session-memory pattern (not part of the v4 Claude Harness harness) — it is the direct ground-truth reference for the memory-layer design in §Memory below. Untracked (`?? .cursor/` in git status) — left alone |

**Total harness-only surface identified:** 10 hooks + 9 commands (7 archive / 2 keep) + 16 scripts + 6 template paths + 5 root docs (3 archive, 3 rewrite-later) = **~40 files**, vs. the source plan's original 16-row table. Nothing found required a category beyond DELETE/ARCHIVE/KEEP/REWRITE-later.

---

## §1 — Gap analysis

| Dimension | v4 state | v5 target | Gap / risk |
|-----------|----------|-----------|------------|
| **Engineering** | Mechanical TDD (red/green phase-gated), pass ceiling, surgical-changes as Tier C advisory | Ponytail core (YAGNI ladder) + advisory TDD via superpowers skill | Low risk — Ponytail's actual shipped content is unverified pending `skills/RESEARCH.md` (see §7-note below); do not mark `required: true` until confirmed |
| **Design** | Not addressed by v4 at all (no design lane existed) | `ui-ux-pro-max` (already installed as a Claude Code skill in this environment) + anti-slop MCP sequence | This is a net-new capability, not a migration — low risk, mostly documentation |
| **Memory** | claude-mem/graphify optional, full-profile-only, manual start, "v4 abandoned it" per harness.md §7 | Automatic dual-scope file-based hooks (project vs. global), zero manual `/compact` | Medium risk — the "context ~50%" auto-compact trigger from the source plan needs verification against real Claude Code hook events (see `memory/SPEC.md` §Hook events) |
| **Spec/planning** | spec-kit mandatory in rigor mode (`speckit_specify` phase blocks impl) | Lightweight, optional; spec-kit only for large features | Low risk — mechanical gate removal is a subtraction, not a redesign |
| **Security** | Tier A/B/C enforcement taxonomy, phase-gated security spec, secret-guard hook | Always-on invariants (rules, not phases) + secret-guard hook retained | Low risk — secret-guard.js is untouched; the taxonomy language is removed, substance (never read/commit secrets, scoped DB queries, 404-not-403, rate limiting) carries forward into `rules/security-invariants.md` |
| **Portability** | Claude Code primary, Cursor "parked at v2.5", Codex unaddressed | Claude Code primary, Cursor via copied rules/skills, Codex via `AGENTS.md` | Medium — Codex adapter is genuinely new work, no existing v4 equivalent to migrate from |
| **DX (install/update)** | 4-step Makefile flow (`global-setup` → `bootstrap` → `profile-setup` → `verify`), profile auto-detection | `install.sh`/`install.ps1`, ≤5 steps per adapter | Medium — `wire-settings.js` (133 lines) currently does real work (merges hook config into `settings.json`); v5's installer needs an equivalent for the 1 surviving hook (secret-guard) + new memory hooks, not a line-for-line port |

---

## §5 — Migration / demolition plan (ordered, for the future implementation PR — not this session)

1. Land this session's deliverables (`rules/`, `skills/`, `memory/`, `WORKFLOW.md`) alongside v4, unreferenced by any hook or command yet — pure addition, CI stays green because nothing existing changed.
2. Rewrite `AGENTS.md`, `AGENT_INSTRUCTIONS.md`, `README.md`, `CLAUDE.md` to point at the new v5 docs instead of `harness.md`.
3. Write `adapters/claude/settings.example.json` (secret-guard + memory hooks only) and a new minimal `install.sh`/`install.ps1`; do **not** delete the old `settings.example.json`/`wire-settings.js` until the new installer is verified working.
4. Edit `.github/workflows/ci.yml`: remove the `harness-test` job; remove or replace the "Spec abuse-cases gate" step in `security` job (decide: drop entirely, or repoint at an advisory, non-blocking check).
5. Move all ARCHIVE-classified files (§0 tables) to `archive/v4-harness/`, preserving directory shape, in one commit.
6. Delete now-dangling references: `Makefile` targets that pointed only at archived scripts (`global-setup`, `bootstrap`, `profile-setup`, `harness-test`, `smoke-test`, `check-pins`, `cursor-install`) either get archived-script-path updates (`archive/v4-harness/scripts/...`) or are dropped if the new installer replaces them.
7. Run `make ci-local` (or the CI workflow directly) to confirm nothing dangles.
8. Tag `CHANGELOG.md` entry — see below.

### CHANGELOG v5.0.0 (breaking) — draft entry

```markdown
## v5.0.0 — Skill pack, not harness (BREAKING)

Claude Harness is no longer a mechanically-enforced loop harness. The 12-phase state
machine, ship/rigor dial, 5-edit pass ceiling, phase-gated Edit/Write blocking,
and verifier-artifact proof-of-work are removed. `.machina/` no longer exists
as a per-project scaffold; `/machina *` commands are gone except the two that
mapped to still-useful skills (`/security-review`, `/security-spec`, now
advisory, not gate-blocking).

Claude Harness v5 is a portable pack of skills, always-on security rules, and
automatic dual-scope memory hooks — install via `install.sh`/`install.ps1`
into Claude Code, Cursor, or Codex. See `WORKFLOW.md` for the new
Understand → Plan → Build → Verify loop (no mechanical gates).

**Breaking:** if you depended on `/machina rigor`'s phase gates blocking
premature implementation, that enforcement is gone. TDD, spec-first design,
and UX review are now skill-triggered and advisory, not hook-blocked.

**Migration:** archived harness code lives in `archive/v4-harness/` for
reference. Re-run the installer; existing `.machina/` directories can be
deleted from projects that adopt v5.
```

---

## §6 — First-PR scope (the actual demolition, separate approval required)

Per source plan's "First implementation PR" list, adjusted for the gaps found here:

1. `archive/v4-harness/` — move all ARCHIVE-classified files from §0 (≈37 files, not 16)
2. `rules/security-invariants.md` (this session's deliverable, already landed)
3. `skills/manifest.yaml` + `skills/RESEARCH.md` (this session's deliverable)
4. `memory/SPEC.md` + `memory/templates/checkpoint.md` (this session's deliverable)
5. `memory/hooks/` — actual working `memory-init.js`, `memory-checkpoint.js`, `memory-compact.js`/`memory-flush.js` (this session ships **pseudocode only** in SPEC.md; working code is next-PR)
6. `AGENTS.md`, `AGENT_INSTRUCTIONS.md`, `README.md`, `CLAUDE.md` rewrites
7. `adapters/claude/settings.example.json` (new, minimal) + `scripts/install.sh` + `install.ps1`
8. `.github/workflows/ci.yml` edit (remove `harness-test` job, rework spec-security step)
9. `Makefile` rework (new targets pointing at `install.sh`, not archived scripts)
10. `CHANGELOG.md` v5.0.0 entry (draft above)
11. Move the 6 template paths (§0) into `archive/v4-harness/templates/`

**File count estimate: ~45–50 touched (mostly moves), not the ≤15 the source plan's "First PR scope" (Phase 6) originally estimated** — because that estimate only counted new files, not the archival moves. Flag this to the user before that PR starts.

---

## §9 — God-Prompt v4 verdict

**Not needed.** The v3 god-prompt's phase structure, locked decisions, and anti-patterns all held up under execution. The single correction this session produced — Phase 0's inventory undercounting real files by roughly 2.5x — is a **completeness fix to this document**, not a structural flaw in the god-prompt's design. Recommend: fold the full §0 table above into the source plan file (`~/.cursor/plans/machina_god-prompt_2ec20c3e.plan.md`) as its authoritative demolition list, superseding the original 16-row table, rather than issuing a v4 prompt.
