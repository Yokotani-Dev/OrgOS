#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
JSONL_DIR="$REPO_ROOT/.ai/METRICS/manager-quality"
PYTHON_BIN="${PYTHON_BIN:-python3}"

mkdir -p "$JSONL_DIR"

"$PYTHON_BIN" "$REPO_ROOT/.claude/evals/manager-quality/report.py" regression --jsonl-dir "$JSONL_DIR" "$@"
