#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EVENTS_PATH="${EVENTS_PATH:-$REPO_ROOT/.ai/EVOLUTION/events.jsonl}"
JSON_APPEND=0
STDOUT_YAML=0
SCANNER_FILTER=""

usage() {
  cat <<'EOF'
Usage: bash scripts/evolution/detect.sh [--json] [--stdout] [--scanner <name>]

Options:
  --json            Append new normalized events to .ai/EVOLUTION/events.jsonl as JSONL.
  --stdout          Print newly emitted events as YAML.
  --scanner <name>  Run only one scanner: eval, capability, oip, memory, intel.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_APPEND=1
      shift
      ;;
    --stdout)
      STDOUT_YAML=1
      shift
      ;;
    --scanner)
      SCANNER_FILTER="${2:-}"
      if [[ -z "$SCANNER_FILTER" ]]; then
        echo "--scanner requires a name" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$JSON_APPEND" -eq 0 && "$STDOUT_YAML" -eq 0 ]]; then
  STDOUT_YAML=1
fi

scanner_script() {
  case "$1" in
    eval) echo "$SCRIPT_DIR/scanners/eval-scanner.sh" ;;
    capability) echo "$SCRIPT_DIR/scanners/capability-scanner.sh" ;;
    oip) echo "$SCRIPT_DIR/scanners/oip-scanner.sh" ;;
    memory) echo "$SCRIPT_DIR/scanners/memory-scanner.sh" ;;
    intel) echo "$SCRIPT_DIR/scanners/intel-scanner.sh" ;;
    *)
      echo "Unknown scanner: $1" >&2
      exit 1
      ;;
  esac
}

if [[ -n "$SCANNER_FILTER" ]]; then
  scanners=("$SCANNER_FILTER")
else
  scanners=(eval capability oip memory intel)
fi

combined="$(
  for scanner in "${scanners[@]}"; do
    script="$(scanner_script "$scanner")"
    payload="$(bash "$script" --json)"
    printf '{"scanner":%s,"payload":' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$scanner")"
    printf '%s' "$payload"
    printf '}\n'
  done
)"

export COMBINED_SCANNER_PAYLOADS="$combined"
export EVENTS_PATH JSON_APPEND STDOUT_YAML

python3 - <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import yaml

events_path = Path(os.environ["EVENTS_PATH"])
json_append = os.environ["JSON_APPEND"] == "1"
stdout_yaml = os.environ["STDOUT_YAML"] == "1"
today = date.today().isoformat()
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

SOURCE_VALUES = {
    "internal_scanner",
    "eval_scanner",
    "capability_scanner",
    "oip_scanner",
    "memory_scanner",
    "intel_scanner",
}
EVENT_TYPE_VALUES = {
    "eval_regression",
    "ux_drift",
    "capability_new",
    "capability_degraded",
    "rule_stale",
    "iron_law_violation",
    "owner_friction",
    "oip_stale",
    "intel_stale",
    "dna_drift",
}
SEVERITY_VALUES = {"P0", "P1", "P2", "P3"}
NOVELTY_VALUES = {"first_seen", "recurring", "transient"}
ACTION_VALUES = {"deduplicate", "rename", "add", "remove", "update", "escalate"}
IMPACT_VALUES = {"small", "medium", "large"}
RISK_VALUES = {"low", "medium", "high"}
AUTONOMY_VALUES = {"silent_execute", "execute_with_report", "ask_before_execute", "owner_only"}
BLAST_VALUES = {"single_file", "multi_file", "schema_change", "iron_law"}


def clamp_confidence(value: Any) -> float:
    try:
        confidence = float(value)
    except (TypeError, ValueError):
        confidence = 0.5
    return max(0.0, min(1.0, confidence))


def enum_value(value: Any, allowed: set[str], default: str) -> str:
    text = str(value) if value is not None else default
    return text if text in allowed else default


def normalize_artifacts(items: Any) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    if not isinstance(items, list):
        return normalized
    for item in items:
        if not isinstance(item, dict):
            continue
        path = str(item.get("path") or "").strip()
        if not path:
            continue
        lines = item.get("lines") if isinstance(item.get("lines"), list) else []
        clean_lines = []
        for line in lines:
            try:
                line_int = int(line)
            except (TypeError, ValueError):
                continue
            if line_int > 0:
                clean_lines.append(line_int)
        normalized.append({"path": path, "lines": clean_lines})
    return normalized


def normalize_evidence(items: Any) -> list[dict[str, str]]:
    normalized: list[dict[str, str]] = []
    if not isinstance(items, list):
        return normalized
    for item in items:
        if not isinstance(item, dict):
            continue
        kind = str(item.get("kind") or "signal").strip()
        snippet = str(item.get("snippet") or "").strip()
        if snippet:
            normalized.append({"kind": kind, "snippet": snippet[:500]})
    return normalized


def normalize_event(raw: dict[str, Any]) -> dict[str, Any]:
    return {
        "event_id": str(raw.get("event_id") or ""),
        "detected_at": str(raw.get("detected_at") or now),
        "source": enum_value(raw.get("source"), SOURCE_VALUES, "internal_scanner"),
        "event_type": enum_value(raw.get("event_type"), EVENT_TYPE_VALUES, "ux_drift"),
        "severity": enum_value(raw.get("severity"), SEVERITY_VALUES, "P2"),
        "confidence": clamp_confidence(raw.get("confidence")),
        "novelty": enum_value(raw.get("novelty"), NOVELTY_VALUES, "first_seen"),
        "target_artifacts": normalize_artifacts(raw.get("target_artifacts")),
        "evidence": normalize_evidence(raw.get("evidence")),
        "proposed_action": enum_value(raw.get("proposed_action"), ACTION_VALUES, "update"),
        "estimated_impact": enum_value(raw.get("estimated_impact"), IMPACT_VALUES, "medium"),
        "estimated_risk": enum_value(raw.get("estimated_risk"), RISK_VALUES, "medium"),
        "autonomy_candidate": enum_value(raw.get("autonomy_candidate"), AUTONOMY_VALUES, "ask_before_execute"),
        "blast_radius": enum_value(raw.get("blast_radius"), BLAST_VALUES, "single_file"),
        "recommended_next": str(raw.get("recommended_next") or "Inspect this event and decide the next evolution action.").strip(),
    }


def fingerprint(event: dict[str, Any]) -> str:
    payload = {
        key: event[key]
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
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def event_date(event: dict[str, Any]) -> str:
    event_id = str(event.get("event_id") or "")
    match = re.match(r"^EVO-([0-9]{4}-[0-9]{2}-[0-9]{2})-[0-9]{3}$", event_id)
    if match:
        return match.group(1)
    detected = str(event.get("detected_at") or "")
    return detected[:10]


raw_candidates: list[dict[str, Any]] = []
for line in os.environ.get("COMBINED_SCANNER_PAYLOADS", "").splitlines():
    if not line.strip():
        continue
    try:
        wrapper = json.loads(line)
    except json.JSONDecodeError as exc:
        print(f"Failed to parse scanner wrapper: {exc}", file=sys.stderr)
        continue
    payload = wrapper.get("payload")
    if not isinstance(payload, list):
        print(f"Scanner {wrapper.get('scanner')} did not return a JSON array", file=sys.stderr)
        continue
    for item in payload:
        if isinstance(item, dict):
            raw_candidates.append(item)

existing: list[dict[str, Any]] = []
if events_path.exists():
    for raw in events_path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict):
            existing.append(row)

today_fp_to_event_id = {
    fingerprint(normalize_event(row)): str(row.get("event_id") or "")
    for row in existing
    if event_date(row) == today
}
today_fingerprints = set(today_fp_to_event_id)
today_ids = []
for row in existing:
    event_id = str(row.get("event_id") or "")
    match = re.match(rf"^EVO-{re.escape(today)}-([0-9]{{3}})$", event_id)
    if match:
        today_ids.append(int(match.group(1)))
next_num = max(today_ids, default=0) + 1

emitted: list[dict[str, Any]] = []
stdout_events: list[dict[str, Any]] = []
seen_this_run: set[str] = set()
for candidate in raw_candidates:
    event = normalize_event(candidate)
    fp = fingerprint(event)
    if fp in seen_this_run:
        continue
    if fp in today_fingerprints:
        event["event_id"] = today_fp_to_event_id.get(fp, "")
        stdout_events.append(event)
        seen_this_run.add(fp)
        continue
    event["event_id"] = f"EVO-{today}-{next_num:03d}"
    next_num += 1
    emitted.append(event)
    stdout_events.append(event)
    seen_this_run.add(fp)

if json_append and emitted:
    events_path.parent.mkdir(parents=True, exist_ok=True)
    with events_path.open("a", encoding="utf-8") as fh:
        for event in emitted:
            fh.write(json.dumps(event, ensure_ascii=False, sort_keys=False, separators=(",", ":")) + "\n")

if stdout_yaml:
    print(yaml.safe_dump({"events": stdout_events}, allow_unicode=True, sort_keys=False, width=1000))
PY
