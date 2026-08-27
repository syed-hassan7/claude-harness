#!/usr/bin/env bash
# Test suite for memory/hooks/*.js. Run from anywhere:
#   bash memory/hooks/test/run.sh
#
# Primary target is Windows + Git Bash (this repo's development environment,
# and the platform with the sharpest edges: native node.exe vs. Git Bash path
# translation, NTFS rename semantics under lock contention). Falls back to
# plain mktemp -d on other platforms, where the specific bugs this suite was
# built to catch don't apply the same way. No CI wiring yet — run manually
# after touching anything in memory/hooks/.
set -euo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Windows-style form for use inside `node -e "...require('...')..."` strings --
# argv paths get MSYS-translated automatically by Git Bash on spawn, but a
# path embedded as a substring inside a -e script argument does not.
win_path() {
  local p="$1" w
  w=$(cd "$p" 2>/dev/null && pwd -W 2>/dev/null) || true
  if [ -n "$w" ]; then echo "$w"; else echo "$p"; fi
}
HOOKS_WIN="$(win_path "$HOOKS")"

# IMPORTANT: found during development that this machine's real home directory
# (~) is itself a git repo (dotfiles-as-repo pattern). Any scratch dir nested
# under the real home (e.g. the default mktemp -d location, %TEMP% on
# Windows) is NOT a safe stand-in for "no git anywhere in the ancestry" --
# walking up from it hits the real ~/.git before it hits any override. Use a
# location outside the home tree entirely when possible.
if [ -d /c ] && [ "$(win_path /c)" = "C:/" ]; then
  WORK="/c/ch-test-$$-$RANDOM"
  mkdir -p "$WORK"
else
  WORK=$(mktemp -d)
fi
trap 'rm -rf "$WORK"' EXIT

FAKE_HOME_POSIX="$WORK/home"
NONGIT_CWD_POSIX="$WORK/nongit"
PROJECT_POSIX="$WORK/project"
mkdir -p "$FAKE_HOME_POSIX" "$NONGIT_CWD_POSIX" "$PROJECT_POSIX"
(cd "$PROJECT_POSIX" && git init -q)

# Native (non-Git-Bash) node.exe doesn't understand Git Bash's /c/... paths --
# argv gets auto-translated by Git Bash on spawn, but path strings embedded in
# JSON stdin do not. Use Windows-style paths for everything that crosses into
# a hook's JSON payload, matching what real Claude Code sends on Windows.
# win_path() is a no-op on platforms without pwd -W.
FAKE_HOME=$(win_path "$FAKE_HOME_POSIX")
NONGIT_CWD=$(win_path "$NONGIT_CWD_POSIX")
PROJECT=$(win_path "$PROJECT_POSIX")

export CLAUDE_HARNESS_HOME_OVERRIDE="$FAKE_HOME"

# Baseline for Test 13 below. All hook invocations in this suite are sandboxed
# via CLAUDE_HARNESS_HOME_OVERRIDE, so nothing here should ever touch the real
# path -- but on a machine that's actually dogfooding these hooks (memory
# hooks wired into real settings.json), the real ~/.claude/session legitimately
# already has content from genuine usage before this suite even starts. An
# existence check can't tell "this run polluted it" from "was already there";
# a before/after diff can.
PRE_SESSION_SNAPSHOT="$(find ~/.claude/session -type f 2>/dev/null | sort)" || true

PASS_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

run_hook() {
  # run_hook <script> <cwd> <json>
  local script="$1" cwd="$2" json="$3"
  (cd "$cwd" && echo "$json" | node "$HOOKS/$script")
}

# Portable "set this file's mtime N seconds in the past". `touch -d "10 days
# ago"`/`touch -d "@<epoch>"` are GNU-only -- BSD/macOS touch's `-d` (where it
# exists at all) wants a strict timestamp, not a relative string or an `@`
# epoch prefix, and rejects both with "illegal time specification" (found via
# this suite's first real macOS CI run -- never caught on this dev machine,
# which only ever runs GNU-ish touch under Git Bash). `touch -t
# [[CC]YY]MMDDhhmm[.SS]` is the one format both implementations honor
# identically, so compute the epoch portably (same BSD `-j -r` / GNU `-d "@"`
# split already used by statusline.sh's iso_to_epoch) and always call touch
# through that one path.
touch_seconds_ago() {
  local seconds="$1" file="$2" target_epoch stamp
  target_epoch=$(( $(date +%s) - seconds ))
  stamp=$(date -j -r "$target_epoch" +%Y%m%d%H%M.%S 2>/dev/null) || stamp=$(date -d "@$target_epoch" +%Y%m%d%H%M.%S)
  touch -t "$stamp" "$file"
}

echo "=== Test 0: home-directory git-repo boundary (regression for the real bug this machine has) ==="
# Give the FAKE home its own .git, matching this machine's real ~/.git shape,
# and put a cwd inside it (not at its root). walkForGitRoot must stop at the
# home boundary and return null (global scope), NOT treat the home dir as a
# project root.
(cd "$FAKE_HOME_POSIX" && git init -q)
DEEP_IN_HOME_POSIX="$FAKE_HOME_POSIX/some/deep/scratch/dir"
mkdir -p "$DEEP_IN_HOME_POSIX"
DEEP_IN_HOME=$(win_path "$DEEP_IN_HOME_POSIX")
SCOPE_JSON=$(node -e "
const lib = require('$HOOKS_WIN/_lib.js');
console.log(JSON.stringify(lib.resolveScope('$DEEP_IN_HOME')));
")
echo "$SCOPE_JSON" | grep -q '"scope":"global"' || fail "home-tracked-as-git-repo bug regressed: got $SCOPE_JSON"
pass "home directory's own .git is never treated as a project root"
rm -rf "$FAKE_HOME_POSIX/.git"

echo "=== Test 1: global scope, no checkpoint yet -> memory-init emits nothing AND creates nothing ==="
OUT=$(run_hook memory-init.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessA"}')
[ -z "$OUT" ] && pass "empty output on first init" || fail "expected empty output, got: $OUT"
[ -e "$FAKE_HOME/.claude" ] && fail "memory-init created ~/.claude/session as a side effect of a pure read (footprint on a repo/home with nothing to inject)" || pass "no directory created on a no-checkpoint read"

# Same check, project scope: a fresh git repo with no prior checkpoint must
# not get a .claude/session/ dropped into it just from SessionStart running.
run_hook memory-init.js "$PROJECT" '{"cwd":"'"$PROJECT"'","session_id":"sessP0"}' > /dev/null
[ -e "$PROJECT/.claude" ] && fail "memory-init created .claude/session in a fresh repo with nothing to inject" || pass "no directory created in a fresh project repo either"

echo "=== Test 2: PostToolUse creates global checkpoint ==="
run_hook memory-checkpoint.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessA","tool_input":{"file_path":"/some/file1.js"}}'
CP="$FAKE_HOME/.claude/session/checkpoint.md"
[ -f "$CP" ] || fail "checkpoint.md not created"
grep -q "session_id: sessA" "$CP" || fail "session_id missing in checkpoint"
grep -q "file1.js" "$CP" || fail "file1.js missing in checkpoint files list"
pass "checkpoint created with correct session_id + file"

echo "=== Test 3: second edit, same session -> file appended, not duplicated ==="
run_hook memory-checkpoint.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessA","tool_input":{"file_path":"/some/file2.js"}}'
run_hook memory-checkpoint.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessA","tool_input":{"file_path":"/some/file1.js"}}'
COUNT1=$(grep -c "file1.js" "$CP")
[ "$COUNT1" -eq 1 ] || fail "file1.js duplicated ($COUNT1 occurrences)"
pass "no duplicate file entries"

echo "=== Test 4: memory-init same session_id -> injects, does NOT rotate ==="
OUT=$(run_hook memory-init.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessA"}')
echo "$OUT" | grep -q "previous session checkpoint" || fail "expected injected checkpoint context"
[ -f "$CP" ] || fail "checkpoint should still exist (same session, no rotation)"
pass "same-session init injects without rotating"

echo "=== Test 5: memory-init DIFFERENT session_id (global) -> injects then rotates ==="
OUT=$(run_hook memory-init.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessB"}')
echo "$OUT" | grep -q "previous session checkpoint" || fail "expected injected old checkpoint before rotation"
[ -f "$CP" ] && fail "checkpoint should have been rotated away (deleted) after session_id mismatch"
ARCHIVE_COUNT=$(find "$FAKE_HOME/.claude/session/archive" -name '*.md' | wc -l)
[ "$ARCHIVE_COUNT" -eq 1 ] || fail "expected exactly 1 archived checkpoint, found $ARCHIVE_COUNT"
pass "cross-session rotation archived + deleted live checkpoint"

echo "=== Test 6: project scope creates .claude/session under repo + .gitignore ==="
run_hook memory-checkpoint.js "$PROJECT" '{"cwd":"'"$PROJECT"'","session_id":"sessP","tool_input":{"file_path":"src/index.ts"}}'
PCP="$PROJECT/.claude/session/checkpoint.md"
[ -f "$PCP" ] || fail "project checkpoint not created"
grep -q "scope: project" "$PCP" || fail "scope not marked project"
[ -f "$PROJECT/.claude/session/.gitignore" ] || fail ".gitignore not created in project session dir"
grep -qx '\*' "$PROJECT/.claude/session/.gitignore" || fail ".gitignore content wrong"
pass "project scope + gitignore correct"

echo "=== Test 7: PreCompact archives + trims + writes compressed summary ==="
run_hook memory-compact.js "$PROJECT" '{"cwd":"'"$PROJECT"'"}'
[ -f "$PCP" ] || fail "checkpoint should still exist after compact (compressed summary written back)"
PARCHIVE_COUNT=$(find "$PROJECT/.claude/session/archive" -name '*.md' | wc -l)
[ "$PARCHIVE_COUNT" -eq 1 ] || fail "expected 1 project archive entry, found $PARCHIVE_COUNT"
pass "PreCompact archived + rewrote live checkpoint"

echo "=== Test 8: memory-flush (SessionEnd) touches updated, doesn't crash on missing checkpoint ==="
run_hook memory-flush.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessB"}' # checkpoint deleted in test 5
run_hook memory-flush.js "$PROJECT" '{"cwd":"'"$PROJECT"'","session_id":"sessP"}'
pass "memory-flush ran clean in both empty and populated cases"

echo "=== Test 9: lessons index injected at SessionStart ==="
mkdir -p "$FAKE_HOME/.claude/lessons"
echo "- read-own-code-first: when debugging this-session code, read it before external research (memory/lessons/read-own-code-first.md)" > "$FAKE_HOME/.claude/lessons/index.md"
OUT=$(run_hook memory-init.js "$NONGIT_CWD" '{"cwd":"'"$NONGIT_CWD"'","session_id":"sessC"}')
echo "$OUT" | grep -q "lessons index" || fail "lessons index not injected"
echo "$OUT" | grep -q "read-own-code-first" || fail "lessons index content missing"
pass "lessons index injected"

echo "=== Test 10: secret pattern in file_path gets redacted (defensive) ==="
FAKE_AWS_KEY="AKIA""ABCDEFGHIJKLMNOP"  # built at runtime, not a literal match target for any scanner reading this file
run_hook memory-checkpoint.js "$NONGIT_CWD" "{\"cwd\":\"$NONGIT_CWD\",\"session_id\":\"sessC\",\"tool_input\":{\"file_path\":\"/tmp/${FAKE_AWS_KEY}/f.js\"}}"
CP2="$FAKE_HOME/.claude/session/checkpoint.md"
grep -q "$FAKE_AWS_KEY" "$CP2" && fail "raw secret pattern leaked into checkpoint" || pass "secret pattern redacted"

echo "=== Test 11: malformed / empty stdin never crashes a hook (fail-open) ==="
for script in memory-init.js memory-checkpoint.js memory-compact.js memory-flush.js memory-recall.js memory-architecture.js canary-check.js review-gate-check.js design-lane-gate-check.js visual-plan-gate-check.js; do
  (cd "$NONGIT_CWD" && echo "" | node "$HOOKS/$script") > "$WORK/hookout" 2>"$WORK/hookerr"
  CODE=$?
  [ "$CODE" -eq 0 ] || fail "$script exited nonzero ($CODE) on empty stdin: $(cat "$WORK/hookerr")"
  [ -s "$WORK/hookerr" ] && fail "$script wrote to stderr on empty stdin: $(cat "$WORK/hookerr")"
done
pass "all hooks fail open on empty/malformed input"

echo ""
echo "=== Test 12: CONCURRENCY -- 20 parallel PostToolUse writes, checkpoint must stay valid ==="
CONC_HOME_POSIX="$WORK/conc_home"
CONC_CWD_POSIX="$WORK/conc_cwd"
mkdir -p "$CONC_HOME_POSIX" "$CONC_CWD_POSIX"
CONC_HOME=$(win_path "$CONC_HOME_POSIX")
CONC_CWD=$(win_path "$CONC_CWD_POSIX")
PIDS=()
for i in $(seq 1 20); do
  (CLAUDE_HARNESS_HOME_OVERRIDE="$CONC_HOME" bash -c "cd '$CONC_CWD' && echo '{\"cwd\":\"$CONC_CWD\",\"session_id\":\"concS\",\"tool_input\":{\"file_path\":\"/f$i.js\"}}' | node '$HOOKS/memory-checkpoint.js'") &
  PIDS+=($!)
done
FAILED=0
for pid in "${PIDS[@]}"; do
  wait "$pid" || FAILED=1
done
[ "$FAILED" -eq 0 ] || fail "one or more concurrent hook invocations exited nonzero"

CONC_CP="$CONC_HOME/.claude/session/checkpoint.md"
[ -f "$CONC_CP" ] || fail "concurrent checkpoint file missing"
node -e "
const lib = require('$HOOKS_WIN/_lib.js');
const fs = require('fs');
const raw = fs.readFileSync('$CONC_CP', 'utf8');
const cp = lib.parseCheckpoint(raw);
if (!/^[A-Za-z0-9-]*\$/.test(cp.session_id)) { console.error('corrupt session_id: ' + JSON.stringify(cp.session_id)); process.exit(1); }
const badFile = cp.files.find(f => !/^\/f\d+\.js\$/.test(f));
if (badFile) { console.error('corrupt/garbage file entry: ' + JSON.stringify(badFile)); process.exit(1); }
console.log('files recorded: ' + cp.files.length + ' / 20');
"
LOCKLEFT=$(find "$CONC_HOME/.claude/session" -name '.checkpoint.lock' 2>/dev/null | wc -l)
[ "$LOCKLEFT" -eq 0 ] || fail "lockfile left behind after concurrent run"
TMPLEFT=$(find "$CONC_HOME/.claude/session" -name '.checkpoint.md.tmp.*' 2>/dev/null | wc -l)
[ "$TMPLEFT" -eq 0 ] || fail "temp file left behind after concurrent run"
pass "checkpoint survived 20-way concurrent writes: valid, no leftover lock/tmp files"

echo ""
echo "=== Test 14: project archive trim -- day-based cutoff (independent of count cap) ==="
TRIM_PROJECT_POSIX="$WORK/trim_project"
mkdir -p "$TRIM_PROJECT_POSIX"
(cd "$TRIM_PROJECT_POSIX" && git init -q)
TRIM_PROJECT=$(win_path "$TRIM_PROJECT_POSIX")
TRIM_ARCHIVE="$TRIM_PROJECT_POSIX/.claude/session/archive"
mkdir -p "$TRIM_ARCHIVE"
mkdir -p "$TRIM_PROJECT_POSIX/.claude/session"
echo -e "# Session checkpoint\nscope: project\nrepo: trim_project\nsession_id: sT\nupdated: $(date -u +%Y-%m-%dT%H:%M:%S.000Z)\ngoal: \n" > "$TRIM_PROJECT_POSIX/.claude/session/checkpoint.md"
# 3 recent archive files (today) + 2 old ones (10 days ago) -- only 5 total,
# well under the count cap of 10, so ONLY the day-cutoff should remove the 2 old ones.
for i in 1 2 3; do echo "recent $i" > "$TRIM_ARCHIVE/2026-recent-$i.md"; done
for i in 1 2; do
  echo "old $i" > "$TRIM_ARCHIVE/2020-old-$i.md"
  touch_seconds_ago 864000 "$TRIM_ARCHIVE/2020-old-$i.md"
done
run_hook memory-compact.js "$TRIM_PROJECT" '{"cwd":"'"$TRIM_PROJECT"'"}' > /dev/null
REMAINING=$(find "$TRIM_ARCHIVE" -name '*.md' | wc -l)
# 3 recent + 1 newly-archived-by-this-compact-call = 4 expected; the 2 old ones must be gone.
[ "$REMAINING" -eq 4 ] || fail "expected 4 archive files after day-cutoff trim (3 recent + 1 just-archived), found $REMAINING"
find "$TRIM_ARCHIVE" -name '2020-old-*' | grep -q . && fail "day-old archive files survived trim (day-based cutoff not enforced)" || pass "day-based cutoff removed old files independent of count cap"

echo "=== Test 15: project archive trim -- count cap (16 recent files -> keep newest 10) ==="
rm -rf "$TRIM_ARCHIVE"
mkdir -p "$TRIM_ARCHIVE"
# Stagger the fixtures' mtimes: trimProjectArchive ranks by mtime, so 15
# files written inside the same second (the pre-2026-08-27 fixture) left the
# ordering to readdir(), which made "the oldest one is evicted" a coin flip --
# this test failed roughly 1 run in 3 on a fast disk. Entry 01 is now the
# unambiguously oldest.
for i in $(seq 1 15); do
  ENTRY="$TRIM_ARCHIVE/2026-entry-$(printf '%02d' "$i").md"
  echo "entry $i" > "$ENTRY"
  touch_seconds_ago $(( (16 - i) * 60 )) "$ENTRY"
done
echo -e "# Session checkpoint\nscope: project\nrepo: trim_project\nsession_id: sT\nupdated: $(date -u +%Y-%m-%dT%H:%M:%S.000Z)\ngoal: \n" > "$TRIM_PROJECT_POSIX/.claude/session/checkpoint.md"
run_hook memory-compact.js "$TRIM_PROJECT" '{"cwd":"'"$TRIM_PROJECT"'"}' > /dev/null
REMAINING2=$(find "$TRIM_ARCHIVE" -name '*.md' | wc -l)
[ "$REMAINING2" -eq 10 ] || fail "expected exactly 10 archive files after count-cap trim (15 + 1 just-archived = 16 total), found $REMAINING2"
find "$TRIM_ARCHIVE" -name '2026-entry-01.md' | grep -q . && fail "oldest entry (01) survived count-cap trim -- should have been evicted" || pass "count cap correctly evicted oldest entries, kept newest 10"

echo "=== Test 16: global archive trim -- wipes to exactly 1 (the just-written entry), twice in a row ==="
TRIM_GLOBAL_POSIX="$WORK/trim_global"
mkdir -p "$TRIM_GLOBAL_POSIX"
TRIM_GLOBAL=$(win_path "$TRIM_GLOBAL_POSIX")
TRIM_GLOBAL_NONGIT_POSIX="$WORK/trim_global_cwd"
mkdir -p "$TRIM_GLOBAL_NONGIT_POSIX"
TRIM_GLOBAL_NONGIT=$(win_path "$TRIM_GLOBAL_NONGIT_POSIX")
CLAUDE_HARNESS_HOME_OVERRIDE="$TRIM_GLOBAL" run_hook memory-checkpoint.js "$TRIM_GLOBAL_NONGIT" '{"cwd":"'"$TRIM_GLOBAL_NONGIT"'","session_id":"sG","tool_input":{"file_path":"/a.js"}}'
CLAUDE_HARNESS_HOME_OVERRIDE="$TRIM_GLOBAL" run_hook memory-compact.js "$TRIM_GLOBAL_NONGIT" '{"cwd":"'"$TRIM_GLOBAL_NONGIT"'"}'
FIRST_COUNT=$(find "$TRIM_GLOBAL_POSIX/.claude/session/archive" -name '*.md' | wc -l)
[ "$FIRST_COUNT" -eq 1 ] || fail "expected exactly 1 global archive file after first PreCompact, found $FIRST_COUNT"
sleep 1
CLAUDE_HARNESS_HOME_OVERRIDE="$TRIM_GLOBAL" run_hook memory-checkpoint.js "$TRIM_GLOBAL_NONGIT" '{"cwd":"'"$TRIM_GLOBAL_NONGIT"'","session_id":"sG","tool_input":{"file_path":"/b.js"}}'
CLAUDE_HARNESS_HOME_OVERRIDE="$TRIM_GLOBAL" run_hook memory-compact.js "$TRIM_GLOBAL_NONGIT" '{"cwd":"'"$TRIM_GLOBAL_NONGIT"'"}'
SECOND_COUNT=$(find "$TRIM_GLOBAL_POSIX/.claude/session/archive" -name '*.md' | wc -l)
[ "$SECOND_COUNT" -eq 1 ] || fail "expected exactly 1 global archive file after second PreCompact (old one should be wiped), found $SECOND_COUNT"
pass "global archive trim wipes to exactly 1 entry, each time, across repeated PreCompact calls"

echo "=== Test 17: stale lock (>10s old) is reclaimed, write succeeds ==="
STALE_HOME_POSIX="$WORK/stale_home"
mkdir -p "$STALE_HOME_POSIX/.claude/session"
STALE_HOME=$(win_path "$STALE_HOME_POSIX")
STALE_CWD_POSIX="$WORK/stale_cwd"
mkdir -p "$STALE_CWD_POSIX"
STALE_CWD=$(win_path "$STALE_CWD_POSIX")
echo "held by a dead process" > "$STALE_HOME_POSIX/.claude/session/.checkpoint.lock"
touch_seconds_ago 20 "$STALE_HOME_POSIX/.claude/session/.checkpoint.lock"
CLAUDE_HARNESS_HOME_OVERRIDE="$STALE_HOME" run_hook memory-checkpoint.js "$STALE_CWD" '{"cwd":"'"$STALE_CWD"'","session_id":"sS","tool_input":{"file_path":"/stale-test.js"}}'
[ -f "$STALE_HOME_POSIX/.claude/session/checkpoint.md" ] || fail "write did not happen -- stale lock (>10s) was not reclaimed"
grep -q "stale-test.js" "$STALE_HOME_POSIX/.claude/session/checkpoint.md" || fail "checkpoint written but missing expected content after stale-lock reclaim"
[ -f "$STALE_HOME_POSIX/.claude/session/.checkpoint.lock" ] && fail "lock left behind after successful stale-lock-reclaim write" || pass "stale lock (>10s) reclaimed, write succeeded, lock released"

echo "=== Test 18: FRESH lock (not stale) blocks the write -- hook skips gracefully, exits 0 ==="
FRESH_HOME_POSIX="$WORK/fresh_home"
mkdir -p "$FRESH_HOME_POSIX/.claude/session"
FRESH_HOME=$(win_path "$FRESH_HOME_POSIX")
FRESH_CWD_POSIX="$WORK/fresh_cwd"
mkdir -p "$FRESH_CWD_POSIX"
FRESH_CWD=$(win_path "$FRESH_CWD_POSIX")
echo "held by a live process, right now" > "$FRESH_HOME_POSIX/.claude/session/.checkpoint.lock"
# fresh mtime (just created) -- well under the 10s stale threshold
EXITCODE=0
(CLAUDE_HARNESS_HOME_OVERRIDE="$FRESH_HOME" bash -c "cd '$FRESH_CWD' && echo '{\"cwd\":\"$FRESH_CWD\",\"session_id\":\"sF\",\"tool_input\":{\"file_path\":\"/should-not-be-written.js\"}}' | node '$HOOKS/memory-checkpoint.js'") || EXITCODE=$?
[ "$EXITCODE" -eq 0 ] || fail "hook exited nonzero ($EXITCODE) when lock was contended -- must fail open, not fail loud"
[ -f "$FRESH_HOME_POSIX/.claude/session/checkpoint.md" ] && fail "write happened despite fresh contended lock -- lock is not actually being respected" || pass "fresh contended lock correctly blocks the write; hook still exits 0"
rm -f "$FRESH_HOME_POSIX/.claude/session/.checkpoint.lock"

echo "=== Test 19: MAX_FILES=50 trimming -- 60 writes, exactly 50 newest survive ==="
MAXF_HOME_POSIX="$WORK/maxf_home"
mkdir -p "$MAXF_HOME_POSIX"
MAXF_HOME=$(win_path "$MAXF_HOME_POSIX")
MAXF_CWD_POSIX="$WORK/maxf_cwd"
mkdir -p "$MAXF_CWD_POSIX"
MAXF_CWD=$(win_path "$MAXF_CWD_POSIX")
for i in $(seq 1 60); do
  CLAUDE_HARNESS_HOME_OVERRIDE="$MAXF_HOME" run_hook memory-checkpoint.js "$MAXF_CWD" "{\"cwd\":\"$MAXF_CWD\",\"session_id\":\"sM\",\"tool_input\":{\"file_path\":\"/f$i.js\"}}" > /dev/null
done
MAXF_CP="$MAXF_HOME_POSIX/.claude/session/checkpoint.md"
MAXF_FILECOUNT=$(grep -c "^  - " "$MAXF_CP")
[ "$MAXF_FILECOUNT" -eq 50 ] || fail "expected exactly 50 files in checkpoint after 60 writes (MAX_FILES cap), found $MAXF_FILECOUNT"
grep -q "/f1\.js" "$MAXF_CP" && fail "oldest file (/f1.js) survived MAX_FILES trim -- should have been evicted" || true
grep -q "/f60\.js" "$MAXF_CP" || fail "newest file (/f60.js) missing -- should always survive"
grep -q "/f11\.js" "$MAXF_CP" || fail "expected /f11.js (the 50th-newest, i.e. oldest survivor) to be present"
pass "MAX_FILES=50 correctly trims to the newest 50 entries"

echo "=== Test 20: lessons index over cap -- truncation note reports how many entries were cut ==="
TRUNC_HOME_POSIX="$WORK/trunc_home"
mkdir -p "$TRUNC_HOME_POSIX/.claude/lessons"
TRUNC_HOME=$(win_path "$TRUNC_HOME_POSIX")
TRUNC_CWD_POSIX="$WORK/trunc_cwd"
mkdir -p "$TRUNC_CWD_POSIX"
TRUNC_CWD=$(win_path "$TRUNC_CWD_POSIX")
# 35 lines of ~260 bytes each (~9240 bytes total, verified) -- comfortably
# over the 8000-byte cap by a known, countable margin.
for i in $(seq 1 35); do
  printf -- '- lesson-%02d: %s\n' "$i" "$(printf 'x%.0s' $(seq 1 250))" >>"$TRUNC_HOME_POSIX/.claude/lessons/index.md"
done
TRUNC_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$TRUNC_HOME" run_hook memory-init.js "$TRUNC_CWD" "{\"cwd\":\"$TRUNC_CWD\",\"session_id\":\"sT\"}")
echo "$TRUNC_OUT" | grep -qE "truncated: [0-9]+ older entr(y|ies) cut" || fail "truncation note missing or not in the new loud format -- expected 'truncated: N older entries cut'"
pass "lessons index truncation note reports a concrete dropped-entry count, not a silent pointer"

echo "=== Test 21: memory-init.js injects project architecture index ==="
ARCH_PROJECT_POSIX="$WORK/arch_project"
mkdir -p "$ARCH_PROJECT_POSIX"
(cd "$ARCH_PROJECT_POSIX" && git init -q)
ARCH_PROJECT=$(win_path "$ARCH_PROJECT_POSIX")
mkdir -p "$ARCH_PROJECT_POSIX/.claude/architecture/notes"
echo "auth-flow | TestProj | auth, jwt, session | Auth uses JWT with 15min expiry | notes/auth-flow.md" > "$ARCH_PROJECT_POSIX/.claude/architecture/index.md"
OUT=$(run_hook memory-init.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","session_id":"sArch"}')
echo "$OUT" | grep -q "project architecture index" || fail "project architecture index block not injected"
echo "$OUT" | grep -q "auth-flow" || fail "architecture index content missing from injection"
pass "project architecture index injected at SessionStart"

echo "=== Test 22: memory-recall.js -- tag match surfaces full note Summary+Detail ==="
cat > "$ARCH_PROJECT_POSIX/.claude/architecture/notes/auth-flow.md" <<'EOF'
# Architecture note
id: auth-flow
scope: project
repo: arch_project
project: TestProj
component: auth
tags: auth, jwt, session
watch_files:
  - src/auth.ts
created: 2026-08-01T00:00:00.000Z
updated: 2026-08-01T00:00:00.000Z
status: current
index_line: auth-flow | TestProj | auth, jwt, session | Auth uses JWT with 15min expiry | notes/auth-flow.md

## Summary
Auth uses JWT with 15min expiry, refreshed via httpOnly cookie.

## Detail
Chosen to avoid localStorage XSS exposure.

## Staleness check

## Superseded
EOF
OUT=$(run_hook memory-recall.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","prompt":"How does our jwt session expiry work?"}')
echo "$OUT" | grep -q "auth-flow" || fail "matched note id missing from recall injection"
echo "$OUT" | grep -q "avoid localStorage XSS" || fail "matched note Detail section missing -- recall injected index summary only, not full note"
pass "memory-recall.js surfaces full note content on tag match"

echo "=== Test 23: memory-recall.js -- no tag match -> empty output ==="
OUT=$(run_hook memory-recall.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","prompt":"what is the weather like today"}')
[ -z "$OUT" ] && pass "no output when prompt matches no tags" || fail "expected empty output, got: $OUT"

echo "=== Test 24: memory-recall.js -- global index recall reachable from an unrelated project (cross-project ask) ==="
mkdir -p "$FAKE_HOME/.claude/architecture/notes"
echo "vendor-db | VenderScope | venderscope, postgres, pooling | Uses PgBouncer transaction pooling on Render | notes/vendor-db.md" > "$FAKE_HOME/.claude/architecture/index.md"
cat > "$FAKE_HOME/.claude/architecture/notes/vendor-db.md" <<'EOF'
# Architecture note
id: vendor-db
scope: global
repo: null
project: VenderScope
tags: venderscope, postgres, pooling
created: 2026-08-01T00:00:00.000Z
updated: 2026-08-01T00:00:00.000Z
status: current
index_line: vendor-db | VenderScope | venderscope, postgres, pooling | Uses PgBouncer transaction pooling on Render | notes/vendor-db.md

## Summary
Uses PgBouncer transaction pooling on Render.

## Detail
Direct connections exhausted the free-tier limit under load.
EOF
OUT=$(run_hook memory-recall.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","prompt":"why is the postgres pooling misbehaving on VenderScope"}')
echo "$OUT" | grep -q "vendor-db" || fail "cross-project global note not recalled while sitting inside an unrelated project"
pass "global architecture index recalled from inside a different project's repo"

echo "=== Test 25: memory-architecture.js -- Read of a watched file surfaces its note, no staleness flip ==="
mkdir -p "$ARCH_PROJECT_POSIX/src"
echo "// auth code" > "$ARCH_PROJECT_POSIX/src/auth.ts"
cat > "$ARCH_PROJECT_POSIX/.claude/architecture/watch-map.json" <<EOF
{"src/auth.ts": ["auth-flow"]}
EOF
AUTH_FILE="$ARCH_PROJECT/src/auth.ts"
OUT=$(run_hook memory-architecture.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","tool_name":"Read","tool_input":{"file_path":"'"$AUTH_FILE"'"}}')
echo "$OUT" | grep -q "auth-flow" || fail "Read of watched file did not surface its architecture note"
grep -q "status: current" "$ARCH_PROJECT_POSIX/.claude/architecture/notes/auth-flow.md" || fail "Read incorrectly flagged the note stale (status changed)"
pass "Read of watched file surfaces note, leaves status untouched"

echo "=== Test 26: memory-architecture.js -- Edit of a watched file flags stale + prefixes index line ==="
OUT=$(run_hook memory-architecture.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","tool_name":"Edit","tool_input":{"file_path":"'"$AUTH_FILE"'"}}')
echo "$OUT" | grep -q "auth-flow" || fail "Edit of watched file did not surface its architecture note"
grep -q "status: possibly-stale" "$ARCH_PROJECT_POSIX/.claude/architecture/notes/auth-flow.md" || fail "Edit did not flip note status to possibly-stale"
grep -q "possibly-stale-since" "$ARCH_PROJECT_POSIX/.claude/architecture/notes/auth-flow.md" || fail "Edit did not append a possibly-stale-since marker"
grep -q '^\[STALE?\] auth-flow' "$ARCH_PROJECT_POSIX/.claude/architecture/index.md" || fail "index.md line was not prefixed [STALE?] after edit"
pass "Edit of watched file flags note stale and prefixes its index line"

echo "=== Test 27: memory-architecture.js -- untracked file -> empty output, no crash ==="
echo "// unrelated" > "$ARCH_PROJECT_POSIX/src/unrelated.ts"
OUT=$(run_hook memory-architecture.js "$ARCH_PROJECT" '{"cwd":"'"$ARCH_PROJECT"'","tool_name":"Edit","tool_input":{"file_path":"'"$ARCH_PROJECT"'/src/unrelated.ts"}}')
[ -z "$OUT" ] && pass "untracked file touch produces no output" || fail "expected empty output for untracked file, got: $OUT"

echo ""
echo "=== Test 28: canary-check.js -- pack-file citation without the name opens a miss + injects a same-turn reminder ==="
CANARY_PROJECT_POSIX="$WORK/canary_project"
mkdir -p "$CANARY_PROJECT_POSIX"
(cd "$CANARY_PROJECT_POSIX" && git init -q)
CANARY_PROJECT=$(win_path "$CANARY_PROJECT_POSIX")
WORK_WIN=$(win_path "$WORK")
TRANSCRIPT_POSIX="$WORK/canary_transcript.jsonl"
TRANSCRIPT="$WORK_WIN/canary_transcript.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Per rules/engineering.md the YAGNI ladder applies here."}]}}' > "$TRANSCRIPT_POSIX"
OUT=$(run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS1","transcript_path":"'"$TRANSCRIPT"'"}')
echo "$OUT" | grep -q "drift canary miss" || fail "expected a canary-miss reminder injected, got: $OUT"
echo "$OUT" | grep -q "rules/engineering.md" || fail "reminder did not name the cited file"
CANARY_LOG="$CANARY_PROJECT_POSIX/.claude/canary/log.md"
grep -q "^OPEN .*rules/engineering.md" "$CANARY_LOG" || fail "OPEN entry not logged: $(cat "$CANARY_LOG" 2>/dev/null)"
pass "canary-check.js opens a miss and injects a same-turn reminder"

echo "=== Test 29: canary-check.js -- name reappearing resolves the pending miss ==="
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Confirming with Zarak now, per WORKFLOW.md drift canary."}]}}' >> "$TRANSCRIPT_POSIX"
OUT=$(run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS1","transcript_path":"'"$TRANSCRIPT"'"}')
echo "$OUT" | grep -q "drift canary miss" && fail "expected no reminder once the name reappeared, got: $OUT"
grep -q "^RESOLVED .*rules/engineering.md" "$CANARY_LOG" || fail "RESOLVED entry not logged: $(cat "$CANARY_LOG")"
pass "canary-check.js resolves a pending miss only when the name actually reappears, not on mere injection"

echo "=== Test 30: canary-check.js -- repeated citation without the name escalates instead of duplicating OPEN ==="
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Per rules/security-invariants.md Tier 0 applies to this edit."}]}}' >> "$TRANSCRIPT_POSIX"
run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS1","transcript_path":"'"$TRANSCRIPT"'"}' > /dev/null
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Also rules/design-lane.md step 6 applies."}]}}' >> "$TRANSCRIPT_POSIX"
run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS1","transcript_path":"'"$TRANSCRIPT"'"}' > /dev/null
grep -q "^ESCALATED (1)" "$CANARY_LOG" || fail "expected an ESCALATED(1) entry: $(cat "$CANARY_LOG")"
pass "canary-check.js escalates a still-open miss instead of opening a duplicate"

echo "=== Test 31: canary-check.js -- missing transcript_path -> no crash, empty output ==="
OUT=$(run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS2","transcript_path":"'"$WORK_WIN"'/does-not-exist.jsonl"}')
[ -z "$OUT" ] || fail "expected empty output when transcript_path does not exist, got: $OUT"
pass "canary-check.js handles a missing transcript_path gracefully"

echo "=== Test 32: memory-init.js -- SessionStart rollup surfaces open canary misses ==="
OUT=$(run_hook memory-init.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS1"}')
echo "$OUT" | grep -q "drift canary" || fail "expected drift-canary rollup in SessionStart injection: $OUT"
echo "$OUT" | grep -qE "1 open naming-miss" || fail "expected exactly 1 open miss counted, got: $OUT"
pass "memory-init.js surfaces open canary-miss count at SessionStart"

echo "=== Test 33: canary-check.js -- pruning an idle session with an open pending miss logs EXPIRED ==="
PRUNE_PROJECT_POSIX="$WORK/prune_project"
mkdir -p "$PRUNE_PROJECT_POSIX"
(cd "$PRUNE_PROJECT_POSIX" && git init -q)
PRUNE_PROJECT=$(win_path "$PRUNE_PROJECT_POSIX")
mkdir -p "$PRUNE_PROJECT_POSIX/.claude/canary"
OLD_ISO=$(node -e "console.log(new Date(Date.now() - 31*24*60*60*1000).toISOString())")
node -e "
const fs = require('fs');
const state = {
  oldWithPending: { offset: 0, lastSeen: '$OLD_ISO', pending: { file: 'rules/engineering.md', at: '$OLD_ISO' } },
  oldNoPending: { offset: 0, lastSeen: '$OLD_ISO', pending: null }
};
fs.writeFileSync('$PRUNE_PROJECT/.claude/canary/state.json', JSON.stringify(state));
"
PRUNE_TRANSCRIPT_POSIX="$WORK/prune_transcript.jsonl"
PRUNE_TRANSCRIPT="$WORK_WIN/prune_transcript.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"just some unrelated turn"}]}}' > "$PRUNE_TRANSCRIPT_POSIX"
run_hook canary-check.js "$PRUNE_PROJECT" '{"cwd":"'"$PRUNE_PROJECT"'","session_id":"canPruneSession","transcript_path":"'"$PRUNE_TRANSCRIPT"'"}' > /dev/null
PRUNE_LOG="$PRUNE_PROJECT_POSIX/.claude/canary/log.md"
grep -q "^EXPIRED .*oldWithPending.*rules/engineering.md" "$PRUNE_LOG" || fail "expected EXPIRED entry for pruned session with open pending: $(cat "$PRUNE_LOG" 2>/dev/null)"
grep -q "oldNoPending" "$PRUNE_LOG" && fail "no-pending session should never appear in an EXPIRED log line" || true
PRUNE_STATE="$PRUNE_PROJECT/.claude/canary/state.json"
node -e "
const fs = require('fs');
const state = JSON.parse(fs.readFileSync('$PRUNE_STATE', 'utf8'));
if ('oldWithPending' in state) { console.error('oldWithPending was not pruned'); process.exit(1); }
if ('oldNoPending' in state) { console.error('oldNoPending was not pruned'); process.exit(1); }
"
pass "idle session with open pending logs EXPIRED before being pruned; idle session with no pending prunes silently"

echo ""
echo "=== Test 34: review-gate-check.js -- a non-commit Bash call is a no-op ==="
REVGATE_PROJECT_POSIX="$WORK/revgate_project"
mkdir -p "$REVGATE_PROJECT_POSIX"
(cd "$REVGATE_PROJECT_POSIX" && git init -q)
REVGATE_PROJECT=$(win_path "$REVGATE_PROJECT_POSIX")
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS1","tool_name":"Bash","tool_input":{"command":"ls -la"}}' > /dev/null
REVGATE_LOG="$REVGATE_PROJECT_POSIX/.claude/review-gate/log.md"
[ -f "$REVGATE_LOG" ] && grep -q "session revS1" "$REVGATE_LOG" && fail "non-commit Bash call should not log anything: $(cat "$REVGATE_LOG")"
REVGATE_STATE="$REVGATE_PROJECT/.claude/review-gate/state.json"
node -e "
const s = JSON.parse(require('fs').readFileSync('$REVGATE_STATE', 'utf8'));
if (s.revS1.reviewSeen) { console.error('reviewSeen should still be false'); process.exit(1); }
if (s.revS1.pending) { console.error('pending should still be null'); process.exit(1); }
"
pass "review-gate-check.js does nothing on a non-commit Bash call"

echo "=== Test 35: review-gate-check.js -- commit with no review evidence logs a MISS ==="
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS1","tool_name":"Bash","tool_input":{"command":"git commit -m \"add feature\""}}' > /dev/null
grep -q "^MISS .*session revS1" "$REVGATE_LOG" || fail "expected a MISS entry for revS1: $(cat "$REVGATE_LOG" 2>/dev/null)"
node -e "
const s = JSON.parse(require('fs').readFileSync('$REVGATE_STATE', 'utf8'));
if (!s.revS1.pending) { console.error('pending should be set after an unreviewed commit'); process.exit(1); }
"
pass "review-gate-check.js logs a MISS when a commit runs with no review-loop/security-audit evidence"

echo "=== Test 36: review-gate-check.js -- a real Skill(review-loop) invocation clears the sticky flag, no MISS on commit ==="
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS2","tool_name":"Skill","tool_input":{"skill":"review-loop"}}' > /dev/null
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS2","tool_name":"Bash","tool_input":{"command":"git commit -m \"ship it\""}}' > /dev/null
grep -q "session revS2" "$REVGATE_LOG" && fail "revS2 ran Skill(review-loop) first, should never log a MISS: $(cat "$REVGATE_LOG")"
pass "review-gate-check.js does not flag a commit once a real Skill(review-loop) invocation happened earlier in the session"

echo "=== Test 36b: review-gate-check.js -- a real Agent(coderabbit:code-reviewer) invocation clears the sticky flag ==="
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS3","tool_name":"Agent","tool_input":{"subagent_type":"coderabbit:code-reviewer"}}' > /dev/null
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS3","tool_name":"Bash","tool_input":{"command":"git commit -m \"ship it\""}}' > /dev/null
grep -q "session revS3" "$REVGATE_LOG" && fail "revS3 ran Agent(coderabbit:code-reviewer) first, should never log a MISS: $(cat "$REVGATE_LOG")"
pass "review-gate-check.js does not flag a commit once a real Agent(coderabbit:code-reviewer) invocation happened earlier in the session"

echo "=== Test 36c: review-gate-check.js -- a real coderabbit CLI invocation via Bash clears the sticky flag ==="
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS4","tool_name":"Bash","tool_input":{"command":"coderabbit review --agent"}}' > /dev/null
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS4","tool_name":"Bash","tool_input":{"command":"git commit -m \"ship it\""}}' > /dev/null
grep -q "session revS4" "$REVGATE_LOG" && fail "revS4 ran the coderabbit CLI first, should never log a MISS: $(cat "$REVGATE_LOG")"
pass "review-gate-check.js does not flag a commit once a real coderabbit CLI invocation happened earlier in the session"

echo "=== Test 36d: review-gate-check.js -- REGRESSION: merely MENTIONING review-loop/coderabbit in text/commands, without a real invocation, must still MISS ==="
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS5","tool_name":"Bash","tool_input":{"command":"echo \"remember to run review-loop and coderabbit later\""}}' > /dev/null
run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS5","tool_name":"Bash","tool_input":{"command":"git commit -m \"ship it\""}}' > /dev/null
grep -q "^MISS .*session revS5" "$REVGATE_LOG" || fail "revS5 only ever MENTIONED the markers in a command string, never actually invoked a review tool -- must still MISS: $(cat "$REVGATE_LOG" 2>/dev/null)"
pass "review-gate-check.js is not satisfied by text merely mentioning review-loop/coderabbit -- only a real invocation counts"

echo "=== Test 37: review-gate-check.js -- UserPromptSubmit surfaces a pending miss exactly once ==="
OUT=$(run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS1"}')
echo "$OUT" | grep -q "review-gate miss" || fail "expected the pending miss to surface on the next turn, got: $OUT"
OUT2=$(run_hook review-gate-check.js "$REVGATE_PROJECT" '{"cwd":"'"$REVGATE_PROJECT"'","session_id":"revS1"}')
[ -z "$OUT2" ] || fail "expected no reminder the second time, pending should already be cleared, got: $OUT2"
pass "review-gate-check.js surfaces a pending miss once, then clears it"

echo "=== Test 38: review-gate-check.js -- pruning an idle session with an open pending miss logs EXPIRED ==="
REVPRUNE_PROJECT_POSIX="$WORK/revgate_prune_project"
mkdir -p "$REVPRUNE_PROJECT_POSIX"
(cd "$REVPRUNE_PROJECT_POSIX" && git init -q)
REVPRUNE_PROJECT=$(win_path "$REVPRUNE_PROJECT_POSIX")
mkdir -p "$REVPRUNE_PROJECT_POSIX/.claude/review-gate"
REV_OLD_ISO=$(node -e "console.log(new Date(Date.now() - 31*24*60*60*1000).toISOString())")
node -e "
const fs = require('fs');
const state = {
  oldWithPending: { offset: 0, reviewSeen: false, lastSeen: '$REV_OLD_ISO', pending: { at: '$REV_OLD_ISO' } },
  oldNoPending: { offset: 0, reviewSeen: true, lastSeen: '$REV_OLD_ISO', pending: null }
};
fs.writeFileSync('$REVPRUNE_PROJECT/.claude/review-gate/state.json', JSON.stringify(state));
"
REVPRUNE_TRANSCRIPT_POSIX="$WORK/revgate_prune_transcript.jsonl"
REVPRUNE_TRANSCRIPT=$(win_path "$WORK")/revgate_prune_transcript.jsonl
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"unrelated turn"}]}}' > "$REVPRUNE_TRANSCRIPT_POSIX"
run_hook review-gate-check.js "$REVPRUNE_PROJECT" '{"cwd":"'"$REVPRUNE_PROJECT"'","session_id":"revPruneSession","transcript_path":"'"$REVPRUNE_TRANSCRIPT"'","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
REVPRUNE_LOG="$REVPRUNE_PROJECT_POSIX/.claude/review-gate/log.md"
grep -q "^EXPIRED .*oldWithPending" "$REVPRUNE_LOG" || fail "expected EXPIRED entry for pruned session with open pending: $(cat "$REVPRUNE_LOG" 2>/dev/null)"
grep -q "oldNoPending" "$REVPRUNE_LOG" && fail "no-pending session should never appear in an EXPIRED log line" || true
REVPRUNE_STATE="$REVPRUNE_PROJECT/.claude/review-gate/state.json"
node -e "
const fs = require('fs');
const state = JSON.parse(fs.readFileSync('$REVPRUNE_STATE', 'utf8'));
if ('oldWithPending' in state) { console.error('oldWithPending was not pruned'); process.exit(1); }
if ('oldNoPending' in state) { console.error('oldNoPending was not pruned'); process.exit(1); }
"
pass "review-gate-check.js logs EXPIRED for an idle session with an unsurfaced pending miss, prunes silently otherwise"

echo ""
echo "=== Test 39: canary-check.js -- a name-drop in an earlier turn must not mask a citation in a LATER turn of the same batch ==="
CANARY2_TRANSCRIPT_POSIX="$WORK/canary2_transcript.jsonl"
CANARY2_TRANSCRIPT=$(win_path "$WORK")/canary2_transcript.jsonl
{
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Confirming with Zarak now, all clear."}]}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"continue"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Per rules/security-invariants.md Tier 0 applies to this edit."}]}}'
} > "$CANARY2_TRANSCRIPT_POSIX"
run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS3","transcript_path":"'"$CANARY2_TRANSCRIPT"'"}' > /dev/null
grep -q "^OPEN .*session canS3.*rules/security-invariants.md" "$CANARY_LOG" || fail "expected a fresh OPEN for the later turn's unnamed citation, name-drop in the earlier turn should not cover it: $(cat "$CANARY_LOG")"
pass "canary-check.js evaluates each real turn independently -- an early name-drop no longer masks a later turn's unnamed citation"

echo "=== Test 40: canary-check.js -- non-regression: a tool-call round-trip WITHIN one turn still merges (no real user text in between) ==="
CANARY3_TRANSCRIPT_POSIX="$WORK/canary3_transcript.jsonl"
CANARY3_TRANSCRIPT=$(win_path "$WORK")/canary3_transcript.jsonl
{
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Confirming with Zarak now."}]}}'
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Per rules/design-lane.md step 2, continuing."}]}}'
} > "$CANARY3_TRANSCRIPT_POSIX"
run_hook canary-check.js "$CANARY_PROJECT" '{"cwd":"'"$CANARY_PROJECT"'","session_id":"canS4","transcript_path":"'"$CANARY3_TRANSCRIPT"'"}' > /dev/null
grep -q "session canS4" "$CANARY_LOG" && fail "a tool_result (no real user text) must not split a turn -- name-drop should still cover the later chunk: $(cat "$CANARY_LOG")"
pass "canary-check.js still merges text split by a tool-call round-trip within one real turn, unchanged from before the fix"

echo ""
echo "=== Test 41: design-lane-gate-check.js -- a non-UI edit + commit is a no-op ==="
DLG_PROJECT_POSIX="$WORK/dlg_project"
mkdir -p "$DLG_PROJECT_POSIX"
(cd "$DLG_PROJECT_POSIX" && git init -q)
DLG_PROJECT=$(win_path "$DLG_PROJECT_POSIX")
DLG_LOG="$DLG_PROJECT_POSIX/.claude/design-lane-gate/log.md"
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS1","tool_name":"Edit","tool_input":{"file_path":"scripts/build.py"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS1","tool_name":"Bash","tool_input":{"command":"git commit -m \"backend fix\""}}' > /dev/null
[ -f "$DLG_LOG" ] && grep -q "session dlgS1" "$DLG_LOG" && fail "non-UI edit should never trigger a MISS: $(cat "$DLG_LOG")"
pass "design-lane-gate-check.js ignores a non-UI file edit entirely"

echo "=== Test 42: design-lane-gate-check.js -- UI edit + commit with no screenshot evidence logs a MISS ==="
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS2","tool_name":"Edit","tool_input":{"file_path":"src/components/Card.tsx"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS2","tool_name":"Bash","tool_input":{"command":"git commit -m \"new card component\""}}' > /dev/null
grep -q "^MISS .*session dlgS2" "$DLG_LOG" || fail "expected a MISS entry for dlgS2: $(cat "$DLG_LOG" 2>/dev/null)"
pass "design-lane-gate-check.js logs a MISS when a commit ships a touched UI file with no screenshot evidence"

echo "=== Test 43: design-lane-gate-check.js -- an image Read counts as screenshot evidence, no MISS on commit ==="
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS3","tool_name":"Edit","tool_input":{"file_path":"src/components/Modal.tsx"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS3","tool_name":"Read","tool_input":{"file_path":"'"$WORK_WIN"'/modal-screenshot.png"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS3","tool_name":"Bash","tool_input":{"command":"git commit -m \"modal styling\""}}' > /dev/null
grep -q "session dlgS3" "$DLG_LOG" && fail "reading back a screenshot should count as evidence, no MISS expected: $(cat "$DLG_LOG")"
pass "design-lane-gate-check.js treats an image-file Read as screenshot evidence"

echo "=== Test 44: design-lane-gate-check.js -- a Bash command mentioning playwright also counts as evidence ==="
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS4","tool_name":"Edit","tool_input":{"file_path":"src/App.css"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS4","tool_name":"Bash","tool_input":{"command":"npx playwright test --project=chromium"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS4","tool_name":"Bash","tool_input":{"command":"git commit -m \"css tweak\""}}' > /dev/null
grep -q "session dlgS4" "$DLG_LOG" && fail "a playwright Bash invocation should count as evidence, no MISS expected: $(cat "$DLG_LOG")"
pass "design-lane-gate-check.js treats a playwright-mentioning Bash command as screenshot evidence"

echo "=== Test 45: design-lane-gate-check.js -- UserPromptSubmit surfaces a pending miss exactly once ==="
OUT=$(run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS2"}')
echo "$OUT" | grep -q "design-lane gate miss" || fail "expected the pending miss to surface on the next turn, got: $OUT"
OUT2=$(run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS2"}')
[ -z "$OUT2" ] || fail "expected no reminder the second time, pending should already be cleared, got: $OUT2"
pass "design-lane-gate-check.js surfaces a pending miss once, then clears it"

echo "=== Test 46: design-lane-gate-check.js -- pruning an idle session with an open pending miss logs EXPIRED ==="
DLGPRUNE_PROJECT_POSIX="$WORK/dlg_prune_project"
mkdir -p "$DLGPRUNE_PROJECT_POSIX"
(cd "$DLGPRUNE_PROJECT_POSIX" && git init -q)
DLGPRUNE_PROJECT=$(win_path "$DLGPRUNE_PROJECT_POSIX")
mkdir -p "$DLGPRUNE_PROJECT_POSIX/.claude/design-lane-gate"
DLG_OLD_ISO=$(node -e "console.log(new Date(Date.now() - 31*24*60*60*1000).toISOString())")
node -e "
const fs = require('fs');
const state = {
  oldWithPending: { uiTouched: true, screenshotSeen: false, lastSeen: '$DLG_OLD_ISO', pending: { at: '$DLG_OLD_ISO' } },
  oldNoPending: { uiTouched: true, screenshotSeen: true, lastSeen: '$DLG_OLD_ISO', pending: null }
};
fs.writeFileSync('$DLGPRUNE_PROJECT/.claude/design-lane-gate/state.json', JSON.stringify(state));
"
run_hook design-lane-gate-check.js "$DLGPRUNE_PROJECT" '{"cwd":"'"$DLGPRUNE_PROJECT"'","session_id":"dlgPruneSession","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
DLGPRUNE_LOG="$DLGPRUNE_PROJECT_POSIX/.claude/design-lane-gate/log.md"
grep -q "^EXPIRED .*oldWithPending" "$DLGPRUNE_LOG" || fail "expected EXPIRED entry for pruned session with open pending: $(cat "$DLGPRUNE_LOG" 2>/dev/null)"
grep -q "oldNoPending" "$DLGPRUNE_LOG" && fail "no-pending session should never appear in an EXPIRED log line" || true
DLGPRUNE_STATE="$DLGPRUNE_PROJECT/.claude/design-lane-gate/state.json"
node -e "
const fs = require('fs');
const state = JSON.parse(fs.readFileSync('$DLGPRUNE_STATE', 'utf8'));
if ('oldWithPending' in state) { console.error('oldWithPending was not pruned'); process.exit(1); }
if ('oldNoPending' in state) { console.error('oldNoPending was not pruned'); process.exit(1); }
"
pass "design-lane-gate-check.js logs EXPIRED for an idle session with an unsurfaced pending miss, prunes silently otherwise"

echo "=== Test 47: design-lane-gate-check.js -- a chained command citing playwright AFTER the commit must not suppress the MISS ==="
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS5","tool_name":"Edit","tool_input":{"file_path":"src/components/Panel.tsx"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG_PROJECT" '{"cwd":"'"$DLG_PROJECT"'","session_id":"dlgS5","tool_name":"Bash","tool_input":{"command":"git commit -m \"panel\" && npx playwright test"}}' > /dev/null
grep -q "^MISS .*session dlgS5" "$DLG_LOG" || fail "expected a MISS -- playwright mentioned AFTER the commit in the same chained command must not count as prior evidence: $(cat "$DLG_LOG" 2>/dev/null)"
pass "design-lane-gate-check.js only counts screenshot evidence that existed before the commit, not evidence the same chained command manufactures after it"

echo "=== Test 48: design-lane-gate-check.js -- an irrelevant tool call touches no state at all (early-return) ==="
DLG_IRRELEVANT_PROJECT_POSIX="$WORK/dlg_irrelevant_project"
mkdir -p "$DLG_IRRELEVANT_PROJECT_POSIX"
(cd "$DLG_IRRELEVANT_PROJECT_POSIX" && git init -q)
DLG_IRRELEVANT_PROJECT=$(win_path "$DLG_IRRELEVANT_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG_IRRELEVANT_PROJECT" '{"cwd":"'"$DLG_IRRELEVANT_PROJECT"'","session_id":"dlgS6","tool_name":"Read","tool_input":{"file_path":"README.md"}}' > /dev/null
[ -d "$DLG_IRRELEVANT_PROJECT_POSIX/.claude/design-lane-gate" ] && fail "a Read on a non-image file should never create the state dir at all: $(ls "$DLG_IRRELEVANT_PROJECT_POSIX/.claude/design-lane-gate" 2>/dev/null)"
pass "design-lane-gate-check.js skips all state I/O for a tool call that could not change either flag"

echo "=== Test 49: lesson-promotion nudge -- lessons exist, no watermark yet -> nudge fires ==="
PROMO49_HOME_POSIX="$WORK/promo49_home"
mkdir -p "$PROMO49_HOME_POSIX/.claude/lessons"
PROMO49_HOME=$(win_path "$PROMO49_HOME_POSIX")
PROMO49_CWD_POSIX="$WORK/promo49_cwd"
mkdir -p "$PROMO49_CWD_POSIX"
PROMO49_CWD=$(win_path "$PROMO49_CWD_POSIX")
echo "- some-lesson: a generalizable rule (lessons/some-lesson.md)" > "$PROMO49_HOME_POSIX/.claude/lessons/index.md"
PROMO49_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$PROMO49_HOME" run_hook memory-init.js "$PROMO49_CWD" "{\"cwd\":\"$PROMO49_CWD\",\"session_id\":\"promo49\"}")
echo "$PROMO49_OUT" | grep -q "lesson promotion review" || fail "expected a lesson-promotion nudge with no prior watermark, got: $PROMO49_OUT"
pass "lesson-promotion nudge fires when lessons exist and no watermark has ever been written"
[ -d "$PROMO49_HOME_POSIX/.claude/promotion" ] && fail "the promotion nudge is read-only -- it must never create .claude/promotion as a side effect of a pure read"
pass "lesson-promotion nudge creates no promotion/ directory as a side effect (matches Test 1's read-only invariant for session/)"

echo "=== Test 50: lesson-promotion nudge -- watermark newer than index mtime -> silent ==="
PROMO50_HOME_POSIX="$WORK/promo50_home"
mkdir -p "$PROMO50_HOME_POSIX/.claude/lessons" "$PROMO50_HOME_POSIX/.claude/promotion"
PROMO50_HOME=$(win_path "$PROMO50_HOME_POSIX")
PROMO50_CWD_POSIX="$WORK/promo50_cwd"
mkdir -p "$PROMO50_CWD_POSIX"
PROMO50_CWD=$(win_path "$PROMO50_CWD_POSIX")
echo "- some-lesson: a generalizable rule (lessons/some-lesson.md)" > "$PROMO50_HOME_POSIX/.claude/lessons/index.md"
touch_seconds_ago 3600 "$PROMO50_HOME_POSIX/.claude/lessons/index.md"
PROMO50_NOW_ISO=$(node -e "console.log(new Date().toISOString())")
node -e "require('fs').writeFileSync('$PROMO50_HOME/.claude/promotion/state.json', JSON.stringify({lastReviewedAt: '$PROMO50_NOW_ISO'}))"
PROMO50_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$PROMO50_HOME" run_hook memory-init.js "$PROMO50_CWD" "{\"cwd\":\"$PROMO50_CWD\",\"session_id\":\"promo50\"}")
echo "$PROMO50_OUT" | grep -q "lesson promotion review" && fail "expected no nudge -- watermark is newer than the index, got: $PROMO50_OUT"
pass "lesson-promotion nudge stays silent once the watermark is current"

echo "=== Test 51: lesson-promotion nudge -- no lessons index at all -> silent, no crash ==="
PROMO51_CWD_POSIX="$WORK/promo51_cwd"
mkdir -p "$PROMO51_CWD_POSIX"
PROMO51_CWD=$(win_path "$PROMO51_CWD_POSIX")
PROMO51_HOME_POSIX="$WORK/promo51_home"
mkdir -p "$PROMO51_HOME_POSIX"
PROMO51_HOME=$(win_path "$PROMO51_HOME_POSIX")
PROMO51_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$PROMO51_HOME" run_hook memory-init.js "$PROMO51_CWD" "{\"cwd\":\"$PROMO51_CWD\",\"session_id\":\"promo51\"}")
echo "$PROMO51_OUT" | grep -q "lesson promotion review" && fail "expected no nudge -- no lessons index exists at all, got: $PROMO51_OUT"
pass "lesson-promotion nudge never fires when there is no lessons index to review"

echo "=== Test 52: lesson-promotion nudge -- index touched again after watermark -> nudge fires again ==="
PROMO52_HOME_POSIX="$WORK/promo52_home"
mkdir -p "$PROMO52_HOME_POSIX/.claude/lessons" "$PROMO52_HOME_POSIX/.claude/promotion"
PROMO52_HOME=$(win_path "$PROMO52_HOME_POSIX")
PROMO52_CWD_POSIX="$WORK/promo52_cwd"
mkdir -p "$PROMO52_CWD_POSIX"
PROMO52_CWD=$(win_path "$PROMO52_CWD_POSIX")
PROMO52_OLD_ISO=$(node -e "console.log(new Date(Date.now() - 3600*1000).toISOString())")
node -e "require('fs').writeFileSync('$PROMO52_HOME/.claude/promotion/state.json', JSON.stringify({lastReviewedAt: '$PROMO52_OLD_ISO'}))"
echo "- some-lesson: a generalizable rule (lessons/some-lesson.md)" > "$PROMO52_HOME_POSIX/.claude/lessons/index.md"
# index.md's real mtime (just written, "now") is newer than the hour-old watermark above.
PROMO52_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$PROMO52_HOME" run_hook memory-init.js "$PROMO52_CWD" "{\"cwd\":\"$PROMO52_CWD\",\"session_id\":\"promo52\"}")
echo "$PROMO52_OUT" | grep -q "lesson promotion review" || fail "expected the nudge to fire again -- index changed after the last review, got: $PROMO52_OUT"
pass "lesson-promotion nudge re-fires once the index changes again after a prior review"

echo "=== Test 53: lesson-promotion nudge -- malformed watermark JSON fails open, never silently swallowed ==="
PROMO53_HOME_POSIX="$WORK/promo53_home"
mkdir -p "$PROMO53_HOME_POSIX/.claude/lessons" "$PROMO53_HOME_POSIX/.claude/promotion"
PROMO53_HOME=$(win_path "$PROMO53_HOME_POSIX")
PROMO53_CWD_POSIX="$WORK/promo53_cwd"
mkdir -p "$PROMO53_CWD_POSIX"
PROMO53_CWD=$(win_path "$PROMO53_CWD_POSIX")
echo "- some-lesson: a generalizable rule (lessons/some-lesson.md)" > "$PROMO53_HOME_POSIX/.claude/lessons/index.md"
echo "{not valid json" > "$PROMO53_HOME_POSIX/.claude/promotion/state.json"
PROMO53_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$PROMO53_HOME" run_hook memory-init.js "$PROMO53_CWD" "{\"cwd\":\"$PROMO53_CWD\",\"session_id\":\"promo53\"}")
echo "$PROMO53_OUT" | grep -q "lesson promotion review" || fail "expected the nudge to fire open on a malformed watermark file, got: $PROMO53_OUT"
pass "lesson-promotion nudge fails open (fires) on a malformed promotion/state.json, never silently treated as reviewed"

echo "=== Test 54: lesson-promotion nudge -- whitespace-only lessons index (all lessons promoted out) -> silent ==="
PROMO54_HOME_POSIX="$WORK/promo54_home"
mkdir -p "$PROMO54_HOME_POSIX/.claude/lessons"
PROMO54_HOME=$(win_path "$PROMO54_HOME_POSIX")
PROMO54_CWD_POSIX="$WORK/promo54_cwd"
mkdir -p "$PROMO54_CWD_POSIX"
PROMO54_CWD=$(win_path "$PROMO54_CWD_POSIX")
printf '   \n\n  \n' > "$PROMO54_HOME_POSIX/.claude/lessons/index.md"
PROMO54_OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$PROMO54_HOME" run_hook memory-init.js "$PROMO54_CWD" "{\"cwd\":\"$PROMO54_CWD\",\"session_id\":\"promo54\"}")
echo "$PROMO54_OUT" | grep -q "lesson promotion review" && fail "expected no nudge -- index exists but is whitespace-only (every lesson already promoted out), got: $PROMO54_OUT"
pass "lesson-promotion nudge stays silent on a whitespace-only lessons index"

echo "=== Test 55: design-lane-gate-check.js -- native <select> added in a UI file surfaces a next-turn nudge ==="
DLG55_PROJECT_POSIX="$WORK/dlg55_project"
mkdir -p "$DLG55_PROJECT_POSIX"
(cd "$DLG55_PROJECT_POSIX" && git init -q)
DLG55_PROJECT=$(win_path "$DLG55_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG55_PROJECT" '{"cwd":"'"$DLG55_PROJECT"'","session_id":"dlgS55","tool_name":"Edit","tool_input":{"file_path":"src/components/VendorDetail.tsx","new_string":"<select value={x} onChange={y}><option>A</option></select>"}}' > /dev/null
OUT=$(run_hook design-lane-gate-check.js "$DLG55_PROJECT" '{"cwd":"'"$DLG55_PROJECT"'","session_id":"dlgS55"}')
echo "$OUT" | grep -q "native-control blind spot" || fail "expected a native-control nudge after adding <select>, got: $OUT"
pass "design-lane-gate-check.js surfaces a native-control nudge when <select> is added"

echo "=== Test 56: design-lane-gate-check.js -- self-closing <select /> also fires the native-control nudge ==="
DLG56_PROJECT_POSIX="$WORK/dlg56_project"
mkdir -p "$DLG56_PROJECT_POSIX"
(cd "$DLG56_PROJECT_POSIX" && git init -q)
DLG56_PROJECT=$(win_path "$DLG56_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG56_PROJECT" '{"cwd":"'"$DLG56_PROJECT"'","session_id":"dlgS56","tool_name":"Write","tool_input":{"file_path":"src/components/Picker.jsx","content":"const Picker = () => <select />;"}}' > /dev/null
OUT=$(run_hook design-lane-gate-check.js "$DLG56_PROJECT" '{"cwd":"'"$DLG56_PROJECT"'","session_id":"dlgS56"}')
echo "$OUT" | grep -q "native-control blind spot" || fail "expected a native-control nudge for self-closing <select />, got: $OUT"
pass "design-lane-gate-check.js catches a self-closing <select /> too"

echo "=== Test 57: design-lane-gate-check.js -- native <input type=\"date\"> also fires the native-control nudge ==="
DLG57_PROJECT_POSIX="$WORK/dlg57_project"
mkdir -p "$DLG57_PROJECT_POSIX"
(cd "$DLG57_PROJECT_POSIX" && git init -q)
DLG57_PROJECT=$(win_path "$DLG57_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG57_PROJECT" '{"cwd":"'"$DLG57_PROJECT"'","session_id":"dlgS57","tool_name":"Edit","tool_input":{"file_path":"src/components/Filters.tsx","new_string":"<input type=\"date\" value={d} />"}}' > /dev/null
OUT=$(run_hook design-lane-gate-check.js "$DLG57_PROJECT" '{"cwd":"'"$DLG57_PROJECT"'","session_id":"dlgS57"}')
echo "$OUT" | grep -q "native-control blind spot" || fail "expected a native-control nudge for <input type=\"date\">, got: $OUT"
pass "design-lane-gate-check.js catches native <input type=\"date\"> too"

echo "=== Test 58: design-lane-gate-check.js -- a capitalized custom <Select> component does not false-positive ==="
DLG58_PROJECT_POSIX="$WORK/dlg58_project"
mkdir -p "$DLG58_PROJECT_POSIX"
(cd "$DLG58_PROJECT_POSIX" && git init -q)
DLG58_PROJECT=$(win_path "$DLG58_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG58_PROJECT" '{"cwd":"'"$DLG58_PROJECT"'","session_id":"dlgS58","tool_name":"Edit","tool_input":{"file_path":"src/components/Filters.tsx","new_string":"<Select value={d} options={opts} />"}}' > /dev/null
OUT=$(run_hook design-lane-gate-check.js "$DLG58_PROJECT" '{"cwd":"'"$DLG58_PROJECT"'","session_id":"dlgS58"}')
echo "$OUT" | grep -q "native-control blind spot" && fail "a capitalized custom <Select> component must not be treated as a native control, got: $OUT"
pass "design-lane-gate-check.js does not false-positive on a custom <Select> component"

echo "=== Test 58b: design-lane-gate-check.js -- a capitalized custom <Input type=\"date\"> component does not false-positive ==="
DLG58B_PROJECT_POSIX="$WORK/dlg58b_project"
mkdir -p "$DLG58B_PROJECT_POSIX"
(cd "$DLG58B_PROJECT_POSIX" && git init -q)
DLG58B_PROJECT=$(win_path "$DLG58B_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG58B_PROJECT" '{"cwd":"'"$DLG58B_PROJECT"'","session_id":"dlgS58b","tool_name":"Edit","tool_input":{"file_path":"src/components/Filters.tsx","new_string":"<Input type=\"date\" value={d} onChange={y} />"}}' > /dev/null
OUT=$(run_hook design-lane-gate-check.js "$DLG58B_PROJECT" '{"cwd":"'"$DLG58B_PROJECT"'","session_id":"dlgS58b"}')
echo "$OUT" | grep -q "native-control blind spot" && fail "a capitalized custom <Input type=\"date\"> component must not be treated as a native control, got: $OUT"
pass "design-lane-gate-check.js does not false-positive on a custom <Input type=\"date\"> component"

echo "=== Test 59: design-lane-gate-check.js -- native-control nudge is independent of the screenshot-MISS pending, neither overwrites the other ==="
DLG59_PROJECT_POSIX="$WORK/dlg59_project"
mkdir -p "$DLG59_PROJECT_POSIX"
(cd "$DLG59_PROJECT_POSIX" && git init -q)
DLG59_PROJECT=$(win_path "$DLG59_PROJECT_POSIX")
run_hook design-lane-gate-check.js "$DLG59_PROJECT" '{"cwd":"'"$DLG59_PROJECT"'","session_id":"dlgS59","tool_name":"Edit","tool_input":{"file_path":"src/components/Card.tsx"}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG59_PROJECT" '{"cwd":"'"$DLG59_PROJECT"'","session_id":"dlgS59","tool_name":"Bash","tool_input":{"command":"git commit -m \"card\""}}' > /dev/null
run_hook design-lane-gate-check.js "$DLG59_PROJECT" '{"cwd":"'"$DLG59_PROJECT"'","session_id":"dlgS59","tool_name":"Edit","tool_input":{"file_path":"src/components/Card.tsx","new_string":"<select><option>x</option></select>"}}' > /dev/null
OUT=$(run_hook design-lane-gate-check.js "$DLG59_PROJECT" '{"cwd":"'"$DLG59_PROJECT"'","session_id":"dlgS59"}')
echo "$OUT" | grep -q "design-lane gate miss" || fail "expected the screenshot-MISS block too, got: $OUT"
echo "$OUT" | grep -q "native-control blind spot" || fail "expected the native-control block alongside the screenshot-MISS, got: $OUT"
pass "design-lane-gate-check.js surfaces both nudges together when both are pending, neither overwrites the other"

echo "=== Test 60: visual-plan-gate-check.js -- non-trivial plan file + ExitPlanMode with no Artifact publish logs a MISS ==="
VPG60_HOME_POSIX="$WORK/vpg60_home"
mkdir -p "$VPG60_HOME_POSIX/.claude/plans"
VPG60_HOME=$(win_path "$VPG60_HOME_POSIX")
VPG60_CWD_POSIX="$WORK/vpg60_cwd"
mkdir -p "$VPG60_CWD_POSIX"
VPG60_CWD=$(win_path "$VPG60_CWD_POSIX")
VPG60_PLANS_WIN=$(win_path "$VPG60_HOME_POSIX/.claude/plans")
VPG60_PLAN="$VPG60_PLANS_WIN/test-plan.md"
{ printf '# Plan\n\n'; printf '%1300s' | tr ' ' 'x'; printf '\n'; } > "$VPG60_HOME_POSIX/.claude/plans/test-plan.md"
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG60_HOME" run_hook visual-plan-gate-check.js "$VPG60_CWD" '{"cwd":"'"$VPG60_CWD"'","session_id":"vpgS60","tool_name":"Write","tool_input":{"file_path":"'"$VPG60_PLAN"'","content":"placeholder"}}' > /dev/null
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG60_HOME" run_hook visual-plan-gate-check.js "$VPG60_CWD" '{"cwd":"'"$VPG60_CWD"'","session_id":"vpgS60","tool_name":"ExitPlanMode","tool_input":{}}' > /dev/null
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$VPG60_HOME" run_hook visual-plan-gate-check.js "$VPG60_CWD" '{"cwd":"'"$VPG60_CWD"'","session_id":"vpgS60"}')
echo "$OUT" | grep -q "visual-plan gate miss" || fail "expected a visual-plan gate MISS for a non-trivial plan with no Artifact, got: $OUT"
pass "visual-plan-gate-check.js logs a MISS when a non-trivial plan exits plan mode with no Artifact publish"

echo "=== Test 61: visual-plan-gate-check.js -- Artifact published before ExitPlanMode suppresses the MISS ==="
VPG61_HOME_POSIX="$WORK/vpg61_home"
mkdir -p "$VPG61_HOME_POSIX/.claude/plans"
VPG61_HOME=$(win_path "$VPG61_HOME_POSIX")
VPG61_CWD_POSIX="$WORK/vpg61_cwd"
mkdir -p "$VPG61_CWD_POSIX"
VPG61_CWD=$(win_path "$VPG61_CWD_POSIX")
VPG61_PLANS_WIN=$(win_path "$VPG61_HOME_POSIX/.claude/plans")
VPG61_PLAN="$VPG61_PLANS_WIN/test-plan.md"
{ printf '# Plan\n\n'; printf '%1300s' | tr ' ' 'x'; printf '\n'; } > "$VPG61_HOME_POSIX/.claude/plans/test-plan.md"
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG61_HOME" run_hook visual-plan-gate-check.js "$VPG61_CWD" '{"cwd":"'"$VPG61_CWD"'","session_id":"vpgS61","tool_name":"Write","tool_input":{"file_path":"'"$VPG61_PLAN"'","content":"placeholder"}}' > /dev/null
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG61_HOME" run_hook visual-plan-gate-check.js "$VPG61_CWD" '{"cwd":"'"$VPG61_CWD"'","session_id":"vpgS61","tool_name":"Artifact","tool_input":{"file_path":"scratch.html"}}' > /dev/null
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG61_HOME" run_hook visual-plan-gate-check.js "$VPG61_CWD" '{"cwd":"'"$VPG61_CWD"'","session_id":"vpgS61","tool_name":"ExitPlanMode","tool_input":{}}' > /dev/null
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$VPG61_HOME" run_hook visual-plan-gate-check.js "$VPG61_CWD" '{"cwd":"'"$VPG61_CWD"'","session_id":"vpgS61"}')
echo "$OUT" | grep -q "visual-plan gate miss" && fail "an Artifact published before ExitPlanMode should suppress the MISS, got: $OUT"
pass "visual-plan-gate-check.js stays silent when an Artifact was published before ExitPlanMode"

echo "=== Test 62: visual-plan-gate-check.js -- a trivial (short) plan stays silent even with no Artifact ==="
VPG62_HOME_POSIX="$WORK/vpg62_home"
mkdir -p "$VPG62_HOME_POSIX/.claude/plans"
VPG62_HOME=$(win_path "$VPG62_HOME_POSIX")
VPG62_CWD_POSIX="$WORK/vpg62_cwd"
mkdir -p "$VPG62_CWD_POSIX"
VPG62_CWD=$(win_path "$VPG62_CWD_POSIX")
VPG62_PLANS_WIN=$(win_path "$VPG62_HOME_POSIX/.claude/plans")
VPG62_PLAN="$VPG62_PLANS_WIN/test-plan.md"
printf '# Fix a typo\n\nChange "recieve" to "receive" in README.md.\n' > "$VPG62_HOME_POSIX/.claude/plans/test-plan.md"
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62_HOME" run_hook visual-plan-gate-check.js "$VPG62_CWD" '{"cwd":"'"$VPG62_CWD"'","session_id":"vpgS62","tool_name":"Write","tool_input":{"file_path":"'"$VPG62_PLAN"'","content":"placeholder"}}' > /dev/null
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62_HOME" run_hook visual-plan-gate-check.js "$VPG62_CWD" '{"cwd":"'"$VPG62_CWD"'","session_id":"vpgS62","tool_name":"ExitPlanMode","tool_input":{}}' > /dev/null
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62_HOME" run_hook visual-plan-gate-check.js "$VPG62_CWD" '{"cwd":"'"$VPG62_CWD"'","session_id":"vpgS62"}')
echo "$OUT" | grep -q "visual-plan gate miss" && fail "a trivial short plan should never trigger a MISS, got: $OUT"
pass "visual-plan-gate-check.js stays silent for a genuinely trivial plan"

echo "=== Test 62b: visual-plan-gate-check.js -- short plan with 2+ file-path mentions is non-trivial by the file-mention branch, logs a MISS ==="
VPG62B_HOME_POSIX="$WORK/vpg62b_home"
mkdir -p "$VPG62B_HOME_POSIX/.claude/plans"
VPG62B_HOME=$(win_path "$VPG62B_HOME_POSIX")
VPG62B_CWD_POSIX="$WORK/vpg62b_cwd"
mkdir -p "$VPG62B_CWD_POSIX"
VPG62B_CWD=$(win_path "$VPG62B_CWD_POSIX")
VPG62B_PLANS_WIN=$(win_path "$VPG62B_HOME_POSIX/.claude/plans")
VPG62B_PLAN="$VPG62B_PLANS_WIN/test-plan.md"
printf '# Plan\n\n## Files to change\n- `src/App.tsx`\n- `src/utils/helpers.ts`\n' > "$VPG62B_HOME_POSIX/.claude/plans/test-plan.md"
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62B_HOME" run_hook visual-plan-gate-check.js "$VPG62B_CWD" '{"cwd":"'"$VPG62B_CWD"'","session_id":"vpgS62b","tool_name":"Write","tool_input":{"file_path":"'"$VPG62B_PLAN"'","content":"placeholder"}}' > /dev/null
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62B_HOME" run_hook visual-plan-gate-check.js "$VPG62B_CWD" '{"cwd":"'"$VPG62B_CWD"'","session_id":"vpgS62b","tool_name":"ExitPlanMode","tool_input":{}}' > /dev/null
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62B_HOME" run_hook visual-plan-gate-check.js "$VPG62B_CWD" '{"cwd":"'"$VPG62B_CWD"'","session_id":"vpgS62b"}')
echo "$OUT" | grep -q "visual-plan gate miss" || fail "expected a MISS via the file-mention branch (short plan, 2+ file paths), got: $OUT"
pass "visual-plan-gate-check.js's file-mention non-trivial branch fires independent of the length branch"

echo "=== Test 62c: visual-plan-gate-check.js -- short plan with only 1 file-path mention stays under both non-trivial thresholds, silent ==="
VPG62C_HOME_POSIX="$WORK/vpg62c_home"
mkdir -p "$VPG62C_HOME_POSIX/.claude/plans"
VPG62C_HOME=$(win_path "$VPG62C_HOME_POSIX")
VPG62C_CWD_POSIX="$WORK/vpg62c_cwd"
mkdir -p "$VPG62C_CWD_POSIX"
VPG62C_CWD=$(win_path "$VPG62C_CWD_POSIX")
VPG62C_PLANS_WIN=$(win_path "$VPG62C_HOME_POSIX/.claude/plans")
VPG62C_PLAN="$VPG62C_PLANS_WIN/test-plan.md"
printf '# Plan\n\nTouches `src/App.tsx` only.\n' > "$VPG62C_HOME_POSIX/.claude/plans/test-plan.md"
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62C_HOME" run_hook visual-plan-gate-check.js "$VPG62C_CWD" '{"cwd":"'"$VPG62C_CWD"'","session_id":"vpgS62c","tool_name":"Write","tool_input":{"file_path":"'"$VPG62C_PLAN"'","content":"placeholder"}}' > /dev/null
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62C_HOME" run_hook visual-plan-gate-check.js "$VPG62C_CWD" '{"cwd":"'"$VPG62C_CWD"'","session_id":"vpgS62c","tool_name":"ExitPlanMode","tool_input":{}}' > /dev/null
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$VPG62C_HOME" run_hook visual-plan-gate-check.js "$VPG62C_CWD" '{"cwd":"'"$VPG62C_CWD"'","session_id":"vpgS62c"}')
echo "$OUT" | grep -q "visual-plan gate miss" && fail "a single file-path mention under the length threshold should stay trivial, got: $OUT"
pass "visual-plan-gate-check.js stays silent when only one file-path mention exists and length is under threshold"

echo "=== Test 63: visual-plan-gate-check.js -- ExitPlanMode with no tracked plan file fails open (no crash, no MISS) ==="
VPG63_HOME_POSIX="$WORK/vpg63_home"
mkdir -p "$VPG63_HOME_POSIX/.claude/plans"
VPG63_HOME=$(win_path "$VPG63_HOME_POSIX")
VPG63_CWD_POSIX="$WORK/vpg63_cwd"
mkdir -p "$VPG63_CWD_POSIX"
VPG63_CWD=$(win_path "$VPG63_CWD_POSIX")
CLAUDE_HARNESS_HOME_OVERRIDE="$VPG63_HOME" run_hook visual-plan-gate-check.js "$VPG63_CWD" '{"cwd":"'"$VPG63_CWD"'","session_id":"vpgS63","tool_name":"ExitPlanMode","tool_input":{}}' > /dev/null || fail "visual-plan-gate-check.js must not crash on ExitPlanMode with no tracked plan file"
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$VPG63_HOME" run_hook visual-plan-gate-check.js "$VPG63_CWD" '{"cwd":"'"$VPG63_CWD"'","session_id":"vpgS63"}')
echo "$OUT" | grep -q "visual-plan gate miss" && fail "no plan file was ever tracked -- there is nothing to judge, expected silence, got: $OUT"
pass "visual-plan-gate-check.js fails open when no plan file was ever tracked"

echo "=== Test 64: visual-plan-gate-check.js -- an irrelevant tool call touches no state at all (early-return) ==="
VPG64_PROJECT_POSIX="$WORK/vpg64_project"
mkdir -p "$VPG64_PROJECT_POSIX"
(cd "$VPG64_PROJECT_POSIX" && git init -q)
VPG64_PROJECT=$(win_path "$VPG64_PROJECT_POSIX")
run_hook visual-plan-gate-check.js "$VPG64_PROJECT" '{"cwd":"'"$VPG64_PROJECT"'","session_id":"vpgS64","tool_name":"Read","tool_input":{"file_path":"README.md"}}' > /dev/null
[ -d "$VPG64_PROJECT_POSIX/.claude/visual-plan-gate" ] && fail "a Read on an unrelated file should never create the state dir at all: $(ls "$VPG64_PROJECT_POSIX/.claude/visual-plan-gate" 2>/dev/null)"
pass "visual-plan-gate-check.js skips all state I/O for a tool call that could not change either flag"

echo "=== Test 65: architecture note IDs that escape the notes dir are rejected before they become paths ==="
# Both the index file and the watch map are repo-tracked -- an id like
# ../../../.ssh/config would otherwise be path.join()'d into a write target
# outside <scope>/architecture/notes/.
TRAVERSAL_JSON=$(node -e "
const lib = require('$HOOKS_WIN/_lib.js');
const bad = ['../../../.ssh/config', 'a/b', 'x\\\\y', '..', '.hidden'];
const good = ['auth-flow', 'Auth_Flow.v2', 'a1'];
console.log(JSON.stringify({
  badIds: bad.filter((id) => lib.isSafeNoteId(id)),
  goodIds: good.filter((id) => !lib.isSafeNoteId(id)),
  badLine: lib.parseArchIndexLine('../../../.ssh/config | proj | tags | summary | notes/x.md'),
  goodLine: !!lib.parseArchIndexLine('auth-flow | proj | tags | summary | notes/auth-flow.md'),
}));
")
echo "$TRAVERSAL_JSON" | grep -q '"badIds":\[\]' || fail "isSafeNoteId accepted a traversing/unsafe note id: $TRAVERSAL_JSON"
echo "$TRAVERSAL_JSON" | grep -q '"goodIds":\[\]' || fail "isSafeNoteId rejected an ordinary note id: $TRAVERSAL_JSON"
echo "$TRAVERSAL_JSON" | grep -q '"badLine":null' || fail "parseArchIndexLine kept an index row whose id escapes the notes dir: $TRAVERSAL_JSON"
echo "$TRAVERSAL_JSON" | grep -q '"goodLine":true' || fail "parseArchIndexLine dropped a legitimate index row: $TRAVERSAL_JSON"
pass "note ids that would escape architecture/notes/ are rejected at parse time, ordinary ids still pass"

echo "=== Test 66: watch-map entries with unsafe ids are dropped, safe siblings survive ==="
WATCH_POSIX="$WORK/watchmap_proj"
mkdir -p "$WATCH_POSIX/.claude/architecture"
printf '{"src/app.ts":["auth-flow","../../../.ssh/config"],"src/b.ts":["../evil"]}' \
  > "$WATCH_POSIX/.claude/architecture/watch-map.json"
WATCH_MAP_JSON=$(node -e "
const lib = require('$HOOKS_WIN/_lib.js');
console.log(JSON.stringify(lib.readWatchMap('$(win_path "$WATCH_POSIX")/.claude')));
")
echo "$WATCH_MAP_JSON" | grep -q '\.ssh' && fail "readWatchMap passed a traversing id through to the note-path builder: $WATCH_MAP_JSON"
echo "$WATCH_MAP_JSON" | grep -q '"src/b.ts"' && fail "an entry whose only id was unsafe should drop out entirely: $WATCH_MAP_JSON"
echo "$WATCH_MAP_JSON" | grep -q 'auth-flow' || fail "readWatchMap dropped a safe id alongside the unsafe one: $WATCH_MAP_JSON"
pass "readWatchMap keeps safe ids and drops the ones that would escape the notes dir"

echo "=== Test 67: stripSecrets redacts the credential classes this pack's own machine holds ==="
REDACT_OUT=$(node -e "
const lib = require('$HOOKS_WIN/_lib.js');
const samples = [
  'key sk-ant-api03-AAAABBBBCCCCDDDDEEEE',
  'Authorization: Bearer abcdefghijklmnop0123456789',
  'token: \"hunter2hunter2\"',
];
console.log(samples.map((s) => lib.stripSecrets(s)).join('\n'));
")
echo "$REDACT_OUT" | grep -q 'sk-ant-api03' && fail "an Anthropic key survived stripSecrets: $REDACT_OUT"
echo "$REDACT_OUT" | grep -q 'abcdefghijklmnop' && fail "a bearer token survived stripSecrets: $REDACT_OUT"
echo "$REDACT_OUT" | grep -q 'hunter2' && fail "a quoted token assignment survived stripSecrets: $REDACT_OUT"
pass "stripSecrets redacts Anthropic keys, bearer tokens, and quoted token assignments"

echo "=== Test 65: an unparseable hook payload is recorded, not silently treated as an empty one ==="
# Every hook here is fail-open by contract, which means a payload shape that
# stopped parsing degrades into a permanent silent no-op -- indistinguishable
# from "nothing to do". Exit 0 must survive; silence must not.
D65_HOME_POSIX="$WORK/diag65_home"
mkdir -p "$D65_HOME_POSIX"
D65_HOME=$(win_path "$D65_HOME_POSIX")
D65_CWD_POSIX="$WORK/diag65_cwd"
mkdir -p "$D65_CWD_POSIX"
D65_CWD=$(win_path "$D65_CWD_POSIX")
CLAUDE_HARNESS_HOME_OVERRIDE="$D65_HOME" run_hook memory-checkpoint.js "$D65_CWD" '{"cwd":"not closed' > /dev/null \
  || fail "a malformed payload must still exit 0 -- fail-open is not negotiable"
D65_LOG="$D65_HOME_POSIX/.claude/diagnostics/hook-errors.log"
[ -f "$D65_LOG" ] || fail "malformed payload left no diagnostic record at $D65_LOG"
grep -q 'unparseable hook payload' "$D65_LOG" || fail "diagnostic recorded but not identifiable as a payload-parse failure: $(cat "$D65_LOG")"
grep -q 'memory-checkpoint.js' "$D65_LOG" || fail "diagnostic does not name the hook that failed: $(cat "$D65_LOG")"
pass "an unparseable hook payload still exits 0 but leaves an attributable diagnostic"

echo "=== Test 66: SessionStart surfaces recent hook errors, and stays silent about stale ones ==="
D66_HOME_POSIX="$WORK/diag66_home"
mkdir -p "$D66_HOME_POSIX/.claude/diagnostics"
D66_HOME=$(win_path "$D66_HOME_POSIX")
D66_CWD_POSIX="$WORK/diag66_cwd"
mkdir -p "$D66_CWD_POSIX"
D66_CWD=$(win_path "$D66_CWD_POSIX")
D66_LOG="$D66_HOME_POSIX/.claude/diagnostics/hook-errors.log"
printf '%s | memory-compact.js | memory-compact failed | Error: EACCES\n' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" > "$D66_LOG"
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$D66_HOME" run_hook memory-init.js "$D66_CWD" '{"cwd":"'"$D66_CWD"'","session_id":"d66"}')
echo "$OUT" | grep -q 'memory hook errors' || fail "SessionStart did not surface a recent hook error at all, got: $OUT"
echo "$OUT" | grep -q 'memory-compact failed' || fail "rollup surfaced no identifying detail from the recorded error, got: $OUT"
# Older than the 7-day window: a problem that was already fixed must stop being
# reported, same silence-when-clean rule as the canary rollup.
printf '2020-01-01T00:00:00.000Z | memory-compact.js | memory-compact failed | Error: EACCES\n' > "$D66_LOG"
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$D66_HOME" run_hook memory-init.js "$D66_CWD" '{"cwd":"'"$D66_CWD"'","session_id":"d66b"}')
echo "$OUT" | grep -q 'memory hook errors' && fail "a hook error well outside the reporting window must not be surfaced, got: $OUT"
pass "SessionStart reports recent hook errors and drops ones outside the window"

echo "=== Test 67: corrupt gate state is quarantined, not silently overwritten ==="
# Reading corrupt state as {} and then writing over it destroys every unresolved
# miss in the file with no EXPIRED line and no trace -- the exact loss
# pruneIdleGateSessions' EXPIRED lines exist to prevent.
D67_PROJECT_POSIX="$WORK/diag67_project"
mkdir -p "$D67_PROJECT_POSIX/.claude/canary"
(cd "$D67_PROJECT_POSIX" && git init -q)
D67_PROJECT=$(win_path "$D67_PROJECT_POSIX")
D67_STATE="$D67_PROJECT_POSIX/.claude/canary/state.json"
printf '{"sX":{"pending":{"file":"WORKFLOW.md"' > "$D67_STATE"
run_hook canary-check.js "$D67_PROJECT" '{"cwd":"'"$D67_PROJECT"'","session_id":"sY"}' > /dev/null \
  || fail "corrupt gate state must not stop the hook from exiting 0"
[ -f "$D67_STATE.corrupt" ] || fail "corrupt state was overwritten instead of preserved at $D67_STATE.corrupt"
grep -q 'WORKFLOW.md' "$D67_STATE.corrupt" || fail "quarantined file does not contain the original bytes: $(cat "$D67_STATE.corrupt")"
node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$D67_STATE" \
  || fail "hook did not write a valid replacement state file"
grep -q 'corrupt gate state' "$D67_PROJECT_POSIX/.claude/diagnostics/hook-errors.log" 2>/dev/null \
  || grep -q 'corrupt gate state' "$FAKE_HOME_POSIX/.claude/diagnostics/hook-errors.log" \
  || fail "corrupt state was quarantined but never recorded as an error"
pass "corrupt gate state is quarantined and recorded, and the gate keeps working"

echo "=== Test 68: a session whose lastSeen is unparseable still gets pruned and closed out ==="
# Date.parse of a corrupt timestamp is NaN, and `NaN < cutoff` is false -- which
# made such a session immortal: never pruned, its open miss never EXPIRED.
D68_PROJECT_POSIX="$WORK/diag68_project"
mkdir -p "$D68_PROJECT_POSIX/.claude/canary"
(cd "$D68_PROJECT_POSIX" && git init -q)
D68_PROJECT=$(win_path "$D68_PROJECT_POSIX")
printf '{"stale":{"offset":0,"pending":{"file":"WORKFLOW.md","at":"whenever"},"lastSeen":"not-a-timestamp"}}' \
  > "$D68_PROJECT_POSIX/.claude/canary/state.json"
run_hook canary-check.js "$D68_PROJECT" '{"cwd":"'"$D68_PROJECT"'","session_id":"fresh"}' > /dev/null
grep -q 'EXPIRED' "$D68_PROJECT_POSIX/.claude/canary/log.md" || fail "no EXPIRED line logged for the pruned session: $(cat "$D68_PROJECT_POSIX/.claude/canary/log.md" 2>/dev/null)"
node -e "
  const s = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
  if (s.stale) { console.error('session with a corrupt lastSeen survived pruning'); process.exit(1); }
" "$D68_PROJECT_POSIX/.claude/canary/state.json" || fail "session with an unparseable lastSeen was never pruned"
pass "an unparseable lastSeen reads as idle: the session is pruned and its open miss logged EXPIRED"

echo "=== Test 69: a malformed watch-map is recorded instead of silently disabling file-touch recall ==="
D69_PROJECT_POSIX="$WORK/diag69_project"
mkdir -p "$D69_PROJECT_POSIX/.claude/architecture"
(cd "$D69_PROJECT_POSIX" && git init -q)
D69_PROJECT=$(win_path "$D69_PROJECT_POSIX")
D69_HOME_POSIX="$WORK/diag69_home"
mkdir -p "$D69_HOME_POSIX"
D69_HOME=$(win_path "$D69_HOME_POSIX")
printf '{"src/app.js": [' > "$D69_PROJECT_POSIX/.claude/architecture/watch-map.json"
CLAUDE_HARNESS_HOME_OVERRIDE="$D69_HOME" run_hook memory-architecture.js "$D69_PROJECT" '{"cwd":"'"$D69_PROJECT"'","tool_name":"Read","tool_input":{"file_path":"'"$D69_PROJECT"'/src/app.js"}}' > /dev/null \
  || fail "a malformed watch-map must not stop the hook from exiting 0"
grep -q 'malformed' "$D69_HOME_POSIX/.claude/diagnostics/hook-errors.log" \
  || fail "malformed watch-map left no diagnostic: $(cat "$D69_HOME_POSIX/.claude/diagnostics/hook-errors.log" 2>/dev/null)"
pass "a malformed watch-map.json is recorded rather than silently disabling recall"

echo "=== Test 70: the diagnostics log is bounded -- a permanently failing hook cannot grow it forever ==="
D70_HOME_POSIX="$WORK/diag70_home"
mkdir -p "$D70_HOME_POSIX/.claude/diagnostics"
D70_HOME=$(win_path "$D70_HOME_POSIX")
D70_CWD_POSIX="$WORK/diag70_cwd"
mkdir -p "$D70_CWD_POSIX"
D70_CWD=$(win_path "$D70_CWD_POSIX")
D70_LOG="$D70_HOME_POSIX/.claude/diagnostics/hook-errors.log"
node -e "
  const fs = require('fs');
  const line = new Array(200).join('x');
  fs.writeFileSync(process.argv[1], Array.from({ length: 2000 }, (_, i) => '2026-01-01T00:00:00.000Z | pad | pad ' + i + ' | ' + line).join('\n') + '\n');
" "$D70_LOG"
CLAUDE_HARNESS_HOME_OVERRIDE="$D70_HOME" run_hook memory-checkpoint.js "$D70_CWD" '{"cwd":"broken' > /dev/null
D70_SIZE=$(node -e "process.stdout.write(String(require('fs').statSync(process.argv[1]).size))" "$D70_LOG")
[ "$D70_SIZE" -le 65536 ] || fail "diagnostics log was not trimmed back under its cap, size is $D70_SIZE"
grep -q 'unparseable hook payload' "$D70_LOG" || fail "trim dropped the newest entry -- the one that just happened: $(tail -1 "$D70_LOG")"
pass "the diagnostics log stays under its size cap and keeps the newest entries"

echo "=== Test 71: a failed atomic write leaves no temp file behind ==="
# atomicWrite used to leak its scratch file on a failed rename, under a name
# nothing reads or cleans up. Forced here by making the rename target a
# directory, which no write can replace.
D71_DIR_POSIX="$WORK/diag71"
mkdir -p "$D71_DIR_POSIX/target.md"
node -e "
  const lib = require(process.argv[1] + '/_lib.js');
  const target = process.argv[2] + '/target.md';
  let threw = false;
  try { lib.atomicWrite(target, 'content'); } catch (_) { threw = true; }
  if (!threw) { console.error('atomicWrite silently succeeded against an unwritable target'); process.exit(1); }
  const leftover = require('fs').readdirSync(process.argv[2]).filter((f) => f.includes('.tmp.'));
  if (leftover.length) { console.error('leftover temp file(s): ' + leftover.join(', ')); process.exit(1); }
" "$HOOKS_WIN" "$(win_path "$D71_DIR_POSIX")" || fail "atomicWrite either swallowed the failure or leaked a temp file"
pass "a failed atomicWrite propagates the error to its caller and cleans up its temp file"

echo ""
echo "=== Test 65: isGitCommitCommand -- real commit shapes match, mere MENTIONS of a commit do not ==="
# Adversarial in both directions. The pre-2026-08-27 matcher (`\bgit\b...\bcommit\b`)
# was only ever checked against `git commit -m "x"`. It was never fed the commit
# forms this pack's OWN instructions mandate (PowerShell here-string, bash
# heredoc), nor the ordinary Bash calls that merely name a commit -- and it
# false-fired on the latter, logging a MISS for a commit that never ran.
cat > "$WORK/t65.js" <<'T65'
const lib = require(process.argv[2] + '/_lib.js');
// [label, command, mustMatch]
const CASES = [
  // real commit shapes -- every one of these MUST fire the gate
  ['plain', 'git commit -m "fix"', true],
  ['add chained', 'git add -A && git commit -m "fix"', true],
  ['amend', 'git commit --amend --no-edit', true],
  ['-am', 'git commit -am "fix"', true],
  ['bare (opens editor)', 'git commit', true],
  ['git -C <path>', 'git -C /repo commit -m x', true],
  ['cd then commit', 'cd /repo; git commit -m x', true],
  ['rtk wrapper (this pack ships rtk)', 'rtk git commit -m x', true],
  ['bash heredoc -F -', 'git commit -F - <<EOF\nsubject\n\nbody\nEOF', true],
  ['PowerShell here-string (CLAUDE.md mandates this form)', "git commit -m @'\nsubject line\n\nbody with $literal\n'@", true],
  ['command substitution', '$(git commit -m x)', true],

  // NOT a commit -- these must stay silent
  ['path naming a commit doc', 'cat docs/git-commit-pr.md', false],
  ['hyphenated token', 'ls .github/git-commit-hooks/', false],
  ['docker commit after git status', 'git status && docker commit foo', false],
  ['git log format', 'git log --format=%s', false],
  ['no git at all', 'npm run build', false],
];
let bad = [];
for (const [label, cmd, want] of CASES) {
  const got = lib.isGitCommitCommand(cmd);
  if (got !== want) bad.push(`${want ? 'MISSED' : 'FALSE-FIRED'}: ${label}`);
}
console.log(bad.length ? 'BAD ' + bad.join(' | ') : 'OK');
T65
T65_OUT=$(node "$WORK/t65.js" "$HOOKS_WIN")
[ "$T65_OUT" = "OK" ] || fail "isGitCommitCommand mismatch -> $T65_OUT"
pass "isGitCommitCommand: 11 real commit shapes match, 5 commit-mentions do not"

echo "=== Test 66: session scope is PINNED -- one session_id cannot split its state across two scopes ==="
# The external audit's finding #5, as an executable regression. A hook's
# `input.cwd` follows the Bash tool's PERSISTED cwd, so one `cd` mid-session
# used to move every later write into a different scope, silently losing state.
PIN_HOME_POSIX="$WORK/pin_home"
mkdir -p "$PIN_HOME_POSIX/.claude"          # pack installed here -> pinning active
PIN_HOME=$(win_path "$PIN_HOME_POSIX")
PIN_A_POSIX="$WORK/pin_repo_a"; mkdir -p "$PIN_A_POSIX"; (cd "$PIN_A_POSIX" && git init -q)
PIN_B_POSIX="$WORK/pin_repo_b"; mkdir -p "$PIN_B_POSIX"; (cd "$PIN_B_POSIX" && git init -q)
PIN_A=$(win_path "$PIN_A_POSIX"); PIN_B=$(win_path "$PIN_B_POSIX")

# turn 1: session starts in repo A -> pin taken from the launch cwd
CLAUDE_HARNESS_HOME_OVERRIDE="$PIN_HOME" run_hook review-gate-check.js "$PIN_A" '{"cwd":"'"$PIN_A"'","session_id":"pinS1","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
[ -f "$PIN_A_POSIX/.claude/review-gate/state.json" ] || fail "first write should land in repo A"
# turn 2: a Bash `cd` has moved cwd into repo B -- same session
CLAUDE_HARNESS_HOME_OVERRIDE="$PIN_HOME" run_hook review-gate-check.js "$PIN_B" '{"cwd":"'"$PIN_B"'","session_id":"pinS1","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' > /dev/null
[ -e "$PIN_B_POSIX/.claude" ] && fail "REGRESSION (audit finding #5): a cd into repo B split session pinS1's state into a second scope"
grep -q "MISS" "$PIN_A_POSIX/.claude/review-gate/log.md" || fail "the commit MISS should have been logged in the PINNED scope (repo A), not lost: $(cat "$PIN_A_POSIX/.claude/review-gate/log.md" 2>/dev/null)"
grep -q '"pinS1"' "$PIN_HOME_POSIX/.claude/session-scope.json" || fail "pin file missing the session entry: $(cat "$PIN_HOME_POSIX/.claude/session-scope.json" 2>/dev/null)"
pass "one session_id resolves to one scope across a mid-session cwd change, and the pin is recorded at global scope"

echo "=== Test 67: a DIFFERENT session in repo B is unaffected by the pin (no cross-session bleed) ==="
CLAUDE_HARNESS_HOME_OVERRIDE="$PIN_HOME" run_hook review-gate-check.js "$PIN_B" '{"cwd":"'"$PIN_B"'","session_id":"pinS2","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
[ -f "$PIN_B_POSIX/.claude/review-gate/state.json" ] || fail "a genuinely different session in repo B must resolve to repo B"
pass "pinning is per-session -- it does not collapse every session onto the first-seen scope"

echo "=== Test 68: pinning never CREATES <home>/.claude, and an id-less session is never pinned ==="
# Guards the Test 1 invariant: memory-init.js is a pure read at SessionStart and
# must leave no footprint. If pinning created the directory it would break that.
PIN_NOHOME_POSIX="$WORK/pin_nohome"     # deliberately NO .claude inside
mkdir -p "$PIN_NOHOME_POSIX"
PIN_NOHOME=$(win_path "$PIN_NOHOME_POSIX")
PIN_C_POSIX="$WORK/pin_repo_c"; mkdir -p "$PIN_C_POSIX"; (cd "$PIN_C_POSIX" && git init -q)
PIN_C=$(win_path "$PIN_C_POSIX")
CLAUDE_HARNESS_HOME_OVERRIDE="$PIN_NOHOME" run_hook review-gate-check.js "$PIN_C" '{"cwd":"'"$PIN_C"'","session_id":"pinS3","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
[ -e "$PIN_NOHOME_POSIX/.claude" ] && fail "pinning created <home>/.claude as a side effect -- breaks the no-footprint invariant Test 1 guards"
# id-less input: must not be pinned under the literal 'unknown' bucket
CLAUDE_HARNESS_HOME_OVERRIDE="$PIN_HOME" run_hook review-gate-check.js "$PIN_C" '{"cwd":"'"$PIN_C"'","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
grep -q '"unknown"' "$PIN_HOME_POSIX/.claude/session-scope.json" && fail "the 'unknown' session bucket must never be pinned -- all id-less sessions would collide on one scope"
pass "no directory created to pin, and id-less sessions are left unpinned"

echo "=== Test 69: a pin older than the 30-day TTL is pruned ==="
PIN_OLD_ISO=$(node -e "console.log(new Date(Date.now() - 31*24*60*60*1000).toISOString())")
node -e "
const fs = require('fs');
fs.writeFileSync('$PIN_HOME/.claude/session-scope.json', JSON.stringify({
  staleSession: { scope: 'global', base: 'X:/gone', repo: null, at: '$PIN_OLD_ISO' }
}));
"
CLAUDE_HARNESS_HOME_OVERRIDE="$PIN_HOME" run_hook review-gate-check.js "$PIN_C" '{"cwd":"'"$PIN_C"'","session_id":"pinS4","tool_name":"Bash","tool_input":{"command":"ls"}}' > /dev/null
grep -q "staleSession" "$PIN_HOME_POSIX/.claude/session-scope.json" && fail "a pin idle > 30d should have been pruned: $(cat "$PIN_HOME_POSIX/.claude/session-scope.json")"
grep -q "pinS4" "$PIN_HOME_POSIX/.claude/session-scope.json" || fail "the fresh pin should still have been written while pruning"
pass "stale pins are pruned on write, fresh pin survives"

echo ""
echo "=== Test 70: memory-init.js nudges when the injected checkpoint has an empty goal ==="
# Audit finding #2: WORKFLOW.md predicts the empty-goal failure in its own text,
# and a real injected checkpoint had it. Both directions tested -- silence when
# a goal IS present matters as much as the nudge, or the block becomes noise
# every single session and gets tuned out.
GOAL_HOME_POSIX="$WORK/goal_home"; mkdir -p "$GOAL_HOME_POSIX/.claude/session"
GOAL_HOME=$(win_path "$GOAL_HOME_POSIX")
GOAL_CWD_POSIX="$WORK/goal_cwd"; mkdir -p "$GOAL_CWD_POSIX"
GOAL_CWD=$(win_path "$GOAL_CWD_POSIX")
GOAL_CP="$GOAL_HOME_POSIX/.claude/session/checkpoint.md"

# (a) empty goal -> nudge
printf '# Session checkpoint\nscope: global\nsession_id: goalS1\ngoal:\nfiles:\n  - a.js\n' > "$GOAL_CP"
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$GOAL_HOME" run_hook memory-init.js "$GOAL_CWD" '{"cwd":"'"$GOAL_CWD"'","session_id":"goalS1"}')
echo "$OUT" | grep -q "checkpoint had no .goal" || fail "expected an empty-goal nudge, got: $OUT"

# (b) whitespace-only goal -> still a nudge (a space is not a goal)
printf '# Session checkpoint\nscope: global\nsession_id: goalS1\ngoal:    \nfiles:\n  - a.js\n' > "$GOAL_CP"
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$GOAL_HOME" run_hook memory-init.js "$GOAL_CWD" '{"cwd":"'"$GOAL_CWD"'","session_id":"goalS1"}')
echo "$OUT" | grep -q "checkpoint had no .goal" || fail "whitespace-only goal should still nudge, got: $OUT"

# (c) real goal -> silence
printf '# Session checkpoint\nscope: global\nsession_id: goalS1\ngoal: ship the wiring verifier\nfiles:\n  - a.js\n' > "$GOAL_CP"
OUT=$(CLAUDE_HARNESS_HOME_OVERRIDE="$GOAL_HOME" run_hook memory-init.js "$GOAL_CWD" '{"cwd":"'"$GOAL_CWD"'","session_id":"goalS1"}')
echo "$OUT" | grep -q "checkpoint had no .goal" && fail "a checkpoint WITH a goal must not be nudged -- that turns the block into per-session noise"
echo "$OUT" | grep -q "previous session checkpoint" || fail "the checkpoint itself should still be injected: $OUT"
pass "empty/whitespace goal nudges, a real goal stays silent"

echo "=== Test 13: real ~/.claude/session gains no NEW files from this run ==="
POST_SESSION_SNAPSHOT="$(find ~/.claude/session -type f 2>/dev/null | sort)" || true
if ! NEW_PATHS="$(comm -13 <(printf '%s\n' "$PRE_SESSION_SNAPSHOT") <(printf '%s\n' "$POST_SESSION_SNAPSHOT"))"; then
  fail "could not compare real ~/.claude/session snapshots -- comm itself failed, this check did not run"
fi
if [ -n "$NEW_PATHS" ]; then
  fail "pollution regression -- this run created real files outside the sandbox: $NEW_PATHS"
fi
pass "real ~/.claude/session gained no new file paths this run (path comparison only -- does not diff pre-existing files' contents)"

echo ""
echo "ALL $PASS_COUNT CHECKS PASSED"
