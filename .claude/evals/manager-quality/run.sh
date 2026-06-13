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

METRICS_DIR="$REPO_ROOT/.ai/_machine/metrics/manager-quality"
mkdir -p "$METRICS_DIR"

# ISS-011: judge against the committed eval fixture profile, not live memory.
# Override with MQ_PROFILE_PATH if needed.
PROFILE_PATH="${MQ_PROFILE_PATH:-$SCRIPT_DIR/fixtures/USER_PROFILE.yaml}"

ARGS=(
  "$SCRIPT_DIR/report.py"
  run
  --repo-root "$REPO_ROOT"
  --output-dir "$METRICS_DIR"
  --profile-path "$PROFILE_PATH"
)

if [[ "$JSON_OUTPUT" == "true" ]]; then
  ARGS+=(--json)
fi

"$PYTHON_BIN" "${ARGS[@]}"
