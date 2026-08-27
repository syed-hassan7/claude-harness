#!/usr/bin/env bash
# Installs the Claude Harness rules/skills/memory pack + statusline into
# ~/.claude. Idempotent — safe to re-run after `git pull`.
#
# Usage: ./install.sh [--with-memory-hooks] [--check] [--onboard] [--caveman-mode=<mode>] [--dry-run]
#   --with-memory-hooks   Also install the session-checkpoint hooks (see
#                          memory/SPEC.md). Opt-in, default off: these fire on
#                          every single Edit/Write once wired, and this
#                          installer never auto-edits settings.json — you
#                          paste the printed hook config in yourself. Once
#                          installed with this flag, a later plain `./install.sh`
#                          (no flag) does NOT remove them — there is no
#                          implicit uninstall.
#   --check                Report-only drift check: diffs the installed pack
#                          (~/.claude/claude-harness/) against this repo's
#                          current source, one file/dir at a time. Prints any
#                          mismatches and exits 1 if drift is found, exits 0 if
#                          the pack matches exactly. Never writes anything —
#                          catches the case where the pack fell out of sync
#                          with the repo (e.g. install.sh ran against a dirty
#                          worktree, or the pack was edited directly) without
#                          mutating ~/.claude/CLAUDE.md the way a real install
#                          run would. Exits before any install step runs.
#   --onboard              Interactive wizard: orients on the 3 install tiers,
#                          prompts for the 2 real choices below (memory hooks,
#                          caveman mode), then runs the normal install steps
#                          and finishes with onboarding/verify.js's mechanical
#                          check. Bash-only (reads stdin) — the in-CLI
#                          /harness-onboard skill drives the same choices via
#                          --with-memory-hooks/--caveman-mode instead, since it
#                          has no TTY to prompt.
#   --caveman-mode=<mode>  Non-interactive equivalent of --onboard's caveman
#                          question. One of ultra|full|lite|off. Only applied
#                          when seeding a FRESH caveman config (same
#                          never-overwrite rule as the rest of this script) —
#                          default ultra if omitted.
#   --dry-run              Preview a fresh run: prints every file/config
#                          write this script would make, writes nothing.
#                          Composes with --onboard and the flags above.
#                          Different job from --check: --check diffs an
#                          ALREADY-installed pack; --dry-run previews what a
#                          run would do on this machine right now, installed
#                          or not.
set -euo pipefail

WITH_MEMORY_HOOKS=0
CHECK_MODE=0
ONBOARD_MODE=0
CAVEMAN_SEED_MODE=""
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --with-memory-hooks) WITH_MEMORY_HOOKS=1 ;;
    --check) CHECK_MODE=1 ;;
    --onboard) ONBOARD_MODE=1 ;;
    --caveman-mode=*) CAVEMAN_SEED_MODE="${arg#--caveman-mode=}" ;;
    --dry-run) DRY_RUN=1 ;;
  esac
done
if [ -n "$CAVEMAN_SEED_MODE" ]; then
  case "$CAVEMAN_SEED_MODE" in
    ultra|full|lite|off) ;;
    *)
      echo "[claude-harness] invalid --caveman-mode='$CAVEMAN_SEED_MODE' (expected ultra|full|lite|off) -- ignoring, default ultra applies"
      CAVEMAN_SEED_MODE=""
      ;;
  esac
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_HARNESS_TARGET:-$HOME/.claude}"
PACK_DIR="$CLAUDE_DIR/claude-harness"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

# Single source of truth for the memory-hooks file list -- both the install
# step's MEMORY_HOOKS_ALL_WIRED check and --check's wiring-drift check need
# every filename, and this bucket already grew from 4 to 10 files across
# several sessions. One list, referenced twice, instead of two hardcoded
# copies quietly drifting apart the moment an 11th hook is added to one but
# not the other.
MEMORY_HOOK_FILES="memory-init.js memory-recall.js canary-check.js review-gate-check.js design-lane-gate-check.js visual-plan-gate-check.js memory-checkpoint.js memory-architecture.js memory-compact.js memory-flush.js"

# On Git Bash, $HOME/PACK_DIR/etc. are POSIX-style (/c/Users/...). That's fine
# for this script's own file operations, but any path we WRITE into CLAUDE.md,
# print as a settings.json snippet, or hand to `node -e` (--onboard's tier
# printout, the closing first-light message) is consumed by native node.exe /
# Claude Code itself, which does not understand /c/... paths (confirmed
# directly: native node.exe fails "Cannot find module"/ENOENT on a
# POSIX-style path). Use drive-letter form for everything user-facing/
# machine-facing; falls back to the original path unchanged on platforms
# without `pwd -W` (macOS/Linux, where this distinction doesn't exist anyway).
# Defined this early (before --check/--onboard) since both need it.
win_path() {
  local p="$1" w
  w=$(cd "$p" 2>/dev/null && pwd -W 2>/dev/null) || true
  if [ -n "$w" ]; then echo "$w"; else echo "$p"; fi
}
REPO_DIR_DISP="$(win_path "$REPO_DIR")"

# Wiring drift check, delegated to onboarding/verify.js --check-wiring.
#
# This used to be a bash function with an embedded `node -e` that checked ONE
# hook's matcher (review-gate-check.js, whose PostToolUse matcher changed from
# "Bash" to "Bash|Skill|Agent" in 6.4.0). That was the right fix for the wrong
# scope: filename-presence checks can't see a matcher value at all, so EVERY
# hook was exposed to the same class of silent staleness, not just that one.
# 6.5.0 moves the whole check into verify.js, which owns the expected-wiring
# table, parses settings.json properly, and additionally catches a settings.json
# entry pointing at a hook file that no longer exists on disk.
#
# Kept from the old implementation, because both were real bugs found in review:
#   - the path goes to verify.js as ARGV/env, never interpolated into a JS
#     source string (an embedded path breaks on a Windows profile like
#     "O'Brien" -- a compile-time SyntaxError no try/catch can swallow), and
#   - a genuine read/parse failure is reported loudly instead of collapsing
#     into "not stale", which would silently read as a pass.
#
# Returns 0 = stale/broken wiring (caller should reprint the block), 1 = fine.
harness_wiring_stale() {
  local settings="$1" rc
  [ -f "$settings" ] || return 1
  CLAUDE_HARNESS_TARGET="$(win_path "$CLAUDE_DIR")"     node "$REPO_DIR/onboarding/verify.js" --check-wiring > /dev/null 2>&1
  rc=$?
  # NOTE the polarity flip, which is easy to get backwards and was, once:
  # verify.js follows the usual CLI convention (exit 0 = healthy), while this
  # function's callers read 0 as "stale, reprint the block". A straight
  # `return "$rc"` therefore inverts the meaning and reprints the wiring block
  # on every healthy install. Caught by running --check against a known-green
  # install and seeing it claim stale wiring.
  case "$rc" in
    0) return 1 ;;  # verify.js: wiring healthy  -> not stale
    1) return 0 ;;  # verify.js: wiring problems -> stale
    *)
      echo "[claude-harness] WARNING: could not check hook wiring freshness (verify.js exited $rc) -- skipping this check, verify manually with: node onboarding/verify.js"
      return 1
      ;;
  esac
}

# --- --check: report-only drift check, exits before any install step runs ---
if [ "$CHECK_MODE" -eq 1 ]; then
  echo "[claude-harness] --check: diffing installed pack ($PACK_DIR) against source ($REPO_DIR)"
  DRIFT=0
  check_path() {
    local rel="$1"
    if [ ! -e "$PACK_DIR/$rel" ]; then
      echo "[claude-harness] MISSING: $rel not installed"
      DRIFT=1
      return
    fi
    local tmp
    tmp="$(mktemp)"
    if ! diff -rq "$REPO_DIR/$rel" "$PACK_DIR/$rel" >"$tmp" 2>&1; then
      cat "$tmp"
      DRIFT=1
    fi
    rm -f "$tmp"
  }
  for rel in rules skills memory/SPEC.md memory/templates caveman onboarding visual-plan-local WORKFLOW.md; do
    check_path "$rel"
  done
  # memory/hooks is opt-in (--with-memory-hooks) — only check it if it was
  # actually installed; its absence is expected default state, not drift.
  if [ -d "$PACK_DIR/memory/hooks" ]; then
    check_path "memory/hooks"
  fi
  # File-copy diff above only proves the hook files exist on disk — it says
  # nothing about whether settings.json actually calls them. A hook can pass
  # every check_path above and still never fire (visual-plan-gate-check.js
  # shipped, tested, documented in d756c48, absent from settings.json the
  # whole time — install.sh --check reported clean). Detect opt-in the same
  # way the install step's own MEMORY_HOOKS_ALL_WIRED gate does: if settings.json
  # mentions ANY hook filename, all of them must be present, or it's drift.
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    ANY_WIRED=0
    for hook_file in $MEMORY_HOOK_FILES; do
      grep -q "$hook_file" "$CLAUDE_DIR/settings.json" && ANY_WIRED=1
    done
    if [ "$ANY_WIRED" -eq 1 ]; then
      for hook_file in $MEMORY_HOOK_FILES; do
        if ! grep -q "$hook_file" "$CLAUDE_DIR/settings.json"; then
          echo "[claude-harness] NOT WIRED: $hook_file present on disk but missing from settings.json hooks"
          DRIFT=1
        fi
      done
      if harness_wiring_stale "$CLAUDE_DIR/settings.json"; then
        echo "[claude-harness] STALE/BROKEN WIRING: at least one hook is unwired, on an out-of-date matcher, or points at a missing file -- run: node onboarding/verify.js   (then re-run ./install.sh and paste the updated hook block)"
        DRIFT=1
      fi
    fi
  fi
  if [ "$DRIFT" -eq 0 ]; then
    echo "[claude-harness] pack matches source exactly — no drift"
    exit 0
  else
    echo "[claude-harness] drift found — re-run ./install.sh (without --check) to sync"
    exit 1
  fi
fi

# --- --onboard: interactive wizard for the 2 real choices, then falls
# through into the same install steps every other invocation runs ---
if [ "$ONBOARD_MODE" -eq 1 ]; then
  echo ""
  echo "[claude-harness] onboarding — three install tiers:"
  node -e '
    const steps = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    for (const t of steps.orient.tiers) {
      console.log("  " + t.label.toUpperCase().padEnd(12) + t.description);
    }
  ' "$REPO_DIR_DISP/onboarding/steps.json"
  echo ""
  if [ "$WITH_MEMORY_HOOKS" -eq 0 ]; then
    read -r -p "[claude-harness] Install memory hooks (session checkpoints, project-architecture recall, drift-canary)? Fires on every Edit/Write once wired. [y/N] " ans
    case "$ans" in
      y|Y|yes|Yes) WITH_MEMORY_HOOKS=1 ;;
      *) WITH_MEMORY_HOOKS=0 ;;
    esac
  fi
  if [ -z "$CAVEMAN_SEED_MODE" ]; then
    read -r -p "[claude-harness] Caveman default intensity [ultra/full/lite/off, default ultra]: " ans
    case "$ans" in
      full|lite|off) CAVEMAN_SEED_MODE="$ans" ;;
      *) CAVEMAN_SEED_MODE="ultra" ;;
    esac
  fi
  echo "[claude-harness] onboarding choices: memory-hooks=$([ "$WITH_MEMORY_HOOKS" -eq 1 ] && echo yes || echo no), caveman-mode=$CAVEMAN_SEED_MODE"
  echo ""
fi

MARKER_START="<!-- claude-harness:managed:start (auto-generated by install.sh — do not hand-edit; re-run install.sh to update) -->"
MARKER_END="<!-- claude-harness:managed:end -->"

echo "[claude-harness] installing from $REPO_DIR into $CLAUDE_DIR"

# --- 0. ponytail: required:true core engineering skill (YAGNI ladder,
# root-cause fixes) -- distributed as a Claude Code marketplace plugin, not
# an npm package (skills/manifest.yaml's install note was wrong/stale until
# 2026-08-27 -- corrected after an external audit found this step never
# existed, so the pack's only always-on engineering skill contributed
# nothing at runtime). Installed via the `claude` CLI's non-interactive
# plugin subcommands (plugin marketplace add / plugin install), not the
# interactive /plugin chat flow -- no stdin prompt. Unconditional, no opt-in
# flag, matching required:true (unlike memory-hooks/caveman below, which are
# genuinely optional). Idempotent -- skips if already installed+enabled.
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would run: claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail (skipped if already installed+enabled)"
elif ! command -v claude >/dev/null 2>&1; then
  echo "[claude-harness] WARNING: 'claude' CLI not on PATH -- cannot install required ponytail plugin. Install manually: claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail"
elif claude plugin list 2>/dev/null | grep -q 'ponytail@ponytail' && [ -f "$CLAUDE_DIR/settings.json" ] && grep -q '"ponytail@ponytail": *true' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
  echo "[claude-harness] ponytail already installed and enabled"
else
  if claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail; then
    echo "[claude-harness] ponytail installed and enabled"
  else
    echo "[claude-harness] WARNING: ponytail install failed (see error output above) -- install manually: claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail"
  fi
fi

# --- 1. Pack files: namespaced, never touch ~/.claude/skills or ~/.claude/memory directly ---
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would sync pack files (rules/, skills/, memory/SPEC.md, memory/templates/, WORKFLOW.md) to $PACK_DIR"
else
  mkdir -p "$PACK_DIR" "$PACK_DIR/memory"
  rm -rf "$PACK_DIR/rules" "$PACK_DIR/skills" "$PACK_DIR/memory/templates"
  cp -r "$REPO_DIR/rules" "$PACK_DIR/rules"
  cp -r "$REPO_DIR/skills" "$PACK_DIR/skills"
  cp "$REPO_DIR/memory/SPEC.md" "$PACK_DIR/memory/SPEC.md"
  cp -r "$REPO_DIR/memory/templates" "$PACK_DIR/memory/templates"
  cp "$REPO_DIR/WORKFLOW.md" "$PACK_DIR/WORKFLOW.md"
  echo "[claude-harness] pack files synced to $PACK_DIR"
fi
PACK_DIR_DISP="$(win_path "$PACK_DIR")"

MEMORY_LINE="Memory spec (session checkpoints + mistake-memory; hooks are spec-only, not shipped yet): \`$PACK_DIR_DISP/memory/SPEC.md\`"
if [ "$WITH_MEMORY_HOOKS" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would install memory hooks at $PACK_DIR/memory/hooks (not wired into settings.json)"
  else
    rm -rf "$PACK_DIR/memory/hooks"
    cp -r "$REPO_DIR/memory/hooks" "$PACK_DIR/memory/hooks"
    echo "[claude-harness] memory hooks installed at $PACK_DIR/memory/hooks (not wired into settings.json — see instructions below)"
  fi
  MEMORY_LINE="Memory spec + hooks (session checkpoints — opt-in, installed): \`$PACK_DIR_DISP/memory/SPEC.md\`, \`$PACK_DIR_DISP/memory/hooks/\`"
  # Unlike the caveman wiring block below, this bucket has grown to 10 hook
  # files across several sessions (canary-check.js -> review-gate-check.js ->
  # design-lane-gate-check.js -> visual-plan-gate-check.js) -- a single-file
  # proxy check (grep for just one filename) would go stale the moment a new
  # hook is added to this list without a matching settings.json edit, so
  # every current file is checked.
  MEMORY_HOOKS_ALL_WIRED=1
  if [ -f "$CLAUDE_DIR/settings.json" ]; then
    for hook_file in $MEMORY_HOOK_FILES; do
      grep -q "$hook_file" "$CLAUDE_DIR/settings.json" || MEMORY_HOOKS_ALL_WIRED=0
    done
    if [ "$MEMORY_HOOKS_ALL_WIRED" -eq 1 ] && harness_wiring_stale "$CLAUDE_DIR/settings.json"; then
      echo "[claude-harness] hook wiring is stale or broken (out-of-date matcher, or a hook pointing at a missing file) -- reprinting the wiring block so you can update it. Run: node onboarding/verify.js  for the specific rows."
      MEMORY_HOOKS_ALL_WIRED=0
    fi
  else
    MEMORY_HOOKS_ALL_WIRED=0
  fi
  if [ "$MEMORY_HOOKS_ALL_WIRED" -eq 1 ]; then
    echo "[claude-harness] memory hooks already fully wired in settings.json"
  else
  cat <<EOF
[claude-harness] Add this to ~/.claude/settings.json under "hooks" (MERGE into
existing arrays — e.g. your SessionStart array already has other hooks,
append to it, don't replace it):
  "SessionStart":     [{ "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/memory-init.js\"", "timeout": 5 }] }]
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/memory-recall.js\"", "timeout": 5 }] },
                        { "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/canary-check.js\"", "timeout": 5 }] },
                        { "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/review-gate-check.js\"", "timeout": 5 }] },
                        { "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/design-lane-gate-check.js\"", "timeout": 5 }] },
                        { "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/visual-plan-gate-check.js\"", "timeout": 5 }] }]
  "PostToolUse":      [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/memory-checkpoint.js\"", "timeout": 5 }] },
                        { "matcher": "Read|Edit|Write", "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/memory-architecture.js\"", "timeout": 5 }] },
                        { "matcher": "Bash|Skill|Agent", "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/review-gate-check.js\"", "timeout": 5 }] },
                        { "matcher": "Edit|Write|Read|Bash|mcp__playwright.*", "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/design-lane-gate-check.js\"", "timeout": 5 }] },
                        { "matcher": "Edit|Write|ExitPlanMode|Artifact", "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/visual-plan-gate-check.js\"", "timeout": 5 }] }]
  "PreCompact":       [{ "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/memory-compact.js\"", "timeout": 5 }] }]
  "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP/memory/hooks/memory-flush.js\"", "timeout": 5 }] }]
memory-recall.js and memory-architecture.js implement project-architecture
memory (memory/SPEC.md's "Project-architecture memory" section) -- mechanical
keyword recall on every prompt + file-touch recall/staleness-flagging on every
Read/Edit/Write. canary-check.js implements the mechanical drift-canary miss
detector (memory/SPEC.md's "Canary-drift memory" section) -- checks pack-file
citation + name co-occurrence on every prompt, non-blocking. review-gate-check.js
implements the mechanical review-gate (memory/SPEC.md's "Review-gate memory"
section) -- registered TWICE (PostToolUse:Bash|Skill|Agent to detect a commit
and real review evidence structurally -- a Skill/Agent call naming a review
tool, or a Bash command actually running the coderabbit CLI, never transcript
text -- UserPromptSubmit to surface a miss on the next turn), same file for
both, non-blocking.
design-lane-gate-check.js implements the mechanical design-lane gate
(memory/SPEC.md's "Design-lane gate memory" section) -- same two-registration
shape and same fully-structural detection (Edit/Write on a UI file, Read on an
image file, mcp__playwright.* tool calls) rather than a transcript text scan,
non-blocking; also flags a native form control (<select>, <input type="date">
etc.) landing in a UI file, independent of the screenshot check.
visual-plan-gate-check.js implements the mechanical visual-plan gate
(memory/SPEC.md's "Visual-plan gate memory" section) -- same two-registration
shape: tracks a Write/Edit to a plan file under <home>/.claude/plans/ and any
Artifact-tool call per session, and on ExitPlanMode checks whether a
non-trivial plan published no Artifact companion, non-blocking. Note each of
these UserPromptSubmit registrations is a SEPARATE
array entry from caveman's
own UserPromptSubmit hook below -- Claude Code runs all matching hooks for an
event, none of them replace each other.
Opt-in for a reason — new code, low-volume real-world testing so far. See memory/SPEC.md.
EOF
  fi
elif [ -d "$PACK_DIR/memory/hooks" ]; then
  echo "[claude-harness] memory hooks already present at $PACK_DIR/memory/hooks (left in place — re-run with --with-memory-hooks to refresh)"
  MEMORY_LINE="Memory spec + hooks (session checkpoints — opt-in, installed): \`$PACK_DIR_DISP/memory/SPEC.md\`, \`$PACK_DIR_DISP/memory/hooks/\`"
else
  echo "[claude-harness] memory hooks NOT installed (default). Re-run with --with-memory-hooks to add them."
fi

# --- 1b. Caveman ultra: default-on communication style, always installed ---
# Not opt-in like memory hooks -- this is the harness's baseline communication
# mode. Ships the hook pair (SessionStart ruleset injection + UserPromptSubmit
# per-turn reinforcement) plus its config resolver and skill source, and seeds
# the default-mode config file to "ultra" if the user has no config yet.
# Existing user config/flag state is never overwritten -- this only sets a
# default where none exists, same idempotence contract as the rest of this
# script.
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would sync caveman/ to $PACK_DIR/caveman"
else
  rm -rf "$PACK_DIR/caveman"
  cp -r "$REPO_DIR/caveman" "$PACK_DIR/caveman"
  echo "[claude-harness] caveman hooks synced to $PACK_DIR/caveman"
fi

CAVEMAN_CONFIG_DIR="${XDG_CONFIG_HOME:-}"
if [ -n "$CAVEMAN_CONFIG_DIR" ]; then
  CAVEMAN_CONFIG_DIR="$CAVEMAN_CONFIG_DIR/caveman"
elif [ -n "${APPDATA:-}" ]; then
  CAVEMAN_CONFIG_DIR="$APPDATA/caveman"
else
  CAVEMAN_CONFIG_DIR="$HOME/.config/caveman"
fi
CAVEMAN_CONFIG_DIR="${CAVEMAN_CONFIG_DIR//\\//}"
CAVEMAN_CONFIG_FILE="$CAVEMAN_CONFIG_DIR/config.json"
if [ ! -f "$CAVEMAN_CONFIG_FILE" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would seed caveman config at $CAVEMAN_CONFIG_FILE with defaultMode=${CAVEMAN_SEED_MODE:-ultra}"
  else
    mkdir -p "$CAVEMAN_CONFIG_DIR"
    echo "{ \"defaultMode\": \"${CAVEMAN_SEED_MODE:-ultra}\" }" > "$CAVEMAN_CONFIG_FILE"
    echo "[claude-harness] caveman default mode set to ${CAVEMAN_SEED_MODE:-ultra} at $CAVEMAN_CONFIG_FILE"
  fi
else
  echo "[claude-harness] caveman config already exists at $CAVEMAN_CONFIG_FILE — left as-is"
fi

# --- 1c. Onboarding helpers: steps.json + verify.js, always synced (cheap,
# read-only files) so a --with-memory-hooks/--caveman-mode run or a later
# manual `node .../onboarding/verify.js` always has a current copy ---
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would sync onboarding/ to $PACK_DIR/onboarding"
else
  rm -rf "$PACK_DIR/onboarding"
  cp -r "$REPO_DIR/onboarding" "$PACK_DIR/onboarding"
  echo "[claude-harness] onboarding helpers synced to $PACK_DIR/onboarding"
fi

# --- 1d. visual-plan-local: default plan-mode rendering skill + vendored
# diagram-design engine -- always synced, no settings.json wiring needed
# (it's a skill, not a hook) ---
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would sync visual-plan-local/ to $PACK_DIR/visual-plan-local"
else
  rm -rf "$PACK_DIR/visual-plan-local"
  cp -r "$REPO_DIR/visual-plan-local" "$PACK_DIR/visual-plan-local"
  echo "[claude-harness] visual-plan-local synced to $PACK_DIR/visual-plan-local"
fi

# --- 1e. security/: the Tier 0 secret guard. ALWAYS installed, no flag --
# rules/security-invariants.md:5 designates secret-guard.js the single
# mechanical backstop for all of Tier 0, with no opt-out, so it must not be
# opt-in here either.
#
# Until 2026-08-27 this file was not in this repo at all: it survived only as an
# untracked leftover in one developer's ~/.claude/hooks/ from the retired v4
# harness. Every fresh install therefore shipped the RULE claiming a mechanical
# secret backstop and none of the hook -- structurally the same defect as
# `ponytail` being required:true and never installed. Copied to
# $CLAUDE_DIR/hooks/ (NOT under $PACK_DIR) deliberately: that is the path
# existing installs' PreToolUse block already points at, so nobody has to
# re-paste wiring to pick this up.
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would sync security/ to $PACK_DIR/security and install secret-guard.js to $CLAUDE_DIR/hooks/"
else
  rm -rf "$PACK_DIR/security"
  cp -r "$REPO_DIR/security" "$PACK_DIR/security"
  mkdir -p "$CLAUDE_DIR/hooks"
  cp "$REPO_DIR/security/hooks/secret-guard.js" "$CLAUDE_DIR/hooks/secret-guard.js"
  echo "[claude-harness] secret-guard.js installed to $CLAUDE_DIR/hooks/secret-guard.js (Tier 0, always on)"
fi

if [ -f "$CLAUDE_DIR/settings.json" ] && grep -q 'secret-guard.js' "$CLAUDE_DIR/settings.json"; then
  echo "[claude-harness] secret-guard already wired in settings.json"
else
  CLAUDE_DIR_DISP="$(win_path "$CLAUDE_DIR")"
  cat <<EOF
[claude-harness] Add this to ~/.claude/settings.json under "hooks" (MERGE):

  "PreToolUse": [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "node \"$CLAUDE_DIR_DISP/hooks/secret-guard.js\"", "timeout": 5 }] }]

EOF
fi

PACK_DIR_DISP_PRE="$(win_path "$PACK_DIR")"
if [ -f "$CLAUDE_DIR/settings.json" ] && grep -q 'caveman-activate.js' "$CLAUDE_DIR/settings.json"; then
  echo "[claude-harness] caveman hooks already wired in settings.json"
else
  cat <<EOF
[claude-harness] Add this to ~/.claude/settings.json under "hooks" (MERGE into
existing arrays, don't replace them):
  "SessionStart":     [{ "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP_PRE/caveman/hooks/caveman-activate.js\"", "timeout": 5 }] }]
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "node \"$PACK_DIR_DISP_PRE/caveman/hooks/caveman-mode-tracker.js\"", "timeout": 5 }] }]
Without this, the default-mode config above is inert -- these two hooks are what
actually inject the ruleset and reinforce it every turn. Override anytime by
saying "stop caveman" / "normal mode" in chat, or editing $CAVEMAN_CONFIG_FILE.
EOF
fi

# --- 2. Statusline: dictated path, safe to copy directly ---
if [ "$DRY_RUN" -ne 1 ]; then
  mkdir -p "$CLAUDE_DIR"
fi
if [ ! -f "$CLAUDE_DIR/statusline.sh" ] || ! cmp -s "$REPO_DIR/statusline/statusline.sh" "$CLAUDE_DIR/statusline.sh"; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would install/update statusline.sh at $CLAUDE_DIR/statusline.sh"
  else
    cp "$REPO_DIR/statusline/statusline.sh" "$CLAUDE_DIR/statusline.sh"
    chmod +x "$CLAUDE_DIR/statusline.sh"
    echo "[claude-harness] statusline.sh installed/updated at $CLAUDE_DIR/statusline.sh"
  fi
else
  echo "[claude-harness] statusline.sh already up to date"
fi

CLAUDE_DIR_DISP="$(win_path "$CLAUDE_DIR")"
if [ -f "$CLAUDE_DIR/settings.json" ] && grep -q '"statusLine"' "$CLAUDE_DIR/settings.json"; then
  echo "[claude-harness] settings.json already has a statusLine block — leaving it alone"
else
  cat <<EOF
[claude-harness] settings.json has no statusLine block. Add manually (see statusline/README.md):
  "statusLine": { "type": "command", "command": "bash \"$CLAUDE_DIR_DISP/statusline.sh\"", "refreshInterval": 60 }
EOF
fi

# --- 3. Managed pointer block in CLAUDE.md (Claude Code's always-loaded file) ---
# Does NOT copy security-invariants.md verbatim: if your CLAUDE.md already has
# hand-written security rules, dedupe them against rules/security-invariants.md
# yourself first — this installer never overwrites your prose, only its own
# marked block.
# A run against a dirty tree stamps CLAUDE.md with a hash that predates
# whatever cp -r just copied a few lines below -- silently wrong provenance,
# not just imprecise (found on this exact repo: caveman/ and
# skills/manifest.yaml were both installed from an uncommitted worktree, then
# committed minutes later, leaving the stamped hash pointing at the prior
# commit). `git describe --dirty` alone isn't enough here -- it only inspects
# tracked-file diffs against the index, so a brand-new UNTRACKED file (e.g. a
# not-yet-`git add`ed skill under rules/ or skills/) would still get copied by
# cp -r while the stamp claims clean. --untracked-files=all catches both.
COMMIT="$(cd "$REPO_DIR" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$(cd "$REPO_DIR" && git status --porcelain --untracked-files=all 2>/dev/null)" ]; then
  COMMIT="${COMMIT}-dirty"
fi
BLOCK_FILE="$(mktemp)"
{
  echo "$MARKER_START"
  echo "## Claude Harness (installed from $REPO_DIR @ $COMMIT)"
  echo
  echo "- Security invariants (always-on, every session/surface — read this alongside this file): \`$PACK_DIR_DISP/rules/security-invariants.md\`"
  echo "- Engineering rules (YAGNI ladder, debugging, review, deps, perf, commit lifecycle): \`$PACK_DIR_DISP/rules/engineering.md\`"
  echo "- Design lane (triggered on UI/UX task shape): \`$PACK_DIR_DISP/rules/design-lane.md\`"
  echo "- Skills manifest (install/version source of truth): \`$PACK_DIR_DISP/skills/manifest.yaml\`"
  echo "- Communication default (caveman ultra, always-on unless you say \"stop caveman\"/\"normal mode\"): \`$PACK_DIR_DISP/caveman/skills/caveman/SKILL.md\`, config \`$CAVEMAN_CONFIG_FILE\`"
  echo "- $MEMORY_LINE"
  echo "- Workflow loop (Understand -> Plan -> Build -> Verify -> Security-if-needed): \`$PACK_DIR_DISP/WORKFLOW.md\`"
  echo "$MARKER_END"
} > "$BLOCK_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would write/update managed block in $CLAUDE_MD:"
  cat "$BLOCK_FILE"
else
  touch "$CLAUDE_MD"
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%Y%m%d%H%M%S)"

  if grep -qF "$MARKER_START" "$CLAUDE_MD"; then
    TMP="$(mktemp)"
    awk -v start="$MARKER_START" -v end="$MARKER_END" -v blockfile="$BLOCK_FILE" '
      $0 == start { while ((getline line < blockfile) > 0) print line; skip=1; next }
      $0 == end { skip=0; next }
      skip { next }
      { print }
    ' "$CLAUDE_MD" > "$TMP"
    mv "$TMP" "$CLAUDE_MD"
    echo "[claude-harness] updated managed block in $CLAUDE_MD"
  else
    { cat "$CLAUDE_MD"; echo; cat "$BLOCK_FILE"; } > "$CLAUDE_MD.new"
    mv "$CLAUDE_MD.new" "$CLAUDE_MD"
    echo "[claude-harness] appended managed block to $CLAUDE_MD"
  fi
fi
rm -f "$BLOCK_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] complete — nothing written. A real run would target pack: $PACK_DIR_DISP | Managed block: $(win_path "$CLAUDE_DIR")/CLAUDE.md"
else
  echo "[claude-harness] done. Pack: $PACK_DIR_DISP | Managed block: $(win_path "$CLAUDE_DIR")/CLAUDE.md"
fi

# --- 4. Onboarding proof: only for a real run that actually made one of the
# 2 real choices (--onboard, --with-memory-hooks, --caveman-mode) -- a plain
# `./install.sh` keeps its existing quiet output, unchanged. Skipped entirely
# under --dry-run: verify.js reads files this run deliberately never wrote,
# so running it here would fail against a pack that doesn't exist yet. ---
if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$ONBOARD_MODE" -eq 1 ] || [ "$WITH_MEMORY_HOOKS" -eq 1 ] || [ -n "$CAVEMAN_SEED_MODE" ]; then
    echo ""
    echo "[dry-run] a real run would now run onboarding/verify.js and print the first-light instructions"
  fi
elif [ "$ONBOARD_MODE" -eq 1 ] || [ "$WITH_MEMORY_HOOKS" -eq 1 ] || [ -n "$CAVEMAN_SEED_MODE" ]; then
  echo ""
  # `|| true`: verify.js exits nonzero on an unmet hard claim (missing/unwired
  # secret-guard, missing ponytail) so scripts can branch on it -- but here it
  # is a REPORT printed after install.sh has already told the user what to
  # paste. A first run legitimately ends with wiring not yet pasted, and
  # failing the whole install for that (under `set -e`) is wrong. Read the rows.
  node "$PACK_DIR/onboarding/verify.js" || true
  echo ""
  node -e '
    const steps = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    console.log("[claude-harness] first light: " + steps.firstLight.instructions);
  ' "$REPO_DIR_DISP/onboarding/steps.json"
fi
