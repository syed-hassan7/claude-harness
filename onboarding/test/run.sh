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
  # XDG_CONFIG_HOME must be sandboxed here too, not just for install.sh: verify.js
  # resolves caveman's config dir the same way install.sh does, so without it the
  # verifier reads the REAL ~/.config/caveman/config.json and reports the caveman
  # tier based on the dev machine's own state rather than the scratch install's --
  # green on a machine that happens to have caveman configured, 'missing' anywhere
  # else (CI included). Same reason the header comment gives for run_install.
  CLAUDE_HARNESS_TARGET="$1" XDG_CONFIG_HOME="$2" node "$1/claude-harness/onboarding/verify.js" --json
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

echo ""
echo "ALL $PASS_COUNT CHECKS PASSED"
