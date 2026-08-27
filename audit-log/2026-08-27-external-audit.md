# Claude Harness — adversarial standalone audit

**Date:** 2026-08-27
**Auditor context:** fresh Claude Code session, cwd `C:\Users\SyedHassan` (no git repo), no project loaded, no prior knowledge of the pack.
**Installed pack version:** `skills/manifest.yaml` `version: "6.2.0"`; install source per `CLAUDE.md` pointer block `d756c48-dirty`.
**Node:** v24.14.0. **Repo of record:** https://github.com/syed-hassan7/claude-harness (not cloned in this session — all findings are against the *installed* copy at `~/.claude/claude-harness`).

> **Provenance note (added 2026-08-27, same day):** copied into the repo from a scratch session's temp directory so it survives past that session's lifetime — the original session's scratchpad path is not readable from other sessions. Findings #7, #9, #11, #12 were fixed same-day in commit `1dfa5d2` (see `CHANGELOG.md`'s 6.4.0 entry); #12 turned out to already be documented and accepted in `skills/manifest.yaml`'s `known_issues`, re-verified rather than re-fixed. The fixes for #7 and #9 each went through two further review rounds that found real bugs in the fixes themselves — see the 6.4.0 CHANGELOG entry for the full sequence. This file is kept as the original, unedited findings record; do not hand-edit it to reflect fix status — that belongs in CHANGELOG.md and memory, not here.

## Method / epistemic note

Two classes of evidence are kept strictly separate throughout:

- **Hook-observable** — a file on disk, an exit code, stdout, an `additionalContext` block, a `Skill` tool result. Verifiable.
- **Self-graded prose** — canary name-drops, caveman terseness, "did I follow the YAGNI ladder." Because the auditor read `WORKFLOW.md` and `rules/*.md` before probing, the auditor's own prose cannot distinguish "the rule loaded and was followed" from "the auditor read the file and imitated it." These are marked **UNVERIFIABLE-BY-CONSTRUCTION**, not pass.

Severity vocabulary: `broken` / `degraded` / `cosmetic` / `working-as-documented` / `unverifiable`.

## Finding index

| # | Title | Severity | Category |
|---|---|---|---|
| 1 | SessionStart banner fires in bare terminal | working-as-documented | session-init |
| 2 | Injected checkpoint has empty `goal:` and `repo:` | degraded | memory |
| 3 | Live checkpoint absent; only archive survives | working-as-documented | memory |
| 4 | Global vs project scope resolves and isolates correctly | working-as-documented | scope |
| 5 | Hook scope follows Bash-tool cwd, not session cwd | degraded | scope |
| 6 | All 12 hooks fail open on malformed/empty/missing input | working-as-documented | robustness |
| 7 | **`review-gate-check.js` is a dead gate — pre-satisfied by Claude Code's own agent listing** | **broken** | gate |
| 8 | `design-lane-gate-check.js` fires correctly end-to-end | working-as-documented | gate |
| 9 | **`caveman-mode-tracker.js` silently disables caveman on any mention of "stop caveman"/"normal mode"** | **broken** | caveman |
| 10 | Caveman statusline badge consequently absent all session | degraded | statusline |
| 11 | `required: true` skill `ponytail` is not installed at all | broken | manifest-vs-reality |
| 12 | `visual-plan-local` and `onboarding` skills are not registered/callable | broken | manifest-vs-reality |
| 13 | `superpowers` TDD skill referenced by WORKFLOW.md is unavailable | degraded | manifest-vs-reality |
| 14 | `anti-slop` — named inside a "hard gate" — is not installed | degraded | manifest-vs-reality |
| 15 | `onboarding/verify.js` reports all-green while #11–#14 are true | degraded | verification |
| 16 | Statusline renders, numbers are live, jq fallback works | working-as-documented | statusline |
| 17 | Statusline `extra` row prints an empty `$0.00/$0.00` meter; `currency: GBP` ignored | cosmetic | statusline |
| 18 | Self-test suite: 71/71 pass, but zero caveman coverage and no test for #7 | degraded | test-coverage |
| 19 | Undocumented third-party hook (`impeccable@1`) fires on Write | cosmetic | config-drift |
| 20 | `claude-mem` installed and touched today despite "opt-in only, never default" | cosmetic | manifest-vs-reality |
| 21 | Hooks accept `session_id`-less input and write an `"unknown"` bucket | cosmetic | robustness |
| 22 | Env `gitStatus` claims a repo where `git rev-parse` says none | cosmetic | harness-external |
| 23 | Drift canary — mechanism live, substance unverifiable | unverifiable | canary |
| 24 | 33 hard/always/mandatory claims in rules; most have no hook backing | unverifiable | probe-8 |
| 25 | WORKFLOW.md "HTML out" default vs user's markdown ask | cosmetic | doc-conflict |
| 26 | `secret-guard.js` fires correctly (blocked this document mid-write) — *written up inside #24* | working-as-documented | security |
| 27 | Caveman kill phrase hit a user prompt in 6 of 20 local sessions — *written up inside #9* | broken | caveman |

---

## 1. SessionStart banner fires in a bare terminal — working-as-documented

**Tried:** Nothing — read the verbatim SessionStart output already present in this session's transcript, in a plain terminal, cwd `C:\Users\SyedHassan`, no git repo, no project.

**Happened:** Both wired SessionStart hooks fired. `caveman-activate.js` emitted:

```
SessionStart:startup hook success: CAVEMAN MODE ACTIVE — level: ultra
```

followed by the full SKILL.md-derived ruleset filtered to the `ultra` row only (intensity table contained only the `**ultra**` row; examples contained only `- ultra:` lines) — i.e. the filtering logic at `caveman-activate.js:72-94` demonstrably ran, not the hardcoded fallback at `:100-115`.

`memory-init.js` emitted four blocks: `## Claude Harness — previous session checkpoint`, `## Claude Harness — archive index` (4 entries), `## Claude Harness — lessons index` (3 lessons), `## Claude Harness — lesson promotion review`. No drift-canary rollup block — correct, `memory-init.js:174-188` only emits it when an entry has `pending` truthy, and none did.

Matches CLAUDE.md's pointer-block claims. **Severity:** working-as-documented. **Category:** session-init.

## 2. Injected checkpoint has empty `goal:` and `repo:` — degraded

**Tried:** Read the injected `## Claude Harness — previous session checkpoint` block.

**Happened:**

```
# Session checkpoint
scope: global
repo:
session_id: 2db2e3ee-c499-47e0-8dde-4d265f91747d
updated: 2026-08-26T20:00:26.122Z
goal:
files:
  - C:\Users\SyedHassan\...\Breaker-Breaker-Visual-Note.html
  - C:\Users\SyedHassan\...\Breaker-Breaker-Spec.html
```

`goal:` empty. This is exactly the failure mode `WORKFLOW.md:36` predicts in its own text ("global scope … is where it gets skipped, leaving the next session's injected checkpoint too thin to answer 'what were we doing'"). The doc predicts it; the live artifact confirms it. `_lib.js:6-12` states plainly that `goal`/`next`/`decisions`/`blockers` are never hook-written — so the only enforcement is agent discipline, and it did not hold in the previous real session.

**Severity:** degraded (the injected block costs context and delivers only two filenames). **Category:** memory.

## 3. Live checkpoint absent; only the archive survives — working-as-documented

**Tried:** `ls -la ~/.claude/session/`

**Happened:**

```
drwxr-xr-x ... archive
```

No `checkpoint.md`. Per `memory-init.js:44-60`, global scope rotates a checkpoint whose `session_id` differs from the current one: copy to `archive/<ts>.md`, then `unlink`. Archive listing confirms `2026-08-27T09-04-03-215Z.md` was created at this session's start. Rotation worked as designed; a fresh checkpoint is only created on the first `PostToolUse` write.

**Severity:** working-as-documented. **Category:** memory.

## 4. Global vs project scope resolves and isolates correctly — working-as-documented

**Tried:** Created `…/scratchpad/throwaway`, `git init -q`. Then invoked the same hook binaries with two synthetic `cwd` values.

```bash
printf '%s' "{\"session_id\":\"scope-probe\",\"cwd\":\"$REPO\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$REPO/App.tsx\",\"content\":\"<select><option>a</option></select>\"}}" | node design-lane-gate-check.js
printf '%s' "{\"session_id\":\"scope-probe\",\"cwd\":\"$REPO\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m wip\"}}" | node design-lane-gate-check.js
printf '%s' "{\"session_id\":\"scope-probe\",\"cwd\":\"$REPO\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m wip\"}}" | node review-gate-check.js
```

**Happened:** All writes landed under `throwaway/.claude/`, none under `~/.claude/`:

```
throwaway/.claude/design-lane-gate/{.gitignore,log.md,state.json}
throwaway/.claude/review-gate/{.gitignore,log.md,state.json}
throwaway/.claude/canary/{.gitignore,state.json}
throwaway/.claude/visual-plan-gate/{.gitignore,state.json}
```

```
$ grep -c "scope-probe" ~/.claude/design-lane-gate/state.json ~/.claude/review-gate/state.json
~/.claude/design-lane-gate/state.json:0
~/.claude/review-gate/state.json:0
```

No crash, no silent no-op, no wrong-scope write. `.gitignore` (`*` + `!.gitignore`) auto-created in each gate dir as `_lib.js:65-74` claims. `_lib.js:40-50`'s deliberate "never walk past home" guard was also exercised implicitly: cwd `/nonexistent/zzz` resolved to global, not to a bogus project.

**Severity:** working-as-documented. **Category:** scope.

## 5. Hook scope follows the Bash tool's persisted cwd, not the session cwd — degraded

**Tried:** From a session whose cwd is `C:\Users\SyedHassan` (global scope), ran a real `Write` of `throwaway/Widget.tsx` and a real `git commit` — after an earlier Bash call had `cd`'d into `throwaway`.

**Happened:** The real session's hook writes went to **project** scope, not global:

```
$ node -e "console.log(Object.keys(require('.../throwaway/.claude/design-lane-gate/state.json')))"
[ '1ffaa591-6324-4ae1-85ea-3fd5dd744d4c', 'unknown', 'scope-probe' ]
```

and global-scope state for this session was frozen at its pre-probe timestamp:

```
$ node -e "...require('C:/Users/SyedHassan/.claude/design-lane-gate/state.json')['1ffaa591-...']"
{ "uiTouched": false, "screenshotSeen": false, "pending": null,
  "pendingNativeControl": null, "lastSeen": "2026-08-27T09:13:25.243Z" }
```

Consequence: a single session's gate/canary/memory state can be split across two or more scopes purely because a Bash call changed directory. `memory-init.js` will inject the wrong scope's checkpoint next session; a MISS logged under a throwaway repo's `.claude/` is effectively lost. Nothing in `memory/SPEC.md` or `WORKFLOW.md` describes mid-session scope migration.

**Severity:** degraded. **Category:** scope.

## 6. All hooks fail open on malformed, empty, and missing-field input — working-as-documented

**Tried:** 4×10 matrix — every hook in `memory/hooks/` against empty stdin, `{}`, `not json at all`, and `{"session_id":"probe-x","cwd":"/nonexistent/zzz","transcript_path":"/nonexistent/t.jsonl"}`.

**Happened:** 40/40 → `exit=0`, empty stderr, no stack trace, no block. Example rows:

```
--- canary-check.js | MALFORMED | exit=0
--- review-gate-check.js | MISSING/BAD PATHS | exit=0
--- memory-compact.js | EMPTY STDIN | exit=0
```

Exit 2 is Claude Code's blocking signal; it was never produced. `readHookInput()` (`_lib.js:18-26`) swallows parse errors to `{}`, and every hook wraps `main()` in `try {} catch (_) {}` + unconditional `process.exit(0)`.

**Severity:** working-as-documented. **Category:** robustness.

## 7. `review-gate-check.js` is a dead gate — pre-satisfied by Claude Code's own agent listing — BROKEN

**Tried:** After a real `git commit` of a real UI file in this session, checked whether a MISS was logged.

**Happened:** No MISS. Live state showed the sticky flag already set before any work:

```json
"1ffaa591-6324-4ae1-85ea-3fd5dd744d4c": {"offset":337607,"reviewSeen":true,"pending":null,...}
```

Root cause located mechanically. `review-gate-check.js:10`:

```js
const MARKER_RE = /\b(review-loop|security-audit|security-review|security-spec|red-team-desk|coderabbit)\b/i;
```

is tested against raw transcript text. Scanning this session's transcript for first occurrence of each marker:

```
review-loop        36907
security-audit     37463
security-review    38925
security-spec      39012
red-team-desk      36006
coderabbit         31157
FIRST MATCHING LINE idx 17 type= attachment
```

Line 18 of the transcript is a Claude Code `agent_listing_delta` attachment — injected automatically at session start, listing available agents including `coderabbit:code-reviewer`. Isolated repro against that single line, in a clean `CLAUDE_HARNESS_HOME_OVERRIDE` sandbox:

```bash
sed -n '18p' <transcript> > t.jsonl   # 3092 bytes, one attachment line
printf '%s' '{"session_id":"clean-2","cwd":"<sandbox>","transcript_path":"<sandbox>/t.jsonl",
  "tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | node review-gate-check.js
```

```
state: {"clean-2":{"offset":3092,"reviewSeen":true,"pending":null,"lastSeen":"2026-08-27T09:17:03.073Z"}}
log:   (no log.md — no MISS was ever written)
```

Control, same sandbox, same commit, transcript that does *not* contain a marker:

```
state: {"clean-1":{"offset":0,"reviewSeen":false,"pending":{"at":"..."},...}}
log:   MISS | 2026-08-27T09:16:33.910Z | session clean-1 | commit ran, no review-loop/security-audit evidence yet this session
```

So the gate is functional in principle and non-functional in practice: on any machine where the `coderabbit` plugin/agent is present, Claude Code's own boilerplate satisfies the marker before the user types anything. `WORKFLOW.md:64` presents this hook as the mechanical answer to a real observed skill-adoption gap. Empirically it can never fire on this setup. The same weakness applies to the user's own prompt text — the audit brief in this session mentions all six markers in prose.

**Severity:** broken. **Category:** gate.

## 8. `design-lane-gate-check.js` fires correctly end-to-end — working-as-documented

**Tried:** Real session, real tools. `Write` of `throwaway/Widget.tsx` containing `<input type="date">` and `<select>`, then real `git add && git commit`. No screenshot, no Playwright, anywhere in session.

**Happened:** Both nudges logged to the resolved scope's `log.md`:

```
NATIVE | 2026-08-27T09:15:29.914Z | session 1ffaa591-... | native form control added in ...\Widget.tsx -- screenshot verification has a blind spot for this component class (see rules/design-lane.md anti-patterns)
MISS   | 2026-08-27T09:15:39.115Z | session 1ffaa591-... | commit ran, UI file touched this session, no screenshot/Playwright evidence found
```

State:

```json
{"uiTouched":true,"screenshotSeen":false,
 "pending":{"at":"2026-08-27T09:15:39.114Z"},
 "pendingNativeControl":{"at":"2026-08-27T09:15:29.913Z","file":"...\\Widget.tsx"}}
```

The `UserPromptSubmit` surfacing side was verified by direct invocation (synthetic session, project scope), returning both blocks in one payload and clearing both pendings:

```json
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"## Claude Harness -- design-lane gate miss\n\n…\n\n## Claude Harness -- native-control blind spot\n\n…"}}
```

Caveat on the real-session half: surfacing to the *live* session requires a subsequent user prompt, which a single-turn audit cannot generate. The `pending` object is written and waiting; the injection path itself is proven only synthetically.

Known-by-design limits worth recording: `UI_FILE_RE` (`:14`) covers `.tsx|jsx|vue|svelte|css|scss|less|html` — UI written in plain `.js`/`.ts` is invisible to the gate. `screenshotSeen` is set by a `Read` of *any* `.png/.jpg/.webp/.gif` (`:62`) or by the literal word `playwright` appearing in *any* Bash command (`:16`, `:77`) — both are trivially satisfiable without rendering anything.

**Severity:** working-as-documented (with the coverage caveats above). **Category:** gate.

## 9. `caveman-mode-tracker.js` silently disables caveman on any mention of the phrase — BROKEN

**Tried:** Noticed that `~/.claude/.caveman-active` did not exist mid-session despite the SessionStart banner having fired. Ran the activate hook manually to confirm it *can* write:

```
$ node ~/.claude/claude-harness/caveman/hooks/caveman-activate.js; echo exit=$?
exit=0
$ cat ~/.claude/.caveman-active
ultra
```

Then replayed this session's own opening user prompt through the tracker:

```bash
node caveman-activate.js >/dev/null      # flag = "ultra"
echo '{"prompt":"Try to get caveman-ultra to lapse without saying \"stop caveman\" — long session, security-adjacent topic."}' | node caveman-mode-tracker.js
```

**Happened:**

```
flag before: ultra
 <-- stdout   (empty — no reinforcement line emitted)
flag after: cat: /c/Users/SyedHassan/.claude/.caveman-active: No such file or directory
```

Second, weaker trigger — a shell command that merely *searches* for the phrase:

```bash
echo '{"prompt":"grep -n \"normal mode\" ./docs/*.md"}' | node caveman-mode-tracker.js
```

```
flag after grep-mention: cat: ... No such file or directory
```

Root cause, `caveman-mode-tracker.js:62-64`:

```js
if (/\b(stop caveman|normal mode)\b/i.test(prompt)) {
  try { fs.unlinkSync(flagPath); } catch (e) {}
}
```

A bare word-boundary test over the entire prompt. No quote-awareness, no negation-awareness ("without saying \"stop caveman\""), no code-block exclusion, no confirmation, no output. Consequences, all silent:

1. The per-turn reinforcement line (`:70-76`) — the thing the header comment calls "the anchor that actually survives session length" — stops being emitted for the rest of the session.
2. The statusline badge disappears (see #10).
3. Nothing tells the user or the agent that the mode was turned off.

**Attribution in this session, and how far it is actually proven.** The kill phrase appears in this session's *user* prompt at `2026-08-27T09:11:40.226Z` — turn 1, ~7 minutes after SessionStart:

```
$ node -e "<scan every ~/.claude/projects/C--Users-SyedHassan/*.jsonl for a user-role
            message matching /\b(stop caveman|normal mode)\b/i>"
1ffaa591 2026-08-27T09:24:53.946Z KILL-PHRASE @ 2026-08-27T09:11:40.226Z
```

That the flag *existed* before that moment is inferred, not directly observed, but the inference is tight: `caveman-activate.js` writes the flag at `:28-33` and only reaches its `process.stdout.write(output)` at `:148` afterwards — and the banner did appear in this session, so the process ran past the write. The write's only failure mode is an fs error inside the silent try/catch, and a manual run in the identical environment succeeded (`flag: ultra`). The alternative hypothesis — activate silently failed to write — is not excluded outright, but would itself be a distinct bug of equal severity.

**Not a one-off.** The same scan shows the kill phrase in a user prompt in **6 of 20** local session transcripts:

```
12e4de56  KILL-PHRASE @ 2026-08-06T08:41:09.145Z
55b41ff2  KILL-PHRASE @ 2026-08-23T19:37:00.451Z
6cf44d5b  KILL-PHRASE @ 2026-08-11T19:51:06.060Z
71e2211b  KILL-PHRASE @ 2026-08-03T09:15:32.039Z
7e707070  KILL-PHRASE @ 2026-08-10T11:02:21.843Z
1ffaa591  KILL-PHRASE @ 2026-08-27T09:11:40.226Z
```

Not all six were necessarily false positives — some may have been genuine deactivation requests. But the phrase is unavoidable in any session that *discusses* caveman mode, which is exactly the class of session where the user is most likely to be working on the pack itself. 30% of sessions tripping a silent, unannounced kill switch is the observable.

Partial mitigation, worth stating precisely: prose terseness *did* persist this session — but only because `caveman-activate.js` had already injected the full ruleset into SessionStart context and `~/.claude/CLAUDE.md` independently declares caveman ultra non-negotiable. That is doc-level redundancy masking a hook-level failure, not the hook working.

**Severity:** broken. **Category:** caveman.

## 10. Caveman statusline badge absent for the whole session — degraded

**Tried:** `ls -la ~/.claude/.caveman-active` at audit time; `cmd /c dir /a` to rule out a hidden-attribute artifact.

**Happened:**

```
ls: cannot access '/c/Users/SyedHassan/.claude/.caveman-active': No such file or directory
```

`statusline.sh` gates the badge on that file existing (`caveman_flag="$HOME/.claude/.caveman-active"`). With the file deleted by #9, `[CAVEMAN:ULTRA]` never renders — while the mode is, per CLAUDE.md, still meant to be active. The badge is therefore not a trustworthy indicator of caveman state: it can only under-report, never over-report.

Downstream of #9. **Severity:** degraded. **Category:** statusline.

## 11. `required: true` skill `ponytail` is not installed at all — broken

**Tried:** `manifest.yaml:3` states "`required: true` = always on for every session." Three entries carry it: `ponytail`, `caveman`, `session-memory`. Checked each for on-disk reality.

**Happened:** `caveman` and `session-memory` are shipped in-repo and wired into `settings.json` — real. `ponytail` is absent everywhere:

```
$ find ~/.claude -maxdepth 4 -iname "*ponytail*"
(no output)
$ npm ls -g --depth=0 | grep -i ponytail
not globally installed
```

It is also not in this session's skill listing and not in `~/.claude/plugins/installed_plugins.json` (which holds `skill-codex`, `coderabbit`, `superpowers`, `claude-mem`).

The upstream source *is* real — `WebFetch https://github.com/DietrichGebert/ponytail` returned a live repo, description "Makes your AI agent think like the laziest senior dev in the room…", 113.2k stars, 210 commits. So this is not vaporware in the manifest; it is a genuine skill that the manifest marks always-on and the installer never installs.

Net effect: the pack's designated "core engineering — YAGNI ladder, root-cause fixes, minimal safe code" skill contributes nothing at runtime. Whatever YAGNI behavior occurs comes from `rules/engineering.md` prose only.

**Severity:** broken. **Category:** manifest-vs-reality.

## 12. `visual-plan-local` and `onboarding` are shipped but not registered — broken

**Tried:** Both ship SKILL.md files inside the pack:

```
$ find ~/.claude/claude-harness -name SKILL.md
caveman/skills/caveman/SKILL.md
onboarding/skills/onboarding/SKILL.md
visual-plan-local/skills/visual-plan-local/SKILL.md
visual-plan-local/vendor/diagram-design/SKILL.md
```

Attempted to invoke each.

**Happened:**

```
Skill(visual-plan-local) → Unknown skill: visual-plan-local
Skill(onboarding)        → Unknown skill: onboarding
```

Neither appears in this session's skill listing. The likely mechanism — that Claude Code resolves skills from `~/.claude/skills/`, `~/.claude/commands/`, and enabled plugins, but not from arbitrary nested paths like `~/.claude/claude-harness/*/skills/` — is inference from the observed layout, not something this audit tested. The *effect* (both skills unresolvable) is directly proven by the two tool errors above. `~/.claude/skills/` contains ten skills — `impeccable, pdf-inspect, playwright, red-team-desk, requirements-matrix, review-loop, rtk, security-audit, tender-pdf, ui-ux-pro-max` — none of them these two.

`caveman` survives only incidentally: `~/.claude/commands/caveman.md` exists as a slash command, and the *behavior* is injected by the SessionStart hook rather than by skill resolution.

This directly voids `WORKFLOW.md:44`'s ("`visual-plan-local` … is the default rendering surface … This is the default because the plan file itself is what it produces; it doesn't need to be separately invoked") — it cannot be invoked at all, separately or otherwise. Same for the manifest's `onboarding` trigger `/harness-onboard`.

**Severity:** broken. **Category:** manifest-vs-reality.

## 13. `superpowers` TDD skill referenced by WORKFLOW.md is unavailable — degraded

**Tried:** `WORKFLOW.md:49` — "use the superpowers TDD skill when the task calls for test-first."

```
Skill(superpowers:test-driven-development) → Unknown skill: superpowers:test-driven-development
```

**Happened:** The plugin *is* installed on disk (`superpowers@superpowers-marketplace 5.1.0`, `~/.claude/plugins/cache/…`) but `settings.json`'s `enabledPlugins` contains only `{"coderabbit@claude-plugins-official": true}`. Installed ≠ enabled ≠ callable. No superpowers skill appears in this session's listing.

**Severity:** degraded. **Category:** manifest-vs-reality.

## 14. `anti-slop`, named inside a "hard gate", is not installed — degraded

**Tried:** `rules/design-lane.md:25` — the render-before-judging **hard gate** — ends: "Alongside the screenshot, run `anti-slop`'s Delivery Gate (see `skills/manifest.yaml`) — a rule-tiered PASS/FAIL filter (38 rules…)".

**Happened:** `anti-slop` is not in `~/.claude/skills/`, not in the session skill listing, not in `installed_plugins.json`. Manifest lists `source: "https://github.com/miqdadbadjuber/anti-slop"`, `trigger: "ui"`, `required: false`.

Half of a rule the pack itself labels "hard, not optional" cannot be executed on this machine.

**Severity:** degraded. **Category:** manifest-vs-reality.

## 15. `onboarding/verify.js` reports all-green while #11–#14 hold — degraded

**Tried:** `node ~/.claude/claude-harness/onboarding/verify.js`

**Happened:**

```
[claude-harness] onboarding verify:
  ✓ always-on      ok    rules + manifest present
  ✓ caveman        ok    installed, configured, wired into settings.json
  ✓ memory-hooks   ok    installed and wired into settings.json
exit=0
```

Three checks, all file-presence and settings-wiring. It does not check that `required: true` skills are actually installed (#11), that shipped skills are resolvable by Claude Code (#12), or that the caveman flag file survives a turn (#9/#10). The verifier's green is compatible with the pack's only always-on engineering skill being entirely absent.

**Severity:** degraded. **Category:** verification.

## 16. Statusline renders with live numbers — working-as-documented

**Tried:** Two synthetic payloads with different context usage, cwd, session start, and rate limits, piped to `bash ~/.claude/statusline.sh`.

**Happened (sample A, 100k/1M, cwd = home, start 08:00Z):**

```
Opus 5 │ Context Window: 10% │ SyedHassan │ ⏱ 1h17m │ ◑ medium
current ●●●●○○○○○○  42% ⟳ resets in - 0 mins
weekly  ●○○○○○○○○○  11% ⟳ resets in - 0 mins
```

**Sample B (750k/1M, cwd = throwaway repo, start yesterday 08:00Z):**

```
Opus 5 │ Context Window: 75% │ throwaway (master*) │ ⏱ 25h17m │ ◑ medium
current ●●●●●●●●○○  88% ⟳ resets in - 0 mins
```

Every field tracked its input: 10%→75% with colour flip green→red, 42%→88% bar fill 4→8, `SyedHassan`→`throwaway`, git branch `(master*)` detected with the dirty marker only in the repo, duration `1h17m`→`25h17m`. Not static.

`jq` is not on PATH; the WinGet-glob fallback (`statusline.sh`, lines documenting the 2026-08-02 second pass) resolved it at `…/WinGet/Packages/jqlang.jq_.../jq` and the script worked. Empty stdin → prints `Claude`, exit 0.

**Severity:** working-as-documented. **Category:** statusline.

## 17. Statusline `extra` row prints `$0.00/$0.00` — cosmetic

**Tried:** Same renders as #16.

**Happened:** Every render appended:

```
extra   ○○○○○○○○○○ $0.00/$0.00 ⟳ sep 1
```

Read the cache the script uses (`/tmp/claude/statusline-usage-cache.json` → `C:\Users\SYEDHA~1\AppData\Local\Temp\claude\statusline-usage-cache.json`, mtime 2026-08-27 10:04):

```json
"extra_usage": {"is_enabled":true,"monthly_limit":0,"used_credits":0,
                "utilization":null,"currency":"GBP", …}
```

So — correcting the obvious guess — this is **not** a stale cache or a failed parse. The data is live and genuine: extra usage is enabled with a zero limit and zero spend. The script faithfully renders it. Two real defects remain, both minor: a permanently-empty `$0.00/$0.00` meter occupies a full statusline row and conveys nothing, and `currency: "GBP"` is discarded — the row hardcodes `$`.

Corroboration that #16's numbers are live rather than synthetic: the same cache carries `seven_day.utilization: 79`, a plausible real value on a real account.

**Severity:** cosmetic. **Category:** statusline.

## 18. Self-test suite passes 71/71 but has coverage holes over the two broken paths — degraded

**Tried:** `bash ~/.claude/claude-harness/memory/hooks/test/run.sh`

**Happened:**

```
ALL 71 CHECKS PASSED
```

Including `Test 13: real ~/.claude/session gains no NEW files from this run — PASS`. The suite is genuinely careful (atomic-rename verification under contention, PascalCase `<Select>` false-positive guards, self-closing `<select />`, `<Input type="date">` negative case).

But:

```
$ grep -c "caveman" run.sh
0
```

Zero coverage of `caveman-activate.js` / `caveman-mode-tracker.js` — the two hooks that produced finding #9.

And Test 36 asserts exactly the behavior that makes #7 a dead gate:

```
Test 36: review-gate-check.js -- review-marker evidence anywhere in-session clears the sticky flag, no MISS on commit
```

The test encodes "anywhere in-session" as intended, so the suite is internally consistent — it just never asks whether Claude Code's own injected boilerplate counts as "anywhere."

**Severity:** degraded. **Category:** test-coverage.

## 19. Undocumented third-party hook fires on Write — cosmetic

**Tried:** Real `Write` of `throwaway/Widget.tsx`.

**Happened:** An additional PostToolUse hook, absent from `~/.claude/settings.json`, returned:

```
[impeccable@1] Design hook scanned Widget.tsx. No deterministic design-quality issues found.
That does not mean the design is good: keep following the project design system
and the impeccable skill guidance.
```

Not wired in `settings.json`'s `hooks` block and not mentioned in `WORKFLOW.md` or the manifest's `impeccable` entry. It functions, but the pack's own docs are not the complete picture of what runs on a tool call.

**Severity:** cosmetic. **Category:** config-drift.

## 20. `claude-mem` installed and touched today despite "opt-in only, never default" — cosmetic

**Tried:** `cat ~/.claude/plugins/installed_plugins.json`

**Happened:**

```
skill-codex@skill-codex              | 1.3.0    | 2026-05-01T09:49:51.860Z
coderabbit@claude-plugins-official   | 1.1.1    | 2026-05-02T18:35:03.378Z
superpowers@superpowers-marketplace  | 5.1.0    | 2026-06-14T21:24:46.842Z
claude-mem@thedotmack                | 13.16.1  | 2026-08-27T09:15:51.889Z
```

`manifest.yaml` marks `claude-mem` `trigger: "opt-in only, never default"`. It is installed, and its `lastUpdated` is *during this audit session*. It is not in `enabledPlugins`, so it is presumably inert — but `settings.local.json` does allowlist `mcp__plugin_claude-mem_mcp-search__search` and `…__get_observations`, so a parallel memory system is at least partially provisioned alongside the pack's own.

**Severity:** cosmetic (no observed interference). **Category:** manifest-vs-reality.

## 21. Hooks accept `session_id`-less input and create an `"unknown"` bucket — cosmetic

**Tried:** Part of the #6 matrix — payloads with no `session_id`.

**Happened:** `review-gate-check.js:53` and peers default to the literal string `'unknown'`, and that becomes a real state key:

```
$ node -e "console.log(Object.keys(require('.../throwaway/.claude/design-lane-gate/state.json')))"
[ '1ffaa591-...', 'unknown', 'scope-probe' ]
$ cat .../throwaway/.claude/canary/state.json
{"unknown":{"offset":0,"pending":null,"lastSeen":"2026-08-27T09:14:21.814Z"}}
```

All sessions lacking an id collide in one bucket, cross-contaminating sticky flags and transcript offsets. Bounded by the 30-day TTL prune. Not reachable through normal Claude Code operation, which always supplies `session_id`.

**Severity:** cosmetic. **Category:** robustness.

## 22. Environment `gitStatus` claims a repo where `git rev-parse` finds none — cosmetic, not the pack

**Tried:** Session env block reported `Is a git repository: true`, `Current branch: HEAD`, `Main branch: main`, status clean.

**Happened:**

```
$ pwd; git rev-parse --is-inside-work-tree
/c/Users/SyedHassan
fatal: not a git repository (or any of the parent directories): .git
```

This is Claude Code's own gitStatus probe, not harness code — `_lib.js`'s independent `walkForGitRoot` resolved global scope correctly throughout. Logged because a reader comparing the session header against scope behavior would otherwise see a contradiction.

**Severity:** cosmetic. **Category:** harness-external.

## 23. Drift canary — mechanism live, substance UNVERIFIABLE — unverifiable

**Tried:** Inspected live canary state; read `canary-check.js`'s role per `WORKFLOW.md:19`.

**Happened:** The hook is running and tracking this session:

```json
"1ffaa591-6324-4ae1-85ea-3fd5dd744d4c": {"offset":15142,"pending":null,"lastSeen":"2026-08-27T09:11:41.069Z"}
```

`pending: null` — no naming miss registered across four tracked sessions, and `memory-init.js` correctly suppressed the rollup block.

What cannot be verified: `WORKFLOW.md:19` states outright that the canary "cannot and does not verify that a rule's *substance* was followed" — it checks pack-file-citation ∧ name-co-occurrence. In this session the auditor cited pack files and named Zarak, so the proxy is satisfied; whether the rules were *followed* is exactly the self-graded prose the canary was built to admit it cannot measure. Additionally, an auditor who has read `WORKFLOW.md` will name Zarak whether or not the mechanism works, so this session cannot serve as a test of it either way.

**Severity:** unverifiable-by-construction (and honestly self-labelled as such by the doc). **Category:** canary.

## 24. Hard/always/mandatory claims without hook backing — unverifiable (probe 8)

**Tried:**

```bash
grep -nE "\b(hard|always|mandatory|must|never|unconditional|every turn|not optional)\b" rules/*.md WORKFLOW.md | wc -l
→ 33
```

**Happened:** Mapping each to a mechanical backstop:

| Claim | Location | Hook backing |
|---|---|---|
| Secret files: never read/echo/commit | `security-invariants.md:13-18` | **Partial.** `secret-guard.js` blocks Edit/Write *content* matching 5 regexes. It does not and cannot block **reading** a `.env`, or echoing to chat. The rule's own text (`:45`) concedes this. |
| Auth/data invariants (404-not-403, rate limits, UUIDs, query scoping) | `security-invariants.md:22-26` | **None.** Prose only. |
| Web transport (form `method=post`, SameSite, XFF `[-1]`) | `security-invariants.md:30-32` | **None.** |
| Never mutate global agent configs unless asked | `security-invariants.md:36` | **None** — and note the pack's own hooks write to `~/.claude/` on every session. |
| External verification before "done" | `security-invariants.md:38`, `WORKFLOW.md:54` | **None.** Self-graded. |
| Sub-tool confidence ≠ authorization | `security-invariants.md:40` | **None.** Self-graded. |
| Render-before-judging, "hard gate" | `design-lane.md:25`, `WORKFLOW.md:55` | **Post-hoc only.** `design-lane-gate-check.js` logs a MISS *after* a commit; it never blocks, and its evidence test is satisfied by reading any `.png` or typing `playwright` in a shell command. Also depends on `anti-slop`, absent (#14). |
| Pre-commit review evidence | `WORKFLOW.md:64` | **Dead** — see #7. |
| Caveman "ACTIVE EVERY RESPONSE… no revert" | SKILL.md, `WORKFLOW.md:13` | **Broken backstop** — see #9. |
| Drift canary | `WORKFLOW.md:17-19` | **Proxy only**, self-labelled — see #23. |

### `secret-guard.js` — fired live, works (and blocked this very document)

Not merely inspected. Four synthetic payloads through `~/.claude/hooks/secret-guard.js` (literals redacted here — see below for why):

```
Write, content = a canonical fake AWS access key literal
  → stderr: MACHINA SECRET GUARD — write blocked.
               pattern: AWS access key
               use environment variables or a secrets manager — never commit literals.
     exit=2

Edit, new_string = a generic api-key assignment literal
  → stderr: … pattern: Generic API key assignment        exit=2

Write, content = "console.log(1)"                        exit=0
Read,  file_path = "C:/tmp/.env"                         exit=0  (Read is not in the matcher)
```

Exit 2 is Claude Code's blocking code, and `harness-hook-utils.js`'s `block()` is correct — `process.stderr.write(...)` then `process.exit(2)`, matching its own comment "exit 2 blocks PreToolUse". True positives block, benign content passes, no false positive observed.

**Stronger evidence than the synthetic runs:** the first attempt to write *this section* — which quoted the fake key literal verbatim as audit evidence — was itself blocked by the real hook on the real `Edit` path:

```
PreToolUse:Edit hook error: [node "C:/Users/SyedHassan/.claude/hooks/secret-guard.js"]:
MACHINA SECRET GUARD — write blocked.
  pattern: AWS access key
```

That is end-to-end confirmation through Claude Code's actual PreToolUse wiring, not a piped-stdin simulation. It also exposes a small real-world cost: the guard cannot distinguish a secret from documentation *about* a secret, so security write-ups must self-censor. Working as designed; worth knowing.

Scope limits, now confirmed rather than assumed: the hook is wired `PreToolUse` on `Edit|Write` only, and reads only `tool_input.content` / `new_string` / `new_str`. It therefore cannot see a `Read` of a `.env`, a `Bash` `cat`/`echo` of a secret, a secret pasted into chat, or a `git add` of a secret file — all of which `security-invariants.md:13-18` forbids. It sits **outside** the pack directory (`~/.claude/hooks/`, mtime 2026-06-20) and is therefore not versioned by the claude-harness repo, while `security-invariants.md:5` designates it the sole mechanical backstop for all of Tier 0.

Every row marked "None" is **unverifiable-by-construction**, not a pass and not a failure — there is no observable that could distinguish compliance from imitation.

**Severity:** unverifiable. **Category:** probe-8.

## 25. WORKFLOW.md's "HTML out" default vs the user's markdown request — cosmetic

`WORKFLOW.md:23-26` makes self-contained HTML the default for "anything a human will VIEW rather than paste into another platform: reports, comparisons, dashboards, analysis write-ups." This audit is exactly that shape. The user explicitly asked for "a structured markdown audit log … Save it to a file." User instruction wins; recorded only as an observed divergence between a standing pack default and an explicit ask.

**Severity:** cosmetic. **Category:** doc-conflict.

---

## Audit-induced side effects (disclosure)

These probes mutated real state. Recorded so a follow-up session does not misread them as organic:

- `~/.claude/.caveman-active` — deleted by the tracker replay in #9, restored to `ultra` at the end of that probe.
- `~/.claude/{canary,review-gate,design-lane-gate,visual-plan-gate}/state.json` — `lastSeen` timestamps advanced by direct hook invocation; a `"probe-x"` entry may exist.
- `…/scratchpad/throwaway/.claude/` — entirely audit-created, contains real `1ffaa591-…` session state plus `scope-probe` and `unknown` buckets, and real MISS/NATIVE log lines.
- `…/scratchpad/throwaway/` — throwaway git repo with one commit (`Widget.tsx`).
- `memory-init.js` was invoked ~6× directly; it is read-only except for global-scope checkpoint rotation, and no live `checkpoint.md` existed to rotate.
- No file inside `~/.claude/claude-harness/` was modified.
