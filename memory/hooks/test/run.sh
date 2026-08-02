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

PASS_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

run_hook() {
  # run_hook <script> <cwd> <json>
  local script="$1" cwd="$2" json="$3"
  (cd "$cwd" && echo "$json" | node "$HOOKS/$script")
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
for script in memory-init.js memory-checkpoint.js memory-compact.js memory-flush.js; do
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
  touch -d "10 days ago" "$TRIM_ARCHIVE/2020-old-$i.md" 2>/dev/null || touch -d "@$(( $(date +%s) - 864000 ))" "$TRIM_ARCHIVE/2020-old-$i.md"
done
run_hook memory-compact.js "$TRIM_PROJECT" '{"cwd":"'"$TRIM_PROJECT"'"}' > /dev/null
REMAINING=$(find "$TRIM_ARCHIVE" -name '*.md' | wc -l)
# 3 recent + 1 newly-archived-by-this-compact-call = 4 expected; the 2 old ones must be gone.
[ "$REMAINING" -eq 4 ] || fail "expected 4 archive files after day-cutoff trim (3 recent + 1 just-archived), found $REMAINING"
find "$TRIM_ARCHIVE" -name '2020-old-*' | grep -q . && fail "day-old archive files survived trim (day-based cutoff not enforced)" || pass "day-based cutoff removed old files independent of count cap"

echo "=== Test 15: project archive trim -- count cap (16 recent files -> keep newest 10) ==="
rm -rf "$TRIM_ARCHIVE"
mkdir -p "$TRIM_ARCHIVE"
for i in $(seq 1 15); do
  echo "entry $i" > "$TRIM_ARCHIVE/2026-entry-$(printf '%02d' "$i").md"
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
touch -d "20 seconds ago" "$STALE_HOME_POSIX/.claude/session/.checkpoint.lock" 2>/dev/null || touch -d "@$(( $(date +%s) - 20 ))" "$STALE_HOME_POSIX/.claude/session/.checkpoint.lock"
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

echo ""
echo "=== Test 13: real ~/.claude/session left untouched by this entire run ==="
if [ -e ~/.claude/session ]; then
  fail "real ~/.claude/session exists after a fully-scoped test run -- pollution regression"
fi
pass "real ~/.claude untouched"

echo ""
echo "ALL $PASS_COUNT CHECKS PASSED"
