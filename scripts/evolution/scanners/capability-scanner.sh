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
  echo "capability-scanner requires --json" >&2
  exit 1
fi

python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

repo = Path(sys.argv[1])
now = datetime.now(timezone.utc).replace(microsecond=0)
detected_at = now.isoformat().replace("+00:00", "Z")
path = repo / ".ai" / "CAPABILITIES.yaml"


def parse_dt(value: Any) -> datetime | None:
    if not value:
        return None
    text = str(value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def line_for(capability_id: str, lines: list[str]) -> int:
    needle = f"- id: {capability_id}"
    for idx, line in enumerate(lines, start=1):
        if line.strip() == needle:
            return idx
    return 1


events: list[dict[str, Any]] = []
if not path.exists():
    print("[]")
    raise SystemExit(0)

lines = path.read_text(encoding="utf-8").splitlines()
doc = yaml.safe_load("\n".join(lines)) or {}
capabilities = doc.get("capabilities") if isinstance(doc, dict) else []
if not isinstance(capabilities, list):
    capabilities = []

for cap in capabilities:
    if not isinstance(cap, dict):
        continue
    cap_id = str(cap.get("id") or cap.get("name") or "unknown")
    status = str(cap.get("status") or "unknown").lower()
    auth_status = str(cap.get("auth_status") or "unknown").lower()
    verified = parse_dt(cap.get("verified_at"))
    age_days = None if verified is None else (now - verified).days
    reason = None
    severity = "P2"
    confidence = 0.85

    if auth_status == "expired":
        reason = "auth_status=expired"
        severity = "P1"
        confidence = 0.95
    elif age_days is not None and age_days > 7:
        reason = f"verified_at age_days={age_days}"
    elif status in {"unavailable", "unknown"} and cap.get("path") is None:
        reason = f"status={status}"
        severity = "P3"
        confidence = 0.7

    if reason is None:
        continue

    events.append({
        "detected_at": detected_at,
        "source": "capability_scanner",
        "event_type": "capability_degraded",
        "severity": severity,
        "confidence": confidence,
        "novelty": "recurring",
        "target_artifacts": [{"path": ".ai/CAPABILITIES.yaml", "lines": [line_for(cap_id, lines)]}],
        "evidence": [{"kind": "capability_registry", "snippet": f"{cap_id}: {reason}, status={status}, auth_status={auth_status}"}],
        "proposed_action": "update",
        "estimated_impact": "medium",
        "estimated_risk": "low",
        "autonomy_candidate": "execute_with_report",
        "blast_radius": "single_file",
        "recommended_next": f"Refresh capability verification for {cap_id} using scripts/capabilities/scan.sh in a controlled follow-up task.",
    })

print(json.dumps(events, ensure_ascii=False, separators=(",", ":")))
PY
