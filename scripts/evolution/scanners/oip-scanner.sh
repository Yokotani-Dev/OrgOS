#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$JSON_OUTPUT" -ne 1 ]]; then
  echo "oip-scanner requires --json" >&2
  exit 1
fi

python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import json
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

repo = Path(sys.argv[1])
now = datetime.now(timezone.utc).replace(microsecond=0)
detected_at = now.isoformat().replace("+00:00", "Z")
oip_dir = repo / ".ai" / "OIP"


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


status_patterns = [
    re.compile(r"^\s*>?\s*Status:\s*(.+?)\s*$", re.IGNORECASE),
    re.compile(r"^\s*[-*]?\s*\*\*ステータス\*\*\s*:\s*(.+?)\s*$"),
    re.compile(r"^\s*[-*]?\s*ステータス\s*:\s*(.+?)\s*$"),
]
date_patterns = [
    re.compile(r"^\s*>?\s*Created:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$", re.IGNORECASE),
    re.compile(r"^\s*>?\s*Date:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$", re.IGNORECASE),
    re.compile(r"^\s*[-*]?\s*\*\*提案日\*\*\s*:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$"),
    re.compile(r"^\s*[-*]?\s*提案日\s*:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$"),
]
open_status = {"draft", "提案中", "proposed"}

events: list[dict[str, Any]] = []
for path in sorted(oip_dir.glob("*.md")) if oip_dir.exists() else []:
    lines = path.read_text(encoding="utf-8").splitlines()
    status = ""
    status_line = 1
    created = None
    for idx, line in enumerate(lines, start=1):
        if not status:
            for pattern in status_patterns:
                match = pattern.match(line)
                if match:
                    status = match.group(1).strip().strip("*")
                    status_line = idx
                    break
        if created is None:
            for pattern in date_patterns:
                match = pattern.match(line)
                if match:
                    try:
                        created = date.fromisoformat(match.group(1))
                    except ValueError:
                        created = None
                    break
    normalized = status.strip().lower()
    if created is None or normalized not in open_status:
        continue
    age_days = (date.today() - created).days
    if age_days <= 14:
        continue
    events.append({
        "detected_at": detected_at,
        "source": "oip_scanner",
        "event_type": "oip_stale",
        "severity": "P1" if age_days > 30 else "P2",
        "confidence": 0.95,
        "novelty": "recurring",
        "target_artifacts": [{"path": rel(path), "lines": [status_line]}],
        "evidence": [{"kind": "oip_age", "snippet": f"status={status}, created={created.isoformat()}, age_days={age_days}"}],
        "proposed_action": "escalate",
        "estimated_impact": "medium",
        "estimated_risk": "low",
        "autonomy_candidate": "ask_before_execute",
        "blast_radius": "single_file",
        "recommended_next": f"Escalate {path.name} to the next Decision Table pass or auto-generate a close/update proposal.",
    })

print(json.dumps(events, ensure_ascii=False, separators=(",", ":")))
PY
