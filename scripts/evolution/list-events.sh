#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EVENTS_PATH="${EVENTS_PATH:-$REPO_ROOT/.ai/_machine/evolution/events.jsonl}"
LIMIT="${1:-20}"

python3 - "$EVENTS_PATH" "$LIMIT" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    limit = int(sys.argv[2])
except ValueError:
    limit = 20

rows = []
if path.exists():
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        rows.append(row)

selected = rows[-limit:]
print(f"{'event_id':<18} {'sev':<3} {'type':<22} {'source':<20} target")
print("-" * 96)
for row in selected:
    artifacts = row.get("target_artifacts") or []
    target = ""
    if artifacts and isinstance(artifacts[0], dict):
        target = str(artifacts[0].get("path") or "")
    print(f"{str(row.get('event_id','')):<18} {str(row.get('severity','')):<3} {str(row.get('event_type','')):<22} {str(row.get('source','')):<20} {target}")
PY
