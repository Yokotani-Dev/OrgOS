#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EVENTS_PATH="${EVENTS_PATH:-$REPO_ROOT/.ai/_machine/evolution/events.jsonl}"

python3 - "$EVENTS_PATH" <<'PY'
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

path = Path(sys.argv[1])
if not path.exists():
    print("events_path_missing")
    raise SystemExit(0)


def event_date(event: dict[str, Any]) -> str:
    event_id = str(event.get("event_id") or "")
    match = re.match(r"^EVO-([0-9]{4}-[0-9]{2}-[0-9]{2})-[0-9]{3}$", event_id)
    if match:
        return match.group(1)
    return str(event.get("detected_at") or "")[:10]


def fingerprint(event: dict[str, Any]) -> str:
    payload = {
        key: event.get(key)
        for key in (
            "source",
            "event_type",
            "severity",
            "target_artifacts",
            "evidence",
            "proposed_action",
            "recommended_next",
        )
    }
    return hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


rows: list[dict[str, Any]] = []
for raw in path.read_text(encoding="utf-8").splitlines():
    if not raw.strip():
        continue
    try:
        row = json.loads(raw)
    except json.JSONDecodeError:
        continue
    if isinstance(row, dict):
        rows.append(row)

seen_ids: set[tuple[str, str]] = set()
seen_fp: set[tuple[str, str]] = set()
kept: list[dict[str, Any]] = []
for row in rows:
    day = event_date(row)
    event_id = str(row.get("event_id") or "")
    id_key = (day, event_id)
    fp_key = (day, fingerprint(row))
    if event_id and id_key in seen_ids:
        continue
    if fp_key in seen_fp:
        continue
    seen_ids.add(id_key)
    seen_fp.add(fp_key)
    kept.append(row)

with path.open("w", encoding="utf-8") as fh:
    for row in kept:
        fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")

print(f"deduped: before={len(rows)} after={len(kept)} removed={len(rows) - len(kept)}")
PY
