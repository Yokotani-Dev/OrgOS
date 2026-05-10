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
  echo "intel-scanner requires --json" >&2
  exit 1
fi

python3 - "$REPO_ROOT" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

repo = Path(sys.argv[1])
now = datetime.now(timezone.utc).replace(microsecond=0)
detected_at = now.isoformat().replace("+00:00", "Z")
root = repo / ".ai" / "INTELLIGENCE"
config = root / "config.yaml"
raw = root / "raw"

events: list[dict] = []
watch_topics = []
if config.exists():
    doc = yaml.safe_load(config.read_text(encoding="utf-8")) or {}
    if isinstance(doc, dict) and isinstance(doc.get("watch_topics"), list):
        watch_topics = doc["watch_topics"]

raw_files = [p for p in raw.rglob("*") if p.is_file() and p.name != ".gitkeep"] if raw.exists() else []
if not raw_files:
    events.append({
        "detected_at": detected_at,
        "source": "intel_scanner",
        "event_type": "intel_stale",
        "severity": "P1",
        "confidence": 0.95,
        "novelty": "recurring",
        "target_artifacts": [{"path": ".ai/INTELLIGENCE/config.yaml", "lines": [1] if config.exists() else []}],
        "evidence": [{"kind": "empty_intelligence_raw", "snippet": f"raw has no collected files while watch_topics={len(watch_topics)}"}],
        "proposed_action": "add",
        "estimated_impact": "large",
        "estimated_risk": "low",
        "autonomy_candidate": "execute_with_report",
        "blast_radius": "multi_file",
        "recommended_next": "Run or create the Intelligence collector so watched AI evolution topics produce raw inputs.",
    })
else:
    latest = max(raw_files, key=lambda p: p.stat().st_mtime)
    age_days = int((now.timestamp() - latest.stat().st_mtime) // 86400)
    if age_days > 7:
        events.append({
            "detected_at": detected_at,
            "source": "intel_scanner",
            "event_type": "intel_stale",
            "severity": "P1",
            "confidence": 0.9,
            "novelty": "recurring",
            "target_artifacts": [{"path": str(latest.relative_to(repo)), "lines": [1]}],
            "evidence": [{"kind": "raw_age", "snippet": f"latest raw input={latest.name}, age_days={age_days}"}],
            "proposed_action": "update",
            "estimated_impact": "large",
            "estimated_risk": "low",
            "autonomy_candidate": "execute_with_report",
            "blast_radius": "multi_file",
            "recommended_next": "Refresh Intelligence raw collection and generate a weekly summary.",
        })

print(json.dumps(events, ensure_ascii=False, separators=(",", ":")))
PY
