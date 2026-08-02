#!/usr/bin/env bash
# Regression test for the jq-missing fallback fix (2026-08-02). Run from
# anywhere: bash statusline/test.sh
#
# Previously: no jq on PATH -> the script hit a hardcoded fallback to one
# specific machine's WinGet jq.exe path; on any other machine, jq calls
# failed silently and the script printed a statusline built from empty
# variables -- e.g. "Context Window: 0%", which reads as a real measurement,
# not an error.
# Now: no jq on PATH -> one honest line, exit 0, nothing that looks like data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.sh"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

PAYLOAD='{"model":{"display_name":"Sonnet 5"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":40000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":23000}},"cwd":"/tmp","session":{"start_time":"2026-08-02T19:00:00Z"}}'

echo "=== Test: jq absent from PATH -> honest error, not fabricated-looking data ==="
# Scrub PATH down to just what's needed to run bash itself, guaranteeing jq
# (and its hardcoded-fallback replacement, now removed from the script
# anyway) cannot be found.
OUT=$(echo "$PAYLOAD" | PATH="/usr/bin:/bin" bash "$STATUSLINE" 2>"$SCRIPT_DIR/.test-stderr")
CODE=$?
ERR=$(cat "$SCRIPT_DIR/.test-stderr")
rm -f "$SCRIPT_DIR/.test-stderr"

[ "$CODE" -eq 0 ] || fail "exited nonzero ($CODE) with jq absent -- must fail open"
echo "$OUT" | grep -q "jq not found" || fail "expected an explicit jq-not-found message, got: $OUT"
echo "$OUT" | grep -q "Context Window" && fail "produced statusline-shaped output despite jq being absent -- this is the exact bug (fabricated-looking data, e.g. a false '0%') that was fixed" || true
[ -z "$ERR" ] && pass "jq absent: clean one-line message, exit 0, no stray stderr, no fabricated statusline fields" || fail "unexpected stderr output: $ERR"

echo ""
echo "=== Test: empty stdin still handled (pre-existing behavior, must not regress) ==="
OUT2=$(echo "" | bash "$STATUSLINE")
[ "$OUT2" = "Claude" ] || fail "expected 'Claude' fallback on empty stdin, got: $OUT2"
pass "empty stdin still falls back to plain 'Claude'"

echo ""
echo "ALL CHECKS PASSED"
