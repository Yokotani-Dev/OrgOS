#!/usr/bin/env bash
# Eval: Consistency Check
# Validates that numeric standards (coverage %, function line limits, etc.)
# are consistent across .claude/ files.
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

INCONSISTENCIES=()

# --- Check 1: Coverage percentage ---
# The canonical value is defined in testing.md
COVERAGE_FILES=()
while IFS= read -r file; do
  rel="${file#$REPO_ROOT/}"
  # Extract lines mentioning coverage with a percentage
  matches=$(grep -inE 'カバレッジ.*[0-9]+%|coverage.*[0-9]+%|[0-9]+%.*カバレッジ|[0-9]+%.*coverage' "$file" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    # Extract all percentages
    pcts=$(echo "$matches" | grep -oE '[0-9]+%' | sort -u)
    COVERAGE_FILES+=("$rel: $pcts")
  fi
done < <(find "$REPO_ROOT/.claude" -name "*.md" -type f 2>/dev/null)

# Check if there are conflicting minimum coverage values
# We expect 80% as the minimum everywhere
MIN_COVERAGES=$(printf '%s\n' "${COVERAGE_FILES[@]}" | grep -oE '[0-9]+%' | sort -u | tr '\n' ' ')
# Count distinct values that look like minimums (typically 80%)
UNIQUE_MINS=$(printf '%s\n' "${COVERAGE_FILES[@]}" | grep -iE '最低|minimum|下回|未満|以上' | grep -oE '[0-9]+%' | sort -u || true)
if [[ -n "$UNIQUE_MINS" ]]; then
  MIN_COUNT=$(echo "$UNIQUE_MINS" | wc -l | tr -d ' ')
  if [[ "$MIN_COUNT" -gt 1 ]]; then
    INCONSISTENCIES+=("Coverage minimum: multiple values found: $UNIQUE_MINS")
  fi
fi

# --- Check 2: Function line limits ---
FUNC_LIMITS=()
while IFS= read -r file; do
  rel="${file#$REPO_ROOT/}"
  # Use grep without -n to avoid line numbers polluting number extraction
  matches=$(grep -iE '[0-9]+行.*関数|関数.*[0-9]+行|[0-9]+行.*超える|[0-9]+ ?lines?.*function' "$file" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    # Extract only numbers followed by 行 or preceding "lines"
    nums=$(echo "$matches" | grep -oE '[0-9]+行' | grep -oE '[0-9]+' | sort -un || true)
    [[ -z "$nums" ]] && nums=$(echo "$matches" | grep -oE '[0-9]+ ?lines' | grep -oE '[0-9]+' | sort -un || true)
    [[ -n "$nums" ]] && FUNC_LIMITS+=("$rel: $nums")
  fi
done < <(find "$REPO_ROOT/.claude" -name "*.md" -type f 2>/dev/null)

# We expect 20 lines recommended, 50 lines upper limit — two values are OK
# But 4+ distinct values suggest inconsistency
ALL_FUNC_NUMS=$(printf '%s\n' "${FUNC_LIMITS[@]}" | grep -oE '[0-9]+' | sort -un | tr '\n' ' ' || true)
FUNC_UNIQUE=$(echo "$ALL_FUNC_NUMS" | wc -w | tr -d ' ')
if [[ "$FUNC_UNIQUE" -gt 4 ]]; then
  INCONSISTENCIES+=("Function line limits: too many distinct values: $ALL_FUNC_NUMS")
fi

# --- Check 3: Eval check names match between run-all.sh and actual scripts ---
RUN_ALL="$REPO_ROOT/.claude/evals/run-all.sh"
if [[ -f "$RUN_ALL" ]]; then
  REFERENCED_SCRIPTS=$(grep -oE 'check-[a-z-]+\.sh' "$RUN_ALL" | sort -u)
  for script_name in $REFERENCED_SCRIPTS; do
    if [[ ! -f "$REPO_ROOT/.claude/evals/$script_name" ]]; then
      INCONSISTENCIES+=("run-all.sh references $script_name but file not found")
    fi
  done
fi

# --- Output ---
if [[ ${#INCONSISTENCIES[@]} -gt 0 ]]; then
  echo "Consistency issues found (${#INCONSISTENCIES[@]}):"
  for inc in "${INCONSISTENCIES[@]}"; do
    echo "  ⚠️ $inc"
  done
  exit 2  # warn
fi

echo "Consistency checks passed."
exit 0
