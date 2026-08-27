#!/usr/bin/env bash
# Test suite for caveman/hooks/caveman-mode-tracker.js's deactivation filter.
# Zero coverage existed before 2026-08-27 (see skills/manifest.yaml drift
# audit + memory/SPEC.md's review-gate section for the sibling fix this
# mirrors) -- this file exists specifically to cover the two directions that
# matter: a real "stop caveman"/"normal mode" directive must still kill the
# flag, and a quoted/negated MENTION of the phrase must not.
#
# Run from anywhere: bash caveman/hooks/test/run.sh
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

win_path() {
  local p="$1" w
  w=$(cd "$p" 2>/dev/null && pwd -W 2>/dev/null) || true
  if [ -n "$w" ]; then echo "$w"; else echo "$p"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAKE_HOME="$(win_path "$WORK")"
FLAG_FILE="$WORK/.claude/.caveman-active"

PASS_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# run_tracker <prompt-json-string> -- primes the flag to "ultra" first,
# invokes caveman-mode-tracker.js with USERPROFILE/HOME pointed at the
# scratch dir (Node's os.homedir() honors both -- confirmed directly on this
# platform), returns whether the flag file still exists afterward.
run_tracker() {
  local prompt="$1"
  mkdir -p "$WORK/.claude"
  printf 'ultra' > "$FLAG_FILE"
  printf '{"prompt":"%s"}' "$prompt" | USERPROFILE="$FAKE_HOME" HOME="$FAKE_HOME" node "$HOOKS/caveman-mode-tracker.js" > /dev/null
}

echo "=== Test 1: a bare 'stop caveman' directive kills the flag ==="
run_tracker "stop caveman"
[ -f "$FLAG_FILE" ] && fail "flag should be removed after a real 'stop caveman' directive"
pass "bare 'stop caveman' directive removes the flag"

echo "=== Test 2: a bare 'normal mode' directive kills the flag ==="
run_tracker "ok let's switch to normal mode now"
[ -f "$FLAG_FILE" ] && fail "flag should be removed after a real 'normal mode' directive"
pass "'normal mode' directive removes the flag"

echo "=== Test 3: REGRESSION -- a double-quoted MENTION of the phrase must NOT kill the flag ==="
run_tracker "Try to get caveman-ultra to lapse without saying \\\"stop caveman\\\" -- long session, security-adjacent topic."
[ -f "$FLAG_FILE" ] || fail "flag should survive a quoted mention of 'stop caveman' inside a negated sentence"
pass "quoted mention of 'stop caveman' inside a negated sentence does not kill the flag"

echo "=== Test 4: REGRESSION -- grepping for the phrase in quotes must NOT kill the flag ==="
run_tracker "grep -n \\\"normal mode\\\" ./docs/*.md"
[ -f "$FLAG_FILE" ] || fail "flag should survive a quoted grep pattern containing 'normal mode'"
pass "quoted grep pattern containing 'normal mode' does not kill the flag"

echo "=== Test 5: an unquoted but negated mention must NOT kill the flag ==="
run_tracker "I don't want to say normal mode right now, keep going as-is"
[ -f "$FLAG_FILE" ] || fail "flag should survive an unquoted negated mention of 'normal mode'"
pass "unquoted negated mention of 'normal mode' does not kill the flag"

echo "=== Test 6: a real directive still works even mid-sentence, after unrelated quoted text ==="
run_tracker "That last commit message was \\\"fix bug\\\", anyway stop caveman please"
[ -f "$FLAG_FILE" ] && fail "flag should be removed -- the directive itself is unquoted and unnegated, only unrelated text was quoted"
pass "a real unquoted directive still fires even when unrelated quoted text precedes it"

echo "=== Test 7: a real directive still works after an UNRELATED negation earlier in the same sentence, across a comma ==="
run_tracker "The bug is not fixed yet, stop caveman"
[ -f "$FLAG_FILE" ] && fail "flag should be removed -- 'not' belongs to an earlier clause (before the comma), not the directive itself"
pass "an unrelated negation word in an earlier comma-separated clause does not veto a real trailing directive"

echo "=== Test 8: REGRESSION -- a real directive bracketed by ordinary CONTRACTIONS on both sides must still fire ==="
run_tracker "let's stop caveman, and don't forget it's done"
[ -f "$FLAG_FILE" ] && fail "flag should be removed -- naive single-quote stripping paired the apostrophes in let's/don't as a quote span and ate the directive between them"
pass "contractions bracketing a real directive do not get mistaken for a quoted span"

echo "=== Test 9: a genuine single-quoted mention of the phrase still does not kill the flag ==="
run_tracker "he said 'stop caveman' is what I must avoid saying"
[ -f "$FLAG_FILE" ] || fail "flag should survive a genuine single-quoted mention of 'stop caveman'"
pass "a genuine single-quoted mention (bounded by whitespace/punctuation, not a contraction) still does not kill the flag"

echo "=== Test 10: REGRESSION -- an earlier NEGATED mention must not veto a LATER real, unnegated occurrence ==="
run_tracker "don't stop caveman... actually, on second thought, stop caveman"
[ -f "$FLAG_FILE" ] && fail "flag should be removed -- the second occurrence is real and unnegated, only the first (checked-only-first, pre-fix) was negated"
pass "a later real, unnegated occurrence of the phrase fires even when an earlier occurrence was negated"

echo "=== Test 11: REGRESSION -- a genuine quoted mention that itself CONTAINS a contraction must still be stripped ==="
run_tracker "the docs say 'stop caveman, that's how you exit' somewhere"
[ -f "$FLAG_FILE" ] || fail "flag should survive -- this is a quoted mention, the interior apostrophe in 'that's' should not have aborted the strip"
pass "a genuine quoted span containing a contraction before its closing quote is still stripped, not left matching"

echo "=== Test 12: REGRESSION -- a genuine quoted mention with a possessive apostrophe must still be stripped ==="
run_tracker "quoting the user: 'please stop caveman for John's demo'"
[ -f "$FLAG_FILE" ] || fail "flag should survive -- this is a quoted mention, the possessive apostrophe in John's should not have aborted the strip"
pass "a genuine quoted span with a possessive apostrophe before its closing quote is still stripped"

echo ""
echo "ALL $PASS_COUNT CHECKS PASSED"

