#!/usr/bin/env bash
# Regression test for the TASKS.yaml legacy edit sentinel.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TASKS_YAML="$REPO_ROOT/.ai/TASKS.yaml"
SENTINEL="# ORGOS-LEGACY: use scripts/org/update-task.py"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

[ -f "$TASKS_YAML" ] || fail "missing .ai/TASKS.yaml"

first_line=$(head -n 1 "$TASKS_YAML")
[ "$first_line" = "$SENTINEL" ] || fail ".ai/TASKS.yaml must start with '$SENTINEL'"

printf 'ok - TASKS.yaml legacy sentinel present\n'
