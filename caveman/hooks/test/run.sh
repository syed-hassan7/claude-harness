#!/usr/bin/env bash
# Test suite for the caveman/hooks/ trio.
#
# Tests 1-12 cover caveman-mode-tracker.js's deactivation filter. Zero
# coverage existed before 2026-08-27 (see skills/manifest.yaml drift
# audit + memory/SPEC.md's review-gate section for the sibling fix this
# mirrors) -- they exist specifically to cover the two directions that
# matter: a real "stop caveman"/"normal mode" directive must still kill the
# flag, and a quoted/negated MENTION of the phrase must not.
#
# Tests 13+ close the rest of the coverage gap this directory had (measured
# with `NODE_V8_COVERAGE=... bash caveman/hooks/test/run.sh` + c8):
# caveman-config.js's resolution order was never executed at all (0% of its
# functions), caveman-activate.js was never executed at all, and the
# tracker's /caveman command branch -- the half that WRITES the flag rather
# than deleting it -- was unreached.
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

# sandbox_env <config_home_or_-> <env_mode_or_-> -- points the caveman config
# resolver at scratch state for the current (sub)shell: '-' means "unset this
# input" so a dev machine's real ~/.config/caveman or an already-exported
# CAVEMAN_DEFAULT_MODE can never decide an assertion's outcome.
sandbox_env() {
  # APPDATA goes with XDG_CONFIG_HOME: it is the win32 branch's own lookup,
  # ahead of the homedir fallback, so leaving a runner's real APPDATA in place
  # would make the "no config home configured" case resolve somewhere real.
  if [ "$1" = "-" ]; then unset XDG_CONFIG_HOME APPDATA; else export XDG_CONFIG_HOME="$(win_path "$1")"; fi
  if [ "$2" = "-" ]; then unset CAVEMAN_DEFAULT_MODE; else export CAVEMAN_DEFAULT_MODE="$2"; fi
  export USERPROFILE="$FAKE_HOME" HOME="$FAKE_HOME"
}

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

# ---------------------------------------------------------------------------
# caveman-config.js -- resolution order (env > config file > 'full')
# ---------------------------------------------------------------------------
#
# Every call sandboxes XDG_CONFIG_HOME (first entry in the resolver's own
# lookup order, so it wins on all three platforms) and unsets
# CAVEMAN_DEFAULT_MODE unless a test is deliberately exercising it --
# otherwise a dev machine with a real caveman config or a shell that already
# exports the env var would decide the assertion instead of the fixture.
#
# call_config <fn> <config_home_or_-> <env_mode_or_-> -- prints the result of
# caveman-config.js's <fn>.
call_config() {
  local fn="$1" cfg="$2" envmode="$3"
  # Exported in a subshell rather than via an `env` prefix so `node` is the
  # process bash itself spawns -- Git bash only rewrites POSIX paths in the
  # argv of a native binary it launches directly.
  (
    sandbox_env "$cfg" "$envmode"
    node -e \
      'process.stdout.write(String(require(process.argv[1])[process.argv[2]]()))' \
      "$HOOKS/caveman-config.js" "$fn"
  )
}

# seed_config <dir> <json> -- writes <dir>/caveman/config.json
seed_config() {
  mkdir -p "$1/caveman"
  printf '%s' "$2" > "$1/caveman/config.json"
}

echo "=== Test 13: CAVEMAN_DEFAULT_MODE wins over a config file that says otherwise ==="
CFG13="$WORK/cfg13"
seed_config "$CFG13" '{"defaultMode":"lite"}'
MODE=$(call_config getDefaultMode "$CFG13" ultra)
[ "$MODE" = "ultra" ] || fail "expected env var to win with 'ultra', got: $MODE"
pass "CAVEMAN_DEFAULT_MODE takes priority over the config file"

echo "=== Test 14: an INVALID env mode is ignored and the config file decides instead ==="
MODE=$(call_config getDefaultMode "$CFG13" bogus)
[ "$MODE" = "lite" ] || fail "expected fallthrough to the config file's 'lite', got: $MODE"
pass "invalid CAVEMAN_DEFAULT_MODE falls through to the config file rather than being honored or crashing"

echo "=== Test 15: both env and config values are matched case-insensitively and normalized to lowercase ==="
CFG15="$WORK/cfg15"
seed_config "$CFG15" '{"defaultMode":"WENYAN-Ultra"}'
MODE=$(call_config getDefaultMode "$CFG15" -)
[ "$MODE" = "wenyan-ultra" ] || fail "expected config value normalized to 'wenyan-ultra', got: $MODE"
MODE=$(call_config getDefaultMode "$CFG15" ULTRA)
[ "$MODE" = "ultra" ] || fail "expected env value normalized to 'ultra', got: $MODE"
pass "mixed-case env and config values resolve to their lowercase mode"

echo "=== Test 16: a missing config file falls back to 'full', not a crash ==="
CFG16="$WORK/cfg16"
mkdir -p "$CFG16"
MODE=$(call_config getDefaultMode "$CFG16" -)
[ "$MODE" = "full" ] || fail "expected 'full' when no config file exists, got: $MODE"
pass "missing config file resolves to the 'full' default"

echo "=== Test 17: malformed JSON and an unrecognized defaultMode both fall back to 'full' ==="
CFG17A="$WORK/cfg17a"
seed_config "$CFG17A" '{ this is not json'
MODE=$(call_config getDefaultMode "$CFG17A" -)
[ "$MODE" = "full" ] || fail "expected 'full' for malformed config JSON, got: $MODE"
CFG17B="$WORK/cfg17b"
seed_config "$CFG17B" '{"defaultMode":"screaming"}'
MODE=$(call_config getDefaultMode "$CFG17B" -)
[ "$MODE" = "full" ] || fail "expected 'full' for an invalid defaultMode value, got: $MODE"
pass "malformed JSON and invalid defaultMode values both resolve to 'full' instead of throwing"

echo "=== Test 18: getConfigDir honors XDG_CONFIG_HOME, and getConfigPath is that dir's config.json ==="
DIR=$(call_config getConfigDir "$CFG13" -)
case "$DIR" in *caveman) ;; *) fail "expected getConfigDir to end in 'caveman', got: $DIR";; esac
case "$DIR" in *cfg13*) ;; *) fail "expected getConfigDir under the sandboxed XDG_CONFIG_HOME, got: $DIR";; esac
PATH_OUT=$(call_config getConfigPath "$CFG13" -)
[ "$PATH_OUT" = "$DIR/config.json" ] || [ "$PATH_OUT" = "$DIR\\config.json" ] \
  || fail "expected getConfigPath to be <getConfigDir>/config.json, got: $PATH_OUT (dir: $DIR)"
pass "getConfigDir/getConfigPath resolve under XDG_CONFIG_HOME"

echo "=== Test 19: with XDG_CONFIG_HOME unset, the config dir falls back under the home directory ==="
DIR=$(call_config getConfigDir - - | tr '\\' '/')
case "$DIR" in */caveman) ;; *) fail "expected the fallback dir to end in 'caveman', got: $DIR";; esac
# The fallback is ~/.config/caveman on posix and ~/AppData/Roaming/caveman on
# win32 -- what both must share is the sandboxed home as their root.
case "$DIR" in "$(printf '%s' "$FAKE_HOME" | tr '\\' '/')"*) ;; *) fail "expected the fallback dir under the sandboxed home ($FAKE_HOME), got: $DIR";; esac
pass "config dir falls back to a home-relative path when XDG_CONFIG_HOME is unset"

# ---------------------------------------------------------------------------
# caveman-mode-tracker.js -- the /caveman command branch (writes the flag)
# ---------------------------------------------------------------------------
#
# run_command <prompt> [default_mode] -- clears the flag first (so a written
# flag is unambiguously this run's work), sandboxes the config resolver, and
# captures the hook's stdout in $TRACKER_OUT.
TRACKER_OUT=""
run_command() {
  local prompt="$1" envmode="${2:--}"
  mkdir -p "$WORK/.claude"
  rm -f "$FLAG_FILE"
  TRACKER_OUT=$(printf '{"prompt":"%s"}' "$prompt" | (
    sandbox_env - "$envmode"
    node "$HOOKS/caveman-mode-tracker.js"
  ))
}

echo "=== Test 20: '/caveman <level>' writes that level to the flag, for plain and wenyan levels alike ==="
for pair in "lite lite" "ultra ultra" "wenyan-lite wenyan-lite" "wenyan-ultra wenyan-ultra"; do
  set -- $pair
  run_command "/caveman $1"
  [ "$(cat "$FLAG_FILE")" = "$2" ] || fail "'/caveman $1' should write '$2', got: $(cat "$FLAG_FILE")"
done
pass "'/caveman lite|ultra|wenyan-lite|wenyan-ultra' each write their own level to the flag"

echo "=== Test 21: '/caveman wenyan-full' is stored under its 'wenyan' alias, same as bare '/caveman wenyan' ==="
run_command "/caveman wenyan-full"
[ "$(cat "$FLAG_FILE")" = "wenyan" ] || fail "'/caveman wenyan-full' should write the 'wenyan' alias, got: $(cat "$FLAG_FILE")"
run_command "/caveman wenyan"
[ "$(cat "$FLAG_FILE")" = "wenyan" ] || fail "'/caveman wenyan' should write 'wenyan', got: $(cat "$FLAG_FILE")"
pass "'wenyan' and 'wenyan-full' both resolve to the single 'wenyan' flag value"

echo "=== Test 22: a bare '/caveman' (no level) falls back to the configured default mode ==="
run_command "/caveman" lite
[ "$(cat "$FLAG_FILE")" = "lite" ] || fail "bare '/caveman' should use the configured default 'lite', got: $(cat "$FLAG_FILE")"
run_command "/caveman:caveman" ultra
[ "$(cat "$FLAG_FILE")" = "ultra" ] || fail "the namespaced '/caveman:caveman' form should behave identically, got: $(cat "$FLAG_FILE")"
pass "bare '/caveman' (plain and namespaced) resolves through caveman-config's default"

echo "=== Test 23: a bare '/caveman' with default mode 'off' leaves no flag behind ==="
run_command "/caveman" off
[ -f "$FLAG_FILE" ] && fail "'off' should never be written as an active mode"
[ -z "$TRACKER_OUT" ] || fail "expected no reinforcement output with no active mode, got: $TRACKER_OUT"
pass "a default mode of 'off' writes no flag and emits no reinforcement"

echo "=== Test 24: the one-shot skill commands write their own mode and skip the chat reinforcement ==="
for pair in "/caveman-commit commit" "/caveman-review review" "/caveman-compress compress" "/caveman:caveman-compress compress"; do
  set -- $pair
  run_command "$1"
  [ "$(cat "$FLAG_FILE")" = "$2" ] || fail "'$1' should write '$2', got: $(cat "$FLAG_FILE")"
  [ -z "$TRACKER_OUT" ] || fail "'$1' is a one-shot skill mode -- expected no per-turn reminder, got: $TRACKER_OUT"
done
pass "commit/review/compress commands set their mode without emitting the per-turn caveman reminder"

echo "=== Test 25: an ordinary prompt leaves the flag alone and re-emits the per-turn reminder ==="
run_command "/caveman ultra"
printf '{"prompt":"%s"}' "how does the auth middleware work?" \
  | USERPROFILE="$FAKE_HOME" HOME="$FAKE_HOME" node "$HOOKS/caveman-mode-tracker.js" > "$WORK/t25.out"
[ "$(cat "$FLAG_FILE")" = "ultra" ] || fail "an unrelated prompt must not change the active mode"
grep -q "CAVEMAN ULTRA still active" "$WORK/t25.out" \
  || fail "expected the per-turn reminder naming the active level, got: $(cat "$WORK/t25.out")"
pass "an unrelated prompt preserves the active mode and re-emits the reminder for it"

echo "=== Test 26: an unknown '/caveman-*' command is a no-op, not a crash or a flag write ==="
run_command "/caveman-bogus"
[ -f "$FLAG_FILE" ] && fail "an unrecognized /caveman-* command should not write a flag"
pass "unrecognized /caveman-* commands leave the flag untouched"

echo "=== Test 27: malformed hook input fails silently (hooks must never break a prompt) ==="
printf 'not json at all' | USERPROFILE="$FAKE_HOME" HOME="$FAKE_HOME" node "$HOOKS/caveman-mode-tracker.js" > "$WORK/t27.out" \
  || fail "the tracker must exit zero on malformed input"
[ -s "$WORK/t27.out" ] && fail "expected no output on malformed input, got: $(cat "$WORK/t27.out")"
pass "malformed stdin exits zero with no output"

# ---------------------------------------------------------------------------
# caveman-activate.js -- SessionStart flag + ruleset emission
# ---------------------------------------------------------------------------
#
# run_activate <config_home_or_-> <env_mode_or_-> [hook_path] -- runs the
# SessionStart hook against the scratch home, stdout captured in
# $ACTIVATE_OUT. hook_path defaults to the in-repo hook (SKILL.md reachable
# at ../skills/caveman/SKILL.md); pass a copy elsewhere to exercise the
# standalone-install fallback.
ACTIVATE_OUT=""
run_activate() {
  local cfg="$1" envmode="$2" hook="${3:-$HOOKS/caveman-activate.js}"
  # env(1) only accepts -u before the first NAME=VALUE, so unsets come first.
  ACTIVATE_OUT=$(
    sandbox_env "$cfg" "$envmode"
    node "$hook"
  )
}

echo "=== Test 28: activation writes the resolved mode to the flag and emits the filtered ruleset ==="
mkdir -p "$WORK/.claude"
rm -f "$FLAG_FILE" "$WORK/.claude/settings.json"
run_activate - full
[ "$(cat "$FLAG_FILE")" = "full" ] || fail "expected the flag to hold 'full', got: $(cat "$FLAG_FILE" 2>&1)"
case "$ACTIVATE_OUT" in *"CAVEMAN MODE ACTIVE — level: full"*) ;; *) fail "expected the level header for 'full', got: $ACTIVATE_OUT";; esac
case "$ACTIVATE_OUT" in *"Respond terse like smart caveman"*) ;; *) fail "expected the SKILL.md ruleset body in the output";; esac
case "$ACTIVATE_OUT" in *"---"*"name: caveman"*) fail "YAML frontmatter should be stripped from the emitted ruleset";; esac
pass "activation writes the flag and emits the SKILL.md ruleset without frontmatter"

echo "=== Test 29: the intensity table and examples are filtered down to the ACTIVE level only ==="
run_activate - lite
case "$ACTIVATE_OUT" in *"| **lite** |"*) ;; *) fail "expected the active level's intensity row to survive filtering";; esac
case "$ACTIVATE_OUT" in *"| **ultra** |"*) fail "an inactive level's intensity row leaked into the output";; esac
case "$ACTIVATE_OUT" in *"- lite:"*) ;; *) fail "expected the active level's examples to survive filtering";; esac
case "$ACTIVATE_OUT" in *"- ultra:"*) fail "an inactive level's examples leaked into the output";; esac
case "$ACTIVATE_OUT" in *"| Level | What change |"*) ;; *) fail "the intensity table header should always be kept";; esac
pass "only the active level's table row and examples survive; the table header is kept"

echo "=== Test 30: the 'wenyan' alias is emitted and filtered under its canonical 'wenyan-full' label ==="
run_activate - wenyan
case "$ACTIVATE_OUT" in *"CAVEMAN MODE ACTIVE — level: wenyan-full"*) ;; *) fail "expected the canonical 'wenyan-full' label, got: $ACTIVATE_OUT";; esac
case "$ACTIVATE_OUT" in *"| **wenyan-full** |"*) ;; *) fail "expected the wenyan-full intensity row to survive filtering";; esac
[ "$(cat "$FLAG_FILE")" = "wenyan" ] || fail "the flag should keep the raw 'wenyan' mode the statusline expects, got: $(cat "$FLAG_FILE")"
pass "'wenyan' emits the canonical 'wenyan-full' label while the flag keeps the raw alias"

echo "=== Test 31: mode 'off' removes any existing flag, prints OK, and emits no ruleset ==="
printf 'ultra' > "$FLAG_FILE"
run_activate - off
[ -f "$FLAG_FILE" ] && fail "'off' should remove a pre-existing flag file"
[ "$ACTIVATE_OUT" = "OK" ] || fail "expected exactly 'OK' for mode off, got: $ACTIVATE_OUT"
pass "mode 'off' clears the flag and emits no ruleset"

echo "=== Test 32: one-shot modes emit a one-line pointer at their own skill, not the intensity ruleset ==="
run_activate - review
case "$ACTIVATE_OUT" in *"level: review. Behavior defined by /caveman-review skill."*) ;; *) fail "expected a pointer at the /caveman-review skill, got: $ACTIVATE_OUT";; esac
case "$ACTIVATE_OUT" in *"| Level | What change |"*) fail "a one-shot mode must not emit the intensity ruleset";; esac
pass "one-shot modes emit only the short activation pointer"

echo "=== Test 33: a missing statusLine setting appends the setup nudge; a configured one does not ==="
rm -f "$WORK/.claude/settings.json"
run_activate - full
case "$ACTIVATE_OUT" in *"STATUSLINE SETUP NEEDED"*) ;; *) fail "expected the statusline nudge when settings.json is absent";; esac
case "$ACTIVATE_OUT" in *'"statusLine": { "type": "command"'*) ;; *) fail "expected the nudge to carry a paste-ready statusLine snippet, got: $ACTIVATE_OUT";; esac
printf '{"statusLine":{"type":"command","command":"bash whatever.sh"}}' > "$WORK/.claude/settings.json"
run_activate - full
case "$ACTIVATE_OUT" in *"STATUSLINE SETUP NEEDED"*) fail "the nudge should be suppressed once statusLine is configured";; esac
pass "the statusline nudge appears only while statusLine is unconfigured"

echo "=== Test 34: malformed settings.json is survivable -- ruleset still emitted, hook still exits zero ==="
printf '{ broken' > "$WORK/.claude/settings.json"
run_activate - full || fail "activation must not fail on malformed settings.json"
case "$ACTIVATE_OUT" in *"CAVEMAN MODE ACTIVE — level: full"*) ;; *) fail "expected the ruleset despite malformed settings.json, got: $ACTIVATE_OUT";; esac
rm -f "$WORK/.claude/settings.json"
pass "malformed settings.json does not block activation"

echo "=== Test 35: a standalone install with no skills/ dir falls back to the hardcoded ruleset ==="
STANDALONE="$WORK/standalone/hooks"
mkdir -p "$STANDALONE"
cp "$HOOKS/caveman-activate.js" "$HOOKS/caveman-config.js" "$STANDALONE/"
run_activate - ultra "$STANDALONE/caveman-activate.js"
case "$ACTIVATE_OUT" in *"CAVEMAN MODE ACTIVE — level: ultra"*) ;; *) fail "expected the level header from the fallback ruleset, got: $ACTIVATE_OUT";; esac
case "$ACTIVATE_OUT" in *"Current level: **ultra**"*) ;; *) fail "expected the fallback ruleset's 'Current level' line (SKILL.md has no such line), got: $ACTIVATE_OUT";; esac
case "$ACTIVATE_OUT" in *"| Level | What change |"*) fail "the fallback ruleset must not contain SKILL.md's intensity table";; esac
[ "$(cat "$FLAG_FILE")" = "ultra" ] || fail "the standalone install should still write the flag, got: $(cat "$FLAG_FILE")"
pass "a SKILL.md-less install emits the hardcoded fallback ruleset and still writes the flag"

echo ""
echo "ALL $PASS_COUNT CHECKS PASSED"

