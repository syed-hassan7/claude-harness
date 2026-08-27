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

# A PATH with jq deliberately, robustly absent -- shared by both jq-absence
# tests below. Three approaches were tried and all three broke on real CI
# before this one: a hardcoded "/usr/bin:/bin" passed locally but had a real
# jq on ubuntu-latest (ships one there by default); dropping every PATH
# directory that contained a jq binary passed on ubuntu but broke on
# macos-latest, where Homebrew's /opt/homebrew/bin holds jq alongside other
# tools this script needs (confirmed via that run's own log: even `git`
# resolves through /opt/homebrew/bin there) -- dropping that whole directory
# took collateral tools down with it; symlinking each needed tool into one
# shadow dir fixed that, but broke Windows/Git-Bash/MSYS -- MSYS-linked
# binaries (bash itself, and it turns out cat/find/date/etc. too) need their
# sibling DLLs alongside their REAL install directory, and a symlink outside
# it makes the loader come up empty ("error while loading shared libraries"
# for bash; a silently-empty `cat` for the coreutils, which is worse -- no
# error, just wrong output). Thin wrapper SCRIPTS instead of symlinks: each
# one execs the tool's real absolute path directly, so the OS loader always
# resolves DLLs relative to that real, unmoved location -- no platform's
# binary format is symlink-portable here, but every platform's shell can
# exec-by-absolute-path.
#
# What to wrap: a hand-picked list still missed "head" once (the grep used to
# build it just didn't include it as a candidate); mirroring the ENTIRE real
# PATH to remove that risk was tried next and timed out locally -- Windows'
# PATH includes System32, thousands of files, one wrapper script write each.
# Landed on a curated list again, but verified two different ways instead of
# grepped-once-from-memory: `bash -x statusline.sh` traced against a real
# payload (jq path) confirmed awk/basename/cat/date/git/jq/mkdir/ps/stat/tr;
# find/head/cygpath come from this exact bug's own CI failures (the WinGet
# jq-fallback branch, only reached when jq is absent, which a jq-present
# trace can't exercise); security/secret-tool/timeout are the two mutually
# exclusive OS-credential paths, each behind its own `command -v` guard so
# a missing one is never fatal either way.
NEEDED_BINS="bash cygpath find head test cat date git ps stat security secret-tool timeout curl awk tr basename mkdir"
SHADOW_DIR="$(mktemp -d)"
trap 'rm -rf "$SHADOW_DIR"' EXIT
for _bin in $NEEDED_BINS; do
  # type -P forces a PATH-only file lookup, unlike `command -v` -- `test` is
  # a shell builtin on this machine, so `command -v test` returns the bare
  # word "test" (not a path), and a wrapper built from that execs "test"
  # again through this same shadow PATH -- self-recursion that never
  # terminates (found by hanging the whole suite, not by inspection). A real
  # /usr/bin/test also exists alongside the builtin; type -P finds that one
  # specifically, which find's own -exec (spawned directly, not through a
  # shell, so it can't fall back to a builtin) genuinely needs a real file for.
  _resolved="$(type -P "$_bin" 2>/dev/null || true)"
  if [ -n "$_resolved" ]; then
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$_resolved" > "$SHADOW_DIR/$_bin"
    chmod +x "$SHADOW_DIR/$_bin"
  fi
done
SCRUBBED_PATH="$SHADOW_DIR"
BASH_BIN="$SHADOW_DIR/bash"

echo "=== Test: jq truly absent (PATH scrubbed, no WinGet fallback dir) -> honest error ==="
# Point HOME at an empty temp dir so the WinGet-package fallback search also
# finds nothing -- otherwise this test would pass or fail depending on
# whether the machine running it happens to have jq installed via winget,
# which defeats the point.
FAKE_HOME="$SCRIPT_DIR/.test-fake-home"
mkdir -p "$FAKE_HOME"
set +e
OUT=$(echo "$PAYLOAD" | PATH="$SCRUBBED_PATH" HOME="$FAKE_HOME" LOCALAPPDATA="$(cygpath -w "$FAKE_HOME/AppData/Local" 2>/dev/null)" "$BASH_BIN" "$STATUSLINE" 2>"$SCRIPT_DIR/.test-stderr")
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
    # NOT `cp` -- confirmed on GitHub's windows-latest runner: its pre-installed
    # jq is a Chocolatey shim, a tiny launcher that finds the real jq.exe via a
    # relative path back to its own install dir ("..\lib\jq\tools\jq.exe").
    # Copying that shim's bytes elsewhere breaks the relative lookup outright
    # ("Cannot find file at ..."). A wrapper script pointed at jq's real,
    # unmoved path sidesteps the question of whether the resolved binary is
    # even copyable -- same technique already proven for SCRUBBED_PATH above,
    # and bash (which is what actually invokes this file, via statusline.sh's
    # own `"$jq_fallback" "$@"`) reads shebang scripts by content, not by the
    # .exe extension on the filename.
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_JQ" > "$PKG_DIR/jq.exe"
    chmod +x "$PKG_DIR/jq.exe"

    OUT3=$(echo "$PAYLOAD" | PATH="$SCRUBBED_PATH" HOME="$FAKE_HOME" LOCALAPPDATA="$(cygpath -w "$FAKE_HOME/AppData/Local" 2>/dev/null)" "$BASH_BIN" "$STATUSLINE")
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
echo "=== Test: payload-supplied escape sequences never reach the terminal ==="
# The statusline is rendered with printf "%b", which interprets backslash
# escapes -- so a model display_name (or branch name) carrying \033[2J would
# otherwise be emitted as a real control sequence and could clear/repaint the
# user's terminal from whatever fed the payload.
ESC=$(printf '\033')
EVIL_PAYLOAD='{"model":{"display_name":"Sonnet \\033[2J\\007evil"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":1000}},"cwd":"/tmp"}'
OUT4=$(echo "$EVIL_PAYLOAD" | bash "$STATUSLINE")
case "$OUT4" in
  *"${ESC}[2J"*) fail "a payload-supplied escape sequence was rendered as a real control sequence: $(printf '%s' "$OUT4" | cat -v)" ;;
esac
printf '%s' "$OUT4" | grep -q 'evil' || fail "sanitization dropped the legible part of the model name too: $(printf '%s' "$OUT4" | cat -v)"
pass "escape sequences in the payload are neutralized while the readable text survives"

echo ""
echo "=== Test: usage cache lives in a private per-user dir, not a shared /tmp path ==="
grep -Eq '^(cache_dir|cache_file)=.*/tmp/' "$STATUSLINE" && fail "statusline still caches under a world-writable, predictable /tmp path" || true
grep -q 'XDG_CACHE_HOME' "$STATUSLINE" || fail "expected the usage cache to resolve under XDG_CACHE_HOME/HOME"
grep -q 'mkdir -m 700' "$STATUSLINE" || fail "cache dir must be created 700 so another local user cannot read cached usage data"
pass "usage cache is a private per-user directory created with restrictive permissions"

echo ""
echo "=== Test: the OAuth token is never passed as a curl command-line argument ==="
# argv is world-readable via ps on Linux -- a token in `-H "Authorization:
# Bearer $token"` is visible to every other local user for the request's
# lifetime. It goes through a --config file on stdin instead.
grep -q 'Authorization: Bearer' "$STATUSLINE" || fail "expected the OAuth header to still be sent somehow"
grep -Eq '^[^#]*-H "Authorization' "$STATUSLINE" && fail "the OAuth token is back in curl's argv, where ps exposes it to other local users" || true
grep -q -- '--config -' "$STATUSLINE" || fail "expected the Authorization header to be fed to curl via --config on stdin"
pass "OAuth token reaches curl through stdin, never through argv"

echo ""
echo "ALL CHECKS PASSED"
