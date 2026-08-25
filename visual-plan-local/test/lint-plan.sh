#!/usr/bin/env bash
# Cheap structural lint for a visual-plan-local plan file. NOT a substitute
# for actually reading the plan -- catches the mechanical failure modes
# document-quality.md/plan-discipline.md call out: missing required
# sections, a duplicated Open Questions section, revision language that
# breaks the "every plan stands alone" rule, and a missing artifact link.
#
# Usage:
#   bash lint-plan.sh <plan.md>              # lint one real plan file
#   bash lint-plan.sh --self-test            # verify the linter itself
#     against fixtures/good-plan.md (must pass) and fixtures/bad-plan.md
#     (must fail on every check it's designed to catch)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUIRED_HEADERS=("## Scope" "## Decisions" "## Steps" "## Verification")
BANNED_PHRASES=(
  "as discussed above"
  "unlike the previous version"
  "unlike the prior version"
  "this revision"
  "preserve the previous plan"
  "preserve the prior plan"
  "do not drop the old idea"
  "correction from the earlier plan"
)

# lint_plan <file> -- prints one "FAIL: <reason>" line per violation found,
# returns 0 if clean, 1 if any violation was printed.
lint_plan() {
  local file="$1" clean=1

  for header in "${REQUIRED_HEADERS[@]}"; do
    grep -qi "^${header}" "$file" || { echo "FAIL: missing required section '$header'"; clean=0; }
  done

  local oq_count
  oq_count=$(grep -ci "^## open questions" "$file" || true)
  if [ "$oq_count" -gt 1 ]; then
    echo "FAIL: 'Open Questions' section appears $oq_count times, must be at most 1"
    clean=0
  fi

  for phrase in "${BANNED_PHRASES[@]}"; do
    if grep -qi "$phrase" "$file"; then
      echo "FAIL: banned revision-language phrase found: \"$phrase\""
      clean=0
    fi
  done

  if ! head -n 15 "$file" | grep -qE 'https?://'; then
    echo "FAIL: no artifact URL found in the first 15 lines"
    clean=0
  fi

  [ "$clean" -eq 1 ]
}

if [ "${1:-}" = "--self-test" ]; then
  GOOD="$HERE/fixtures/good-plan.md"
  BAD="$HERE/fixtures/bad-plan.md"

  echo "=== self-test: good-plan.md must pass clean ==="
  OUT=$(lint_plan "$GOOD") && echo "PASS: good-plan.md has no violations" \
    || { echo "$OUT"; echo "FAIL: good-plan.md should have passed clean"; exit 1; }

  echo "=== self-test: bad-plan.md must fail, and catch every seeded violation ==="
  set +e
  OUT=$(lint_plan "$BAD")
  CODE=$?
  set -e
  [ "$CODE" -ne 0 ] || { echo "FAIL: bad-plan.md should have failed the lint"; exit 1; }
  for expect in \
    "missing required section '## Verification'" \
    "'Open Questions' section appears 2 times" \
    "as discussed above" \
    "unlike the previous version" \
    "this revision" \
    "no artifact URL found"; do
    echo "$OUT" | grep -qF "$expect" || { echo "FAIL: expected violation not caught: $expect"; echo "$OUT"; exit 1; }
  done
  echo "PASS: bad-plan.md failed on every seeded violation"
  echo ""
  echo "ALL SELF-TESTS PASSED"
  exit 0
fi

if [ $# -ne 1 ]; then
  echo "Usage: bash lint-plan.sh <plan.md>  |  bash lint-plan.sh --self-test" >&2
  exit 2
fi

if lint_plan "$1"; then
  echo "clean: $1"
  exit 0
else
  exit 1
fi
