# Security spec — opt-in audit-log hook (data-access logging for GRC/compliance)

**Status:** spec only, no implementation yet. Revised after an adversarial advisor pass found several holes in the first draft — this version supersedes it. Written in response to moi.computer's creator correctly redirecting an audit-log feature request: "this sounds more like something the harness must be responsible for. moi is just a layer on top of existing harnesses." **Separately decided (2026-08-11): moi itself is rejected for adoption into claude-harness** — Elastic-2.0 license, requires a persistent background daemon, registers its own `.githooks`, 63 stars/no independent coverage. This spec is not about adopting moi; it stands on its own as a general compliance-evidence capability for any external-data-touching tool call the agent makes. Revisit moi once it matures.

This spec treats the deliverable as a **compliance-evidence artifact**, not a generic feature — the threat model centers on what a GRC/SOC2 reviewer would actually ask of this file (completeness boundary, integrity claims, retention, PII exposure), not generic hook-security concerns.

## Scope

New opt-in `PostToolUse` hook that appends a coarse record of external-data-source access (Bash, WebFetch, MCP tool calls) to a local, per-scope, append-only JSONL file. Observational only — never blocks, never gates, matches this repo's "no mechanical gates" premise (`WORKFLOW.md`; `skills/manifest.yaml` rejected `semgrep-guardian` specifically for being a `PreToolUse` blocking hook — this feature must not repeat that mistake in a different guise).

Files expected to change/add:
- New `audit-log/audit-log.js` — the hook itself.
- New `audit-log/test/run.sh` — test suite, same rigor tier as `memory/hooks/test/run.sh`.
- `install.sh` — new `--with-audit-log` flag, following the exact print-only pattern already used for `--with-memory-hooks` (verified directly in `install.sh`'s source: it never auto-edits `settings.json` for any feature — checks for an existing marker, prints a snippet to merge in manually otherwise).
- `.github/workflows/test.yml` — one new `run:` step in the existing matrix job.
- No changes to `memory/` or `caveman/` code paths. Pure addition. Reuses `memory/hooks/_lib.js` via relative `require()` (`resolveScope`, `stripSecrets`, `nowISO`, `ensureDir`, `ensureGitignore`) rather than forking it — `install.sh` already syncs the full pack tree regardless of which flags were passed, so the file is present on disk either way.

**Explicit non-goals (stated here, not buried — overclaiming here is the most damaging failure mode this spec exists to prevent):**
1. Does **not** capture access performed by child processes the agent launches. `Bash: <tool> start` is logged as one event; anything that tool itself subsequently reads from an external system is invisible to this hook. This is the literal boundary of "the harness" — say so plainly rather than let a reader assume broader coverage. (This is exactly the boundary that made moi un-fixable by this hook — see Status above.)
2. This is a **supporting access log, not a tamper-evident audit trail.** Local, gitignored, user-editable, unsigned JSONL. No signing, no write-once storage, no remote append target in v1.
3. **Bash coverage is best-effort classification, not reliable capture.** Logging only the first token of a Bash command (see Inputs/outputs below) tells you *a shell command ran*, roughly what kind — it does not reliably tell you *what* was accessed, and it is easy to defeat unintentionally (`env FOO=bar psql`, `sudo`, `bash -lc "…"`, pipelines, `&&` chains all shift or hide the meaningful token). **WebFetch and MCP logging are the load-bearing signal in this design** — they capture host/identifier reliably because those tools' calling convention is structured, not free text. Do not present Bash coverage as equivalent evidence quality in any consuming report.
4. **Hooks fire inside subagents too** (confirmed against Claude Code's own hooks docs). A single user-visible action that fans out into N subagent tool calls produces N log lines, not one. "One line per external call" is accurate; "one line per user-visible action" is not — don't imply the latter in dogfood checks or documentation.

## Assets

- The audit log file itself — a metadata inventory of which external systems the agent touched. Sensitive in aggregate even though individual lines are coarse; treat the file with the same care as an access log for the systems it describes.
- Session/scope identifiers (`session_id`, `scope`, `repo`) — low sensitivity, same class already handled by the memory checkpoint system.
- Indirectly: whatever secrets/PII would leak into logged fields **if the design is wrong** — command arguments, URL query strings/userinfo, MCP call parameters. Closing this is the central purpose of this spec.
- Availability of the primary agent loop — the hook must never degrade or block a real Bash/WebFetch/MCP call. Never-block is itself a protected asset here, not just a nice-to-have.

## Trust boundaries

- **Agent process (Claude Code):** trusted code, but `tool_input` content is not trusted data — it can contain anything the agent constructed, including secrets or PII a user pasted earlier in the conversation. Treat every field of the hook's stdin payload as untrusted.
- **Filesystem:** JSONL file lives under the existing dual-scope session dir (`<repo>/.claude/session/` or `~/.claude/session/`), gitignored, local disk only. No network transmission — this feature does not send data anywhere.
- **No third parties.** 100% local file write.
- **Human/compliance-tooling reader (`jq` over JSONL):** trusted consumer, but must be able to trust the file's *completeness claims* without extra context — hence the non-goals above ship as a header comment in the file/hook, not only in this spec.
- **Child processes the agent launches:** explicitly **outside** this trust boundary. Their own I/O is structurally invisible to a `PostToolUse` hook.
- **Subagents:** explicitly **inside** this trust boundary — hooks fire for their tool calls too, per Claude Code's docs. Don't conflate "subagent" (covered) with "child process" (not covered) — they are different things this spec must not blur.

## Authn/authz

No multiuser system, no session-ownership model to enforce — this is a local single-user hook. Scope resolution (`resolveScope()`) determines project-vs-global log location using the same git-root-walk trust model already shipped and tested for memory hooks (capped at the home directory, so a git-tracked dotfiles home doesn't collapse global scope into project scope — `memory/hooks/_lib.js`'s `walkForGitRoot`).

## Inputs and outputs

- **Input:** Claude Code `PostToolUse` hook JSON on stdin. **Structural field allowlist — this is a testable invariant, not a convention:** the hook reads only `tool_name`, `session_id`, `cwd` from the top-level payload, plus derives exactly one target field per the tool-specific rule below. It must never read `tool_response` and must never read any part of `tool_input` other than the single field each derivation rule names. Malformed/missing stdin handled the same way `_lib.js`'s `readHookInput()` already does — try/catch, empty-object fallback, never throws.
- **Output:** one JSON line appended to `<scope>/.claude/session/audit-YYYY-MM.jsonl` — the month is part of the filename, derived from the current write's timestamp. This *is* the rotation mechanism: a new month's writes go to a new file automatically, no read-modify-move, no coordination between concurrent writers, and no-auto-delete is satisfied by construction (nothing ever touches last month's file again). No separate "rotation policy" is needed beyond this filename rule.
- **Matcher — anchored, allowlist, not all-tools:** `^(Bash|WebFetch)$|^mcp__.*$`. Confirmed live against Claude Code's hook docs: `PostToolUse` fires for MCP tool calls, and matcher regex genuinely supports patterns like `mcp__.*__write.*`. **Anchoring is a defensive default, not a confirmed requirement** — the docs did not settle whether an unanchored `Bash` would also substring-match a hypothetical `BashOutput`-style tool name; anchoring costs nothing and removes the question. Confirm with a live dogfood check during implementation before shipping.
- **Field-level output policy per tool — this is the actual security control, not `stripSecrets()` alone:**
  - `Bash` → log only the first whitespace-separated token (binary name, e.g. `psql`, `curl`, `aws`), explicitly labeled as best-effort classification per the non-goals above. **Never log arguments** — that is where PII/secrets live in practice, and omitting them entirely is stronger than pattern-matching them out after the fact.
  - `WebFetch` → log URL **origin only** (scheme + host). Strip userinfo (`user:pass@`), path, and query string unconditionally before writing — a query string or basic-auth URL is exactly where customer IDs/PII/credentials appear.
  - `mcp__<server>__<tool>` → log the tool identifier only. **Never log call arguments or any tool response content** — enforced by the structural allowlist above, not just this per-tool rule.
  - `stripSecrets()` still applied to whatever coarse fields are logged, as defense-in-depth (e.g. a URL host that somehow embeds a token) — belt-and-suspenders, not the primary control.
- **Timeout:** hook wiring carries `"timeout": 5`, matching the existing `memory-checkpoint.js` snippet in `install.sh` — a hung node spawn is a real never-block risk on Windows specifically, and the existing memory hook already accounts for it; this one must too.
- **Path constraints:** log path is derived purely from `resolveScope()` plus the current write's own timestamp for the month segment. No user-controlled or tool-controlled path is ever accepted as a destination.
- No upload/download surface — this feature never transmits data off the machine.

## Secrets and config

- No new required env vars. One optional install-time flag: `--with-audit-log`, default off (mirrors `--with-memory-hooks`'s default-off precedent and the "never install/wire without an explicit request" rule in `rules/security-invariants.md`).
- **Logging exclusions (explicit, not implicit):** never log `tool_input` verbatim, never log `tool_response` at all, never log full Bash commands, full URLs, MCP call arguments, or file contents. Only: tool name, coarse target (per the field-level policy above), timestamp, `session_id`, `scope`, `repo`.
- Checkpoint-system precedent reused directly: same "never persist secret values, only descriptors" principle already stated for `memory-checkpoint.js` in `rules/security-invariants.md`'s enforcement model.

## Dependencies and supply chain

Zero new dependencies. Pure Node stdlib, reuses existing `memory/hooks/_lib.js`. No new install scripts beyond the existing `install.sh` pattern. Nothing to pin.

## Abuse cases

1. **Bash argument PII** (`psql -c "...email=..."`) — mitigated structurally: arguments are never logged, only the binary name (and that's explicitly labeled best-effort, not a completeness claim).
2. **WebFetch URL with PII/credentials in query string or userinfo** (`https://user:pass@host/api?ssn=...`) — mitigated: origin-only logging, userinfo/path/query stripped unconditionally before write.
3. **MCP call parameters containing customer records** (e.g. a Postgres-MCP query embedding row data) — mitigated: only `mcp__server__tool` identifier logged; the structural field allowlist makes reading call arguments or results a code-level impossibility, not just a documented rule.
4. **False compliance guarantee** — someone points an auditor at this file claiming full system audit coverage, when it only covers agent-initiated tool calls, not child-process I/O or human-initiated access. Mitigated by shipping the non-goal statements as a header comment in the file/hook itself, not only in this spec.
5. **Silent evidence destruction via a future "cleanup"** — a contributor later ports `checkpoint.md`'s 10/7-day trim onto this file "for consistency," destroying compliance evidence. Mitigated structurally, not just by policy: the date-derived filename means there is no "current file" to trim in place — each month is its own immutable-by-design file, so a trim would have to explicitly delete a whole past month's file, a much louder and more deliberate act than editing a rotation threshold.
6. **Log tampering** — local user or malicious code with filesystem access edits/deletes entries to hide evidence. Not mitigated in v1 — explicitly out of scope (access log, not tamper-evident trail).
7. **Hook breaks the real tool call** — a bug in `audit-log.js` throws, hangs, or fails to write. Mitigated: entire hook body wrapped in try/catch, always exits 0, single `fs.appendFileSync` write (no lock, no read-modify-write, sub-millisecond), 5s timeout as a backstop in the hook wiring itself.

## Required security tests/gates

- Unit: correct coarse-target extraction per tool type (Bash binary-name-only, WebFetch origin-only with userinfo/path/query stripped, MCP identifier passthrough).
- **Structural invariant test:** assert the hook's source never references `tool_response` and never indexes into `tool_input` outside the one derivation per tool — this should be checkable by direct inspection/grep of the hook file, not just by behavioral testing.
- Negative test: a fake secret/PII string placed in `tool_input` arguments never appears anywhere in the written JSONL line.
- Fault injection: malformed/empty stdin, and a simulated write failure (e.g. read-only target dir) — hook still exits 0, no crash, no partial/corrupt line.
- Concurrency smoke test: N concurrent invocations append exactly N valid, non-interleaved JSON lines to the same month's file.
- Matcher dogfood check: confirm live that a `BashOutput`-style or other near-name tool does not spuriously match the anchored `Bash` pattern.
- CI wiring: new `run:` step added to `.github/workflows/test.yml`'s existing matrix job (windows-latest/macos-latest/ubuntu-latest). Written to avoid the four landmines this repo's own last five commits already paid for: no `touch -d` relative/GNU-only dates, no assumption `jq` exists as a copyable binary, no hardcoded `PATH=/usr/bin:/bin`, no `find` under `set -e`.
- Manual/dogfood check after install: run one real Bash command, one real WebFetch call, and (if available) one real MCP tool call — confirm one coarse-target JSONL line per call, confirm no argument/query/response content appears anywhere in the file, and confirm a subagent-issued call also produces its own line.

## Open questions

None rise to a HALT-worthy blocker:

1. **Correlation hash** (a hash of the full raw command/URL for cross-referencing without storing the PII itself) — deferred out of v1 per YAGNI; revisit only if a real compliance workflow later needs it.
2. **File provenance** (adding `Read|Write|Edit` to the matcher) — deferred; no external-access use case has asked for it yet, and adding it would reopen the "does this need to exist" question for a different asset class.
3. **Repo layout/ceremony level** — resolved: single `audit-log/` directory (this spec + `audit-log.js` + `test/run.sh`), no separate design-spec doc beyond this file.

Security spec ready: `C:\Users\SyedHassan\OneDrive - thrivelearning.com\Documents\claude-harness\audit-log\SECURITY_SPEC.md`
