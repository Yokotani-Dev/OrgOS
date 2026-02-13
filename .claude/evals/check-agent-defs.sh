#!/usr/bin/env bash
# Eval: Agent Definition Check
# Validates that all agent .md files in .claude/agents/ have required
# YAML frontmatter fields: name, description, tools.
#
# Exit codes: 0=pass, 1=fail, 2=warn

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
AGENTS_DIR="$REPO_ROOT/.claude/agents"

ERRORS=()
WARNINGS=()

# Skip non-agent files
SKIP_FILES=("CODEX_WORKER_GUIDE.md")

should_skip() {
  local filename="$1"
  for skip in "${SKIP_FILES[@]}"; do
    [[ "$filename" == "$skip" ]] && return 0
  done
  return 1
}

if [[ ! -d "$AGENTS_DIR" ]]; then
  echo "Agents directory not found: $AGENTS_DIR"
  exit 1
fi

AGENT_COUNT=0
for agent_file in "$AGENTS_DIR"/*.md; do
  [[ ! -f "$agent_file" ]] && continue
  filename=$(basename "$agent_file")

  if should_skip "$filename"; then
    continue
  fi

  ((AGENT_COUNT++))

  # Check for YAML frontmatter (starts with ---)
  FIRST_LINE=$(head -1 "$agent_file")
  if [[ "$FIRST_LINE" != "---" ]]; then
    ERRORS+=("$filename: missing YAML frontmatter (no opening ---)")
    continue
  fi

  # Extract frontmatter (between first and second ---)
  # Use awk for macOS/BSD compatibility (head -n -1 is GNU-only)
  FRONTMATTER=$(awk 'NR==1{next} /^---$/{exit} {print}' "$agent_file")

  # Required fields
  for field in "name:" "description:" "tools:"; do
    if ! echo "$FRONTMATTER" | grep -q "$field"; then
      ERRORS+=("$filename: missing required frontmatter field '$field'")
    fi
  done

  # Check name field has a value and matches filename
  EXPECTED_NAME="${filename%.md}"
  ACTUAL_NAME=$(echo "$FRONTMATTER" | grep "^name:" | head -1 | sed 's/^name:[[:space:]]*//')
  if [[ -z "$ACTUAL_NAME" ]]; then
    ERRORS+=("$filename: name field is empty")
  elif [[ "$ACTUAL_NAME" != "$EXPECTED_NAME" ]]; then
    WARNINGS+=("$filename: name '$ACTUAL_NAME' doesn't match filename '$EXPECTED_NAME'")
  fi
done

if [[ $AGENT_COUNT -eq 0 ]]; then
  ERRORS+=("No agent definition files found in $AGENTS_DIR")
fi

# --- Output ---
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Agent definition check failed:"
  for e in "${ERRORS[@]}"; do
    echo "  ❌ $e"
  done
  exit 1
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "Agent definitions valid with warnings ($AGENT_COUNT agents):"
  for w in "${WARNINGS[@]}"; do
    echo "  ⚠️ $w"
  done
  exit 2
fi

echo "All $AGENT_COUNT agent definitions valid."
exit 0
