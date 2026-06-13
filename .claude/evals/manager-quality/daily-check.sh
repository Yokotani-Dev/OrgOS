#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
JSONL_DIR="${JSONL_DIR:-$REPO_ROOT/.ai/_machine/metrics/manager-quality}"
# ISS-011: judge against the committed eval fixture profile, not live memory.
PROFILE_PATH="${MQ_PROFILE_PATH:-$SCRIPT_DIR/fixtures/USER_PROFILE.yaml}"

mkdir -p "$JSONL_DIR"

set +e
eval_output="$("$PYTHON_BIN" "$SCRIPT_DIR/report.py" run --repo-root "$REPO_ROOT" --output-dir "$JSONL_DIR" --profile-path "$PROFILE_PATH" --json)"
eval_exit=$?
regression_output="$("$PYTHON_BIN" "$SCRIPT_DIR/report.py" regression --jsonl-dir "$JSONL_DIR" --json)"
regression_exit=$?
set -e

export EVAL_OUTPUT="$eval_output"
export REGRESSION_OUTPUT="$regression_output"

"$PYTHON_BIN" - <<'PY'
from __future__ import annotations

import json
import os

eval_summary = json.loads(os.environ["EVAL_OUTPUT"])
regression = json.loads(os.environ["REGRESSION_OUTPUT"])

payload = {
    "suite": "manager-quality",
    "eval": eval_summary,
    "regression": regression,
}
print(json.dumps(payload, ensure_ascii=False))
PY

if [[ $regression_exit -eq 2 ]]; then
  exit 2
fi
exit "$eval_exit"
