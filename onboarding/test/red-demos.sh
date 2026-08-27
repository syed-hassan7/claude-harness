#!/usr/bin/env bash
# RED demos for onboarding/verify.js.
#
# WHY THIS FILE EXISTS. `verify.js` reported all-green while four separate
# findings of the 2026-08-27 external audit were live -- including this pack's
# only always-on engineering skill not being installed at all. A checker that
# has never been shown FAILING has not been shown working; its green is
# indistinguishable from a green stub.
#
# So: every claim verify.js makes gets deliberately broken here, one at a time,
# against a throwaway fake install, and this suite asserts verify.js reports
# that specific breakage. Then it asserts the unbroken sandbox comes back GREEN,
# so the suite can't pass by verify.js simply always failing.
#
# Fully sandboxed via CLAUDE_HARNESS_TARGET + CLAUDE_HARNESS_HOME_OVERRIDE.
# Touches no real settings.json, no real ~/.claude, no live session state.
#
#   bash onboarding/test/red-demos.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$REPO/onboarding/verify.js"

if [ -d /c ]; then WORK="/c/ch-red-$$-$RANDOM"; mkdir -p "$WORK"; else WORK=$(mktemp -d); fi
trap 'rm -rf "$WORK"' EXIT

win_path() {
  local p="$1" w
  w=$(cd "$p" 2>/dev/null && pwd -W 2>/dev/null) || true
  if [ -n "$w" ]; then echo "$w"; else echo "$p"; fi
}

PASS_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# ── build a fake, fully-healthy install we can then damage ───────────────────
HOME_POSIX="$WORK/home"
TARGET_POSIX="$HOME_POSIX/.claude"
PACK_POSIX="$TARGET_POSIX/claude-harness"
mkdir -p "$PACK_POSIX/rules" "$PACK_POSIX/skills" "$PACK_POSIX/caveman" \
         "$PACK_POSIX/memory/hooks" "$TARGET_POSIX/hooks" "$WORK/cfg/caveman"
: > "$PACK_POSIX/skills/manifest.yaml"
cp "$REPO/security/hooks/secret-guard.js" "$TARGET_POSIX/hooks/secret-guard.js"
cp "$REPO/memory/hooks/"*.js "$PACK_POSIX/memory/hooks/"
cp "$REPO/caveman/hooks/"*.js "$PACK_POSIX/caveman/" 2>/dev/null || true
echo '{"defaultMode":"ultra"}' > "$WORK/cfg/caveman/config.json"
echo "ultra" > "$TARGET_POSIX/.caveman-active"

HOME_WIN=$(win_path "$HOME_POSIX")
TARGET_WIN=$(win_path "$TARGET_POSIX")
PACK_WIN=$(win_path "$PACK_POSIX")

SESSION="redDemoSession"

# a healthy settings.json mirroring what install.sh prints
write_settings() {
  node -e '
const fs = require("fs"), pack = process.argv[1], target = process.argv[2];
const n = (rel) => ({ type: "command", command: `node "${pack}/${rel}"`, timeout: 5 });
const guard = { type: "command", command: `node "${target}/hooks/secret-guard.js"`, timeout: 5 };
fs.writeFileSync(process.argv[3], JSON.stringify({
  enabledPlugins: { "ponytail@ponytail": true, "coderabbit@claude-plugins-official": true },
  hooks: {
    SessionStart: [{ hooks: [n("caveman/caveman-activate.js")] }, { hooks: [n("memory/hooks/memory-init.js")] }],
    UserPromptSubmit: [
      { hooks: [n("caveman/caveman-mode-tracker.js")] },
      { hooks: [n("memory/hooks/memory-recall.js")] },
      { hooks: [n("memory/hooks/canary-check.js")] },
      { hooks: [n("memory/hooks/review-gate-check.js")] },
      { hooks: [n("memory/hooks/design-lane-gate-check.js")] },
      { hooks: [n("memory/hooks/visual-plan-gate-check.js")] },
    ],
    PreToolUse: [{ matcher: "Edit|Write", hooks: [guard] }],
    PostToolUse: [
      { matcher: "Edit|Write", hooks: [n("memory/hooks/memory-checkpoint.js")] },
      { matcher: "Read|Edit|Write", hooks: [n("memory/hooks/memory-architecture.js")] },
      { matcher: "Bash|Skill|Agent", hooks: [n("memory/hooks/review-gate-check.js")] },
      { matcher: "Edit|Write|Read|Bash|mcp__playwright.*", hooks: [n("memory/hooks/design-lane-gate-check.js")] },
      { matcher: "Edit|Write|ExitPlanMode|Artifact", hooks: [n("memory/hooks/visual-plan-gate-check.js")] },
    ],
    PreCompact: [{ hooks: [n("memory/hooks/memory-compact.js")] }],
    SessionEnd: [{ hooks: [n("memory/hooks/memory-flush.js")] }],
  },
}, null, 1));
' "$PACK_WIN" "$TARGET_WIN" "$TARGET_POSIX/settings.json"
}

# fake "these hooks ran this session" state, as the real gates would write it
write_live_state() {
  local now
  now=$(node -e "console.log(new Date().toISOString())")
  for g in canary review-gate design-lane-gate visual-plan-gate; do
    mkdir -p "$TARGET_POSIX/$g"
    node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({'$SESSION':{lastSeen:'$now'}}))" "$TARGET_POSIX/$g/state.json"
  done
  mkdir -p "$TARGET_POSIX/session"
  printf '# Session checkpoint\nsession_id: %s\n' "$SESSION" > "$TARGET_POSIX/session/checkpoint.md"
  node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({'$SESSION':{scope:'global',base:process.argv[2],repo:null,at:'$now'}}))" \
    "$TARGET_POSIX/session-scope.json" "$TARGET_WIN"
}

# Full restore, not partial: an earlier demo may have deleted a hook file or
# neutered the guard, and a half-reset sandbox makes every later demo assert
# against leftover damage instead of the break it actually introduced.
reset_sandbox() {
  cp "$REPO/memory/hooks/"*.js "$PACK_POSIX/memory/hooks/"
  cp "$REPO/security/hooks/secret-guard.js" "$TARGET_POSIX/hooks/secret-guard.js"
  write_settings
  write_live_state
  echo "ultra" > "$TARGET_POSIX/.caveman-active"
}

run_verify() {
  CLAUDE_HARNESS_TARGET="$TARGET_WIN" CLAUDE_HARNESS_HOME_OVERRIDE="$HOME_WIN" \
    XDG_CONFIG_HOME="$(win_path "$WORK/cfg")" APPDATA="" \
    node "$VERIFY" --live 2>&1 || true
}
run_verify_json() {
  CLAUDE_HARNESS_TARGET="$TARGET_WIN" CLAUDE_HARNESS_HOME_OVERRIDE="$HOME_WIN" \
    XDG_CONFIG_HOME="$(win_path "$WORK/cfg")" APPDATA="" \
    node "$VERIFY" --live --json 2>/dev/null || true
}

# Assertions run against --json STATUS FIELDS, never against report prose.
# Learned the hard way while writing this file: an early version grepped the
# human output for "secret-guard" / "ponytail" / "stale" -- all of which appear
# in a fully GREEN report too (a tier name, and the phrase "flagging a note
# stale"). Those demos would have passed no matter what verify.js did. That is
# the same happy-path-fixture mistake this whole overhaul exists to eliminate,
# reproduced inside its own test harness.
#
#   expect_status  <tier>            <wanted status>
#   expect_row     <row-name substr> <wanted status>
expect_status() {
  local tier="$1" want="$2" label="$3" got
  got=$(run_verify_json | node -e '
let raw="";process.stdin.on("data",d=>raw+=d).on("end",()=>{
  const r=JSON.parse(raw).find(x=>x.tier===process.argv[1]);
  console.log(r?r.status:"TIER-ABSENT");});' "$tier")
  [ "$got" = "$want" ] || fail "$label -- tier '$tier' status was '$got', wanted '$want'
$(run_verify)"
  pass "$label"
}
# Rows MUST be scoped to a tier: several row names appear in more than one tier
# (e.g. "canary-check.js" is both a `wiring` row and a `live` row), so an
# unscoped match silently asserts against whichever tier happens to come first.
#   expect_row <tier> <row-name substr> <wanted status> <label>
expect_row() {
  local tier="$1" needle="$2" want="$3" label="$4" got
  got=$(run_verify_json | node -e '
let raw="";process.stdin.on("data",d=>raw+=d).on("end",()=>{
  const t=JSON.parse(raw).find(x=>x.tier===process.argv[1]);
  if(!t) return console.log("TIER-ABSENT");
  const hit=(t.rows||[]).find(r=>String(r[0]).includes(process.argv[2]));
  console.log(hit?hit[1]:"ROW-ABSENT");});' "$tier" "$needle")
  [ "$got" = "$want" ] || fail "$label -- $tier row matching '$needle' had status '$got', wanted '$want'
$(run_verify)"
  pass "$label"
}
# every tier ok, and no row in a non-ok state
assert_green() {
  local label="$1" bad
  bad=$(run_verify_json | node -e '
let raw="";process.stdin.on("data",d=>raw+=d).on("end",()=>{
  const rs=JSON.parse(raw);
  const badTiers=rs.filter(r=>r.status!=="ok").map(r=>`tier:${r.tier}=${r.status}`);
  const OK=["ok","opted-out","unprovable","not-exercised"];
  const badRows=rs.flatMap(r=>r.rows||[]).filter(r=>!OK.includes(r[1])).map(r=>`row:${r[0]}=${r[1]}`);
  console.log([...badTiers,...badRows].join(", "));});')
  [ -z "$bad" ] || fail "$label -- expected all-green, got: $bad
$(run_verify)"
  pass "$label"
}

echo "############ baseline: an intact sandbox must be GREEN ############"
reset_sandbox
assert_green "intact sandbox reports green (so the RED demos below prove something)"

echo
echo "############ RED 1: a hook is wired NOWHERE (the 6.3.0 dead-hook bug) ############"
reset_sandbox
node -e '
const fs=require("fs"),p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
s.hooks.UserPromptSubmit=s.hooks.UserPromptSubmit.filter(e=>!JSON.stringify(e).includes("canary-check.js"));
fs.writeFileSync(p,JSON.stringify(s,null,1));' "$TARGET_POSIX/settings.json"
expect_row "wiring" "canary-check.js" "UNWIRED" "unwired hook detected (canary-check.js removed from UserPromptSubmit)"
expect_status "wiring" "BROKEN" "  ...and the wiring tier itself reports BROKEN"

echo
echo "############ RED 2: STALE MATCHER (the exact 6.4.0 upgrade bug) ############"
reset_sandbox
node -e '
const fs=require("fs"),p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
for(const e of s.hooks.PostToolUse) if(JSON.stringify(e).includes("review-gate-check.js")) e.matcher="Bash";
fs.writeFileSync(p,JSON.stringify(s,null,1));' "$TARGET_POSIX/settings.json"
expect_row "wiring" "PostToolUse:review-gate-check.js" "STALE MATCHER" "stale matcher detected (review-gate rolled back to pre-6.4.0 Bash-only)"

echo
echo "############ RED 3: wired to a file that does not exist ############"
reset_sandbox
rm -f "$PACK_POSIX/memory/hooks/visual-plan-gate-check.js"
expect_row "wiring" "visual-plan-gate-check.js" "MISSING FILE" "settings.json pointing at a deleted hook file detected"

echo
echo "############ RED 3b: same, but the command has NO surrounding quotes ############"
# A hand-edited settings.json entry with an unquoted command (valid shell --
# `node /home/u/.../hook.js`, no spaces) previously extracted a null path via
# a "first quoted span" regex and silently skipped the missing-file check
# entirely -- a false green in the one tier whose job is catching this.
reset_sandbox
rm -f "$PACK_POSIX/memory/hooks/visual-plan-gate-check.js"
node -e '
const fs=require("fs"),p=process.argv[1],pack=process.argv[2];
const s=JSON.parse(fs.readFileSync(p,"utf8"));
for(const e of s.hooks.PostToolUse) if(JSON.stringify(e).includes("visual-plan-gate-check.js"))
  for(const h of e.hooks) if(h.command.includes("visual-plan-gate-check.js"))
    h.command = `node ${pack}/memory/hooks/visual-plan-gate-check.js`; // unquoted
fs.writeFileSync(p,JSON.stringify(s,null,1));' "$TARGET_POSIX/settings.json" "$PACK_WIN"
expect_row "wiring" "visual-plan-gate-check.js" "MISSING FILE" "unquoted command pointing at a deleted hook file still detected"

echo
echo "############ RED 4: secret-guard NOT INSTALLED (the off-inventory finding) ############"
reset_sandbox
rm -f "$TARGET_POSIX/hooks/secret-guard.js"
expect_status "secret-guard" "missing" "missing Tier 0 secret backstop detected"

echo
echo "############ RED 5: secret-guard PRESENT BUT NOT BLOCKING (worse than absent) ############"
reset_sandbox
printf '#!/usr/bin/env node\nprocess.exit(0); // neutered: never blocks anything\n' > "$TARGET_POSIX/hooks/secret-guard.js"
expect_status "secret-guard" "BROKEN" "a present-but-non-blocking secret guard detected by live smoke test"

echo
echo "############ RED 5b: secret-guard present + functional but WIRED NOWHERE ############"
# The more deceptive half of the Tier 0 failure: the file is on disk and passes
# its own smoke test, but settings.json never names it, so Claude Code never
# invokes it. File-presence checking alone reports this as healthy.
reset_sandbox
node -e '
const fs=require("fs"),p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
delete s.hooks.PreToolUse;
fs.writeFileSync(p,JSON.stringify(s,null,1));' "$TARGET_POSIX/settings.json"
expect_status "secret-guard" "BROKEN" "installed-but-unwired secret guard detected (not reported as ok)"

echo
echo "############ RED 6: ponytail (required:true) not enabled -- audit finding #11 ############"
reset_sandbox
node -e '
const fs=require("fs"),p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
delete s.enabledPlugins["ponytail@ponytail"];
fs.writeFileSync(p,JSON.stringify(s,null,1));' "$TARGET_POSIX/settings.json"
expect_status "ponytail" "missing" "ponytail not installed detected (the gap verify.js used to report green through)"

echo
echo "############ RED 7: caveman flag killed mid-session -- audit finding #9/#10 ############"
reset_sandbox
rm -f "$TARGET_POSIX/.caveman-active"
expect_row "live" "caveman flag" "DEAD" "silently-deactivated caveman detected as DEAD, not as not-yet-exercised"

echo
echo "############ RED 8: hook wired + present, but never ACTUALLY RAN this session ############"
# The failure mode no static check can see, and the whole reason --live exists:
# every file present, every matcher current, and the hook still never executed
# (syntax error, wrong node, crashed on load, event never delivered).
reset_sandbox
node -e "require('fs').writeFileSync(process.argv[1], JSON.stringify({}))" "$TARGET_POSIX/canary/state.json"
expect_row "live" "canary-check.js" "DEAD" "a wired, present, current-matcher hook that never executed detected as DEAD"
expect_status "live" "BROKEN" "  ...and the live tier itself reports BROKEN"

echo
echo "############ closing baseline: restore -> GREEN again ############"
reset_sandbox
assert_green "sandbox returns to green after every break is undone (verify.js is not simply always-red)"

echo
echo "ALL $PASS_COUNT RED DEMOS PASSED — every check verify.js makes has been shown failing"
