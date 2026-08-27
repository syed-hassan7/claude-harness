#!/usr/bin/env bash
# Test suite for onboarding/ + install.sh's --onboard/--caveman-mode surface.
# Run from anywhere: bash onboarding/test/run.sh
#
# Every invocation below sandboxes BOTH CLAUDE_HARNESS_TARGET (pack/settings
# location, same override install.sh already supports) AND XDG_CONFIG_HOME
# (caveman's config dir, checked first in install.sh's own resolution order,
# ahead of APPDATA/~/.config) -- without the second override, a run on a
# machine that already has a real caveman config (this dev machine does) would
# silently no-op the seed-a-fresh-config assertions instead of actually
# testing them.
#
# Tests 1-5 drive the real install.sh; tests 6+ drive onboarding/verify.js
# directly against fabricated pack dirs, because the install-driven tests can
# only ever reach the tier states install.sh itself produces on a clean
# scratch dir -- every 'ok' branch, the not-installed branch, and the
# human-readable renderer were unreachable that way (0 direct coverage).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -d /c ] && [ "$(cd /c && pwd -W 2>/dev/null)" = "C:/" ]; then
  WORK="/c/ch-onboard-test-$$-$RANDOM"
  mkdir -p "$WORK"
else
  WORK=$(mktemp -d)
fi
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

run_install() {
  # run_install <target> <cfg_home> <args...>
  local target="$1" cfg="$2"
  shift 2
  (cd "$REPO_DIR" && CLAUDE_HARNESS_TARGET="$target" XDG_CONFIG_HOME="$cfg" bash install.sh "$@")
}

run_verify_json() {
  # run_verify_json <target> <cfg_home>
  # verify.js resolves caveman's config dir from XDG_CONFIG_HOME/APPDATA the
  # same way install.sh does, so the sandbox has to cover BOTH sides of the
  # check -- without it the verifier reads this machine's real caveman config
  # (or lack of one) and reports a tier state the install under test never
  # produced, which is the drift the suite's own header warns about.
  CLAUDE_HARNESS_TARGET="$1" XDG_CONFIG_HOME="$2" APPDATA="$2" \
    node "$1/claude-harness/onboarding/verify.js" --json
}

run_verify_repo() {
  # run_verify_repo <target> <cfg_home> [args...] -- same sandboxing, but runs
  # the in-repo verify.js against a fabricated target dir, so a test does not
  # have to install a whole pack just to reach one tier state.
  local target="$1" cfg="$2"
  shift 2
  CLAUDE_HARNESS_TARGET="$target" XDG_CONFIG_HOME="$cfg" APPDATA="$cfg" \
    node "$REPO_DIR/onboarding/verify.js" "$@"
}

echo "=== Test 1: non-interactive flags -- always-on ok, caveman/memory pending-manual-paste (no settings.json in scratch) ==="
T1="$WORK/t1_target"
C1="$WORK/t1_config"
mkdir -p "$T1" "$C1"
run_install "$T1" "$C1" --with-memory-hooks --caveman-mode=lite > "$WORK/t1.out" 2>&1 || fail "install.sh exited nonzero: $(cat "$WORK/t1.out")"
OUT=$(run_verify_json "$T1" "$C1")
echo "$OUT" | grep -q '"tier":"always-on","status":"ok"' || fail "expected always-on ok, got: $OUT"
echo "$OUT" | grep -q '"tier":"caveman","status":"pending-manual-paste"' || fail "expected caveman pending-manual-paste, got: $OUT"
echo "$OUT" | grep -q '"tier":"memory-hooks","status":"pending-manual-paste"' || fail "expected memory-hooks pending-manual-paste, got: $OUT"
pass "non-interactive flags: always-on ok, caveman + memory-hooks pending-manual-paste"

echo "=== Test 2: --caveman-mode=lite actually seeds a fresh config with defaultMode lite ==="
CFG_FILE="$C1/caveman/config.json"
[ -f "$CFG_FILE" ] || fail "caveman config.json not created at $CFG_FILE"
grep -q '"defaultMode": "lite"' "$CFG_FILE" || fail "expected defaultMode lite in fresh config, got: $(cat "$CFG_FILE")"
pass "fresh caveman config seeded with the requested mode"

echo "=== Test 3: --onboard (piped answers) converges on the same outcome as the flags path ==="
T3="$WORK/t3_target"
C3="$WORK/t3_config"
mkdir -p "$T3" "$C3"
printf 'y\nlite\n' | (cd "$REPO_DIR" && CLAUDE_HARNESS_TARGET="$T3" XDG_CONFIG_HOME="$C3" bash install.sh --onboard) > "$WORK/t3.out" 2>&1 \
  || fail "install.sh --onboard exited nonzero: $(cat "$WORK/t3.out")"
OUT3=$(run_verify_json "$T3" "$C3")
echo "$OUT3" | grep -q '"tier":"always-on","status":"ok"' || fail "onboard path: expected always-on ok, got: $OUT3"
echo "$OUT3" | grep -q '"tier":"memory-hooks","status":"pending-manual-paste"' || fail "onboard path: expected memory-hooks pending-manual-paste (i.e. the 'y' answer was honored), got: $OUT3"
grep -q '"defaultMode": "lite"' "$C3/caveman/config.json" || fail "onboard path: expected defaultMode lite (i.e. the 'lite' answer was honored)"
pass "--onboard's piped answers produce the same result as the equivalent flags"

echo "=== Test 4: --caveman-mode never overwrites an EXISTING config (same idempotence rule as the rest of install.sh) ==="
T4="$WORK/t4_target"
C4="$WORK/t4_config"
mkdir -p "$T4" "$C4/caveman"
echo '{ "defaultMode": "full" }' > "$C4/caveman/config.json"
run_install "$T4" "$C4" --caveman-mode=off > "$WORK/t4.out" 2>&1 || fail "install.sh exited nonzero: $(cat "$WORK/t4.out")"
grep -q '"defaultMode": "full"' "$C4/caveman/config.json" || fail "existing config was overwritten -- expected 'full' to survive, got: $(cat "$C4/caveman/config.json")"
pass "existing caveman config left untouched despite a different --caveman-mode"

echo "=== Test 5: invalid --caveman-mode value is rejected, falls back to ultra, does not crash ==="
T5="$WORK/t5_target"
C5="$WORK/t5_config"
mkdir -p "$T5" "$C5"
run_install "$T5" "$C5" --caveman-mode=bogus > "$WORK/t5.out" 2>&1 || fail "install.sh exited nonzero on invalid --caveman-mode: $(cat "$WORK/t5.out")"
grep -q "invalid --caveman-mode" "$WORK/t5.out" || fail "expected a warning about the invalid mode, got: $(cat "$WORK/t5.out")"
grep -q '"defaultMode": "ultra"' "$C5/caveman/config.json" || fail "expected fallback to ultra, got: $(cat "$C5/caveman/config.json")"
pass "invalid --caveman-mode warns and falls back to ultra instead of crashing"

# ---------------------------------------------------------------------------
# verify.js against fabricated pack dirs (no install.sh in the loop)
# ---------------------------------------------------------------------------
#
# fake_pack <target> <cfg_home> <tiers...> -- builds a pack tree under
# <target>/claude-harness containing only the requested tiers. Tiers:
#   always-on   rules/ + skills/manifest.yaml
#   caveman     caveman/ + a config.json with defaultMode
#   memory      memory/hooks/
fake_pack() {
  local target="$1" cfg="$2"
  shift 2
  local pack="$target/claude-harness"
  mkdir -p "$pack" "$cfg"
  for tier in "$@"; do
    case "$tier" in
      always-on)
        mkdir -p "$pack/rules" "$pack/skills"
        : > "$pack/skills/manifest.yaml"
        ;;
      caveman)
        mkdir -p "$pack/caveman" "$cfg/caveman"
        printf '{ "defaultMode": "ultra" }' > "$cfg/caveman/config.json"
        ;;
      memory) mkdir -p "$pack/memory/hooks" ;;
      *) fail "fake_pack: unknown tier '$tier'" ;;
    esac
  done
}

# tier_status <json> <tier> -- prints the status reported for one tier.
tier_status() {
  printf '%s' "$1" | node -e '
    let s = "";
    process.stdin.on("data", c => { s += c; });
    process.stdin.on("end", () => {
      const hit = JSON.parse(s).find(r => r.tier === process.argv[1]);
      process.stdout.write(hit ? hit.status : "<no such tier>");
    });
  ' "$2"
}

expect_status() {
  # expect_status <json> <tier> <expected>
  local got
  got=$(tier_status "$1" "$2")
  [ "$got" = "$3" ] || fail "expected $2 status '$3', got '$got' -- full report: $1"
}

echo "=== Test 6: a fully installed + fully wired pack reports every tier ok ==="
T6="$WORK/t6_target"
C6="$WORK/t6_config"
fake_pack "$T6" "$C6" always-on caveman memory
cat > "$T6/settings.json" <<'JSON'
{
  "enabledPlugins": { "ponytail@ponytail": true },
  "hooks": { "SessionStart": "caveman-activate.js", "SessionEnd": "memory-init.js" }
}
JSON
OUT6=$(run_verify_repo "$T6" "$C6" --json)
for tier in always-on ponytail caveman memory-hooks; do
  expect_status "$OUT6" "$tier" ok
done
pass "a fully installed and wired pack reports ok for all four tiers"

echo "=== Test 7: files present but settings.json unwired is 'pending-manual-paste', not 'ok' ==="
T7="$WORK/t7_target"
C7="$WORK/t7_config"
fake_pack "$T7" "$C7" always-on caveman memory
printf '{}' > "$T7/settings.json"
OUT7=$(run_verify_repo "$T7" "$C7" --json)
expect_status "$OUT7" always-on ok
expect_status "$OUT7" caveman pending-manual-paste
expect_status "$OUT7" memory-hooks pending-manual-paste
expect_status "$OUT7" ponytail missing
pass "an unwired settings.json downgrades caveman + memory-hooks to pending-manual-paste and ponytail to missing"

echo "=== Test 8: a missing rules/ or skills/manifest.yaml makes always-on 'missing' and names what is gone ==="
T8="$WORK/t8_target"
C8="$WORK/t8_config"
fake_pack "$T8" "$C8" caveman
OUT8=$(run_verify_repo "$T8" "$C8" --json)
expect_status "$OUT8" always-on missing
echo "$OUT8" | grep -q 'rules/' || fail "expected the detail to name the missing rules/ dir, got: $OUT8"
echo "$OUT8" | grep -q 'skills/manifest.yaml' || fail "expected the detail to name the missing manifest, got: $OUT8"
pass "always-on reports missing and enumerates both absent paths"

echo "=== Test 9: opted-out memory hooks are 'not-installed' -- absence of an opt-in tier is not a failure ==="
T9="$WORK/t9_target"
C9="$WORK/t9_config"
fake_pack "$T9" "$C9" always-on caveman
OUT9=$(run_verify_repo "$T9" "$C9" --json)
expect_status "$OUT9" memory-hooks not-installed
echo "$OUT9" | grep -q -- '--with-memory-hooks' || fail "expected the detail to point at the opt-in flag, got: $OUT9"
pass "an absent memory/hooks reports not-installed with the opt-in flag as remediation"

echo "=== Test 10: caveman distinguishes 'not installed' from 'installed but unconfigured' ==="
T10="$WORK/t10_target"
C10="$WORK/t10_config"
fake_pack "$T10" "$C10" always-on
OUT10=$(run_verify_repo "$T10" "$C10" --json)
expect_status "$OUT10" caveman missing
echo "$OUT10" | grep -q 'caveman/ not installed' || fail "expected the 'not installed' detail, got: $OUT10"
mkdir -p "$T10/claude-harness/caveman"
OUT10B=$(run_verify_repo "$T10" "$C10" --json)
expect_status "$OUT10B" caveman missing
echo "$OUT10B" | grep -q 'config missing defaultMode' || fail "expected the 'unconfigured' detail once caveman/ exists, got: $OUT10B"
mkdir -p "$C10/caveman"
printf '{ "defaultMode": "lite" }' > "$C10/caveman/config.json"
OUT10C=$(run_verify_repo "$T10" "$C10" --json)
expect_status "$OUT10C" caveman pending-manual-paste
pass "caveman's three pre-wiring states (absent / unconfigured / configured) are reported distinctly"

echo "=== Test 11: the default (non---json) rendering prints one labeled line per tier ==="
OUT11=$(run_verify_repo "$T6" "$C6")
echo "$OUT11" | grep -q 'onboarding verify:' || fail "expected the human-readable header, got: $OUT11"
for tier in always-on ponytail caveman memory-hooks; do
  echo "$OUT11" | grep -q "$tier" || fail "expected a line for the $tier tier, got: $OUT11"
done
[ "$(printf '%s\n' "$OUT11" | grep -c '✓')" = "4" ] || fail "expected an ok icon on all four tier lines, got: $OUT11"
pass "the human-readable renderer prints a header plus one status line per tier"

echo ""
echo "ALL $PASS_COUNT CHECKS PASSED"
