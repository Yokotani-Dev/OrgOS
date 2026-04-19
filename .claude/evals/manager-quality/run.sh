#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

METRICS_DIR="$REPO_ROOT/.ai/METRICS/manager-quality"
mkdir -p "$METRICS_DIR"

ARGS=(
  "$SCRIPT_DIR/report.py"
  run
  --repo-root "$REPO_ROOT"
  --output-dir "$METRICS_DIR"
)

if [[ "$JSON_OUTPUT" == "true" ]]; then
  ARGS+=(--json)
fi

"$PYTHON_BIN" "${ARGS[@]}"
