#!/usr/bin/env bash
# Regression test for the jq-missing fallback fix (2026-08-02, two passes).
# Run from anywhere: bash statusline/test.sh
#
# Pass 1: no jq on PATH -> the script hit a hardcoded fallback to one
# specific machine's WinGet jq.exe path; on any other machine, jq calls
# failed silently and the script printed a statusline built from empty
# variables -- e.g. "Context Window: 0%", which reads as a real measurement,
# not an error. Fixed to: no jq anywhere -> one honest line, exit 0, nothing
# that looks like data.
#
# Pass 2: `winget install jq` was confirmed (2026-08-02) to not reliably add
# jq to PATH at all -- not a stale-shell caching issue, the PATH registry
# value itself never gained an entry. So the script now also searches
# %LOCALAPPDATA%\Microsoft\WinGet\Packages\jqlang.jq_*\jq.exe directly when
# PATH resolution fails, and must produce a real statusline (not the error
# message) when jq is only reachable that way.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.sh"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

PAYLOAD='{"model":{"display_name":"Sonnet 5"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":40000,"cache_creation_input_tokens":5000,"cache_read_input_tokens":23000}},"cwd":"/tmp","session":{"start_time":"2026-08-02T19:00:00Z"}}'

echo "=== Test: jq truly absent (PATH scrubbed, no WinGet fallback dir) -> honest error ==="
# Point HOME at an empty temp dir so the WinGet-package fallback search also
# finds nothing -- otherwise this test would pass or fail depending on
# whether the machine running it happens to have jq installed via winget,
# which defeats the point.
FAKE_HOME="$SCRIPT_DIR/.test-fake-home"
mkdir -p "$FAKE_HOME"
# Scrub jq out of PATH -- NOT by hardcoding a minimal PATH string. A fixed
# "/usr/bin:/bin" was tried first and passed on this dev machine, then failed
# outright on GitHub's ubuntu-latest runner, which ships a real jq at
# /usr/bin/jq by default -- the hardcoded "minimal" PATH still had it. Filter
# the REAL PATH instead: drop every directory that itself contains an
# executable jq, keep everything else needed (date/git/stat/etc) intact. This
# is the one thing that's actually platform-agnostic about "jq is absent".
SCRUBBED_PATH=""
IFS=':' read -ra _path_dirs <<< "$PATH"
for _dir in "${_path_dirs[@]}"; do
  [ -x "$_dir/jq" ] && continue
  SCRUBBED_PATH="${SCRUBBED_PATH:+$SCRUBBED_PATH:}$_dir"
done
set +e
OUT=$(echo "$PAYLOAD" | PATH="$SCRUBBED_PATH" HOME="$FAKE_HOME" LOCALAPPDATA="$(cygpath -w "$FAKE_HOME/AppData/Local" 2>/dev/null)" bash "$STATUSLINE" 2>"$SCRIPT_DIR/.test-stderr")
CODE=$?
set -e
ERR=$(cat "$SCRIPT_DIR/.test-stderr")
rm -f "$SCRIPT_DIR/.test-stderr"
rmdir "$FAKE_HOME"

[ "$CODE" -eq 0 ] || fail "exited nonzero ($CODE) with jq absent -- must fail open"
echo "$OUT" | grep -q "jq not found" || fail "expected an explicit jq-not-found message, got: $OUT"
echo "$OUT" | grep -q "Context Window" && fail "produced statusline-shaped output despite jq being absent -- this is the exact bug (fabricated-looking data, e.g. a false '0%') that was fixed" || true
[ -z "$ERR" ] && pass "jq absent: clean one-line message, exit 0, no stray stderr, no fabricated statusline fields" || fail "unexpected stderr output: $ERR"

echo ""
echo "=== Test: jq absent from PATH but present under WinGet package dir -> fallback finds it ==="
# Fabricate a fake HOME with just enough of the WinGet package layout for the
# fallback's `find` to succeed, using the real system jq binary as the payload
# so the script's actual jq calls succeed too.
REAL_JQ="$(command -v jq || true)"
if [ -z "$REAL_JQ" ]; then
    # jq itself may not be on PATH (that's the bug this fallback works around) --
    # fall back further to whatever real jq.exe find can locate on this machine.
    REAL_JQ="$(find "$HOME/AppData/Local/Microsoft/WinGet/Packages" -maxdepth 1 -iname 'jqlang.jq_*' -exec test -x '{}/jq.exe' \; -print 2>/dev/null | head -n1)"
    [ -n "$REAL_JQ" ] && REAL_JQ="$REAL_JQ/jq.exe"
fi
if [ -z "$REAL_JQ" ]; then
    echo "SKIP: no real jq on this machine to use as the fallback's binary"
else
    FAKE_HOME="$SCRIPT_DIR/.test-fake-home-winget"
    PKG_DIR="$FAKE_HOME/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe"
    mkdir -p "$PKG_DIR"
    cp "$REAL_JQ" "$PKG_DIR/jq.exe"
    chmod +x "$PKG_DIR/jq.exe"

    OUT3=$(echo "$PAYLOAD" | PATH="/usr/bin:/bin" HOME="$FAKE_HOME" LOCALAPPDATA="$(cygpath -w "$FAKE_HOME/AppData/Local" 2>/dev/null)" bash "$STATUSLINE")
    rm -rf "$FAKE_HOME"

    echo "$OUT3" | grep -q "Context Window" || fail "expected a real statusline via WinGet-dir fallback, got: $OUT3"
    echo "$OUT3" | grep -q "jq not found" && fail "fallback should have found jq.exe under the fake WinGet package dir, but script still reported it missing" || true
    pass "jq absent from PATH but present under WinGet package dir: fallback locates and uses it"
fi

echo ""
echo "=== Test: empty stdin still handled (pre-existing behavior, must not regress) ==="
OUT2=$(echo "" | bash "$STATUSLINE")
[ "$OUT2" = "Claude" ] || fail "expected 'Claude' fallback on empty stdin, got: $OUT2"
pass "empty stdin still falls back to plain 'Claude'"

echo ""
echo "ALL CHECKS PASSED"
