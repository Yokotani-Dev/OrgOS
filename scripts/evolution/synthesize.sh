#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
EVENTS_PATH="${EVENTS_PATH:-$REPO_ROOT/.ai/EVOLUTION/events.jsonl}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.ai/EVOLUTION/proposals}"
SCHEMA_PATH="${SCHEMA_PATH:-$REPO_ROOT/.claude/schemas/evolution-proposal.yaml}"

usage() {
  cat <<'EOF'
Usage: bash scripts/evolution/synthesize.sh [filters]

Filters:
  --last <duration>          Include events detected within duration, e.g. 7d, 12h.
  --problem-class <P0|P1|P2> Include only events with matching proposal problem class.
  --event-id <id>            Include one event by event_id.
  --event-type <type>        Include only one evolution event_type.
  --target-file <path>       Force the target file for fixture/smoke tests.

Options:
  --events-path <path>       Read events from a custom JSONL path.
  --output-dir <path>        Write proposal YAMLs to a custom directory.
  --stdout                  Print the generated proposal YAML to stdout.
  -h, --help                 Show this help.

This task intentionally uses a fixture synthesizer. It does not call an LLM API.
EOF
}

STDOUT=0
LAST=""
PROBLEM_CLASS=""
EVENT_ID=""
EVENT_TYPE=""
TARGET_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      LAST="${2:-}"
      if [[ -z "$LAST" ]]; then
        echo "--last requires a duration" >&2
        exit 2
      fi
      shift 2
      ;;
    --problem-class)
      PROBLEM_CLASS="${2:-}"
      if [[ -z "$PROBLEM_CLASS" ]]; then
        echo "--problem-class requires P0, P1, or P2" >&2
        exit 2
      fi
      shift 2
      ;;
    --event-id)
      EVENT_ID="${2:-}"
      if [[ -z "$EVENT_ID" ]]; then
        echo "--event-id requires an event id" >&2
        exit 2
      fi
      shift 2
      ;;
    --event-type)
      EVENT_TYPE="${2:-}"
      if [[ -z "$EVENT_TYPE" ]]; then
        echo "--event-type requires an event type" >&2
        exit 2
      fi
      shift 2
      ;;
    --target-file)
      TARGET_FILE="${2:-}"
      if [[ -z "$TARGET_FILE" ]]; then
        echo "--target-file requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --events-path)
      EVENTS_PATH="${2:-}"
      if [[ -z "$EVENTS_PATH" ]]; then
        echo "--events-path requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      if [[ -z "$OUTPUT_DIR" ]]; then
        echo "--output-dir requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    --stdout)
      STDOUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

export REPO_ROOT EVENTS_PATH OUTPUT_DIR SCHEMA_PATH STDOUT LAST PROBLEM_CLASS EVENT_ID EVENT_TYPE TARGET_FILE

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
events_path = Path(os.environ["EVENTS_PATH"])
if not events_path.is_absolute():
    events_path = repo_root / events_path
output_dir = Path(os.environ["OUTPUT_DIR"])
if not output_dir.is_absolute():
    output_dir = repo_root / output_dir
schema_path = Path(os.environ["SCHEMA_PATH"])
if not schema_path.is_absolute():
    schema_path = repo_root / schema_path

stdout_enabled = os.environ["STDOUT"] == "1"
last_filter = os.environ.get("LAST", "")
problem_filter = os.environ.get("PROBLEM_CLASS", "")
event_id_filter = os.environ.get("EVENT_ID", "")
event_type_filter = os.environ.get("EVENT_TYPE", "")
forced_target = os.environ.get("TARGET_FILE", "")

PROBLEM_VALUES = {"P0", "P1", "P2"}
RISK_VALUES = {"low", "medium", "high", "critical"}
AUTONOMY_VALUES = {
    "silent_execute",
    "execute_with_report",
    "ask_before_execute",
    "owner_only",
}
BLAST_MAP = {
    "single_file": "local",
    "multi_file": "shared",
    "schema_change": "shared",
    "iron_law": "external",
}
RISK_MAP = {
    "low": "low",
    "medium": "medium",
    "high": "high",
}
FORBIDDEN_TARGETS = {
    "AGENTS.md",
    "CLAUDE.md",
    ".claude/rules/rationalization-prevention.md",
    ".claude/rules/request-intake-loop.md",
}
FORBIDDEN_TEXT_RE = re.compile(
    r"\b(disable|bypass|ignore|weaken|remove)\b.*\b(iron law|rationalization|owner approval|protected file)\b",
    re.IGNORECASE,
)


def fail(kind: str, message: str, recovery: str) -> None:
    print(
        json.dumps(
            {
                "level": "error",
                "trace": "proposal",
                "error_class": kind,
                "message": message,
                "recovery": recovery,
            },
            ensure_ascii=False,
        ),
        file=sys.stderr,
    )
    raise SystemExit(1)


def utc_now() -> datetime:
    override = os.environ.get("ORGOS_SYNTHESIS_NOW")
    if override:
        try:
            return datetime.fromisoformat(override.replace("Z", "+00:00")).astimezone(timezone.utc)
        except ValueError:
            fail("invalid_argument", "ORGOS_SYNTHESIS_NOW is not ISO8601", "Unset it or pass an ISO8601 timestamp.")
    return datetime.now(timezone.utc).replace(microsecond=0)


def parse_duration(value: str) -> timedelta | None:
    if not value:
        return None
    match = re.fullmatch(r"([1-9][0-9]*)([dhm])", value)
    if not match:
        fail("invalid_argument", f"--last must look like 7d, 12h, or 30m: {value}", "Use a positive integer plus d/h/m.")
    amount = int(match.group(1))
    unit = match.group(2)
    if unit == "d":
        return timedelta(days=amount)
    if unit == "h":
        return timedelta(hours=amount)
    return timedelta(minutes=amount)


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def load_events() -> list[dict[str, Any]]:
    if not events_path.exists():
        fail("missing_input", f"events file not found: {events_path}", "Run scripts/evolution/detect.sh --json first.")
    rows: list[dict[str, Any]] = []
    for line_no, raw in enumerate(events_path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail("invalid_input", f"{events_path}:{line_no} is not valid JSON: {exc}", "Repair or dedupe events.jsonl before synthesis.")
        if isinstance(row, dict):
            rows.append(row)
    if not rows:
        fail("empty_input", f"no events in {events_path}", "Run detection or loosen filters.")
    return rows


def problem_class(event: dict[str, Any]) -> str:
    severity = str(event.get("severity") or "P2")
    return severity if severity in PROBLEM_VALUES else "P2"


def target_from_event(event: dict[str, Any]) -> str:
    artifacts = event.get("target_artifacts")
    if isinstance(artifacts, list):
        for artifact in artifacts:
            if isinstance(artifact, dict) and str(artifact.get("path") or "").strip():
                return str(artifact["path"]).strip()
    return "UNKNOWN"


def normalize_target(path: str) -> str:
    text = path.strip()
    if not text:
        return "UNKNOWN"
    try:
        candidate = Path(text)
        if candidate.is_absolute():
            text = str(candidate.relative_to(repo_root))
    except ValueError:
        pass
    return text.replace("\\", "/")


def iron_law_check(target_file: str, description: str) -> dict[str, Any]:
    target = normalize_target(target_file)
    reasons: list[str] = []
    if target in FORBIDDEN_TARGETS:
        reasons.append(f"target_file is protected by Iron Law: {target}")
    if FORBIDDEN_TEXT_RE.search(description):
        reasons.append("proposed_change text appears to weaken a protected rule")
    return {
        "status": "rejected" if reasons else "passed",
        "checked_at": now.isoformat().replace("+00:00", "Z"),
        "forbidden_patterns": sorted(FORBIDDEN_TARGETS),
        "violations": reasons,
        "self_check": "No protected rule weakening detected." if not reasons else "Rejected before peer review.",
    }


def proposal_id_for_today() -> str:
    output_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"P-{now.date().isoformat()}-"
    max_n = 0
    for path in output_dir.glob(f"{prefix}*.yaml"):
        match = re.fullmatch(rf"{re.escape(prefix)}([0-9]{{3}})\.yaml", path.name)
        if match:
            max_n = max(max_n, int(match.group(1)))
    return f"{prefix}{max_n + 1:03d}"


def filter_events(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    selected = events
    duration = parse_duration(last_filter)
    if duration is not None:
        cutoff = now - duration
        selected = [event for event in selected if (parse_time(event.get("detected_at")) or now) >= cutoff]
    if problem_filter:
        if problem_filter not in PROBLEM_VALUES:
            fail("invalid_argument", f"--problem-class is outside P0/P1/P2: {problem_filter}", "Choose P0, P1, or P2.")
        selected = [event for event in selected if problem_class(event) == problem_filter]
    if event_id_filter:
        selected = [event for event in selected if str(event.get("event_id") or "") == event_id_filter]
    if event_type_filter:
        selected = [event for event in selected if str(event.get("event_type") or "") == event_type_filter]
    if not selected:
        fail("no_match", "no events matched the requested filters", "Loosen filters or run detection.")
    return selected


def sort_key(event: dict[str, Any]) -> tuple[int, datetime, str]:
    severity_rank = {"P0": 0, "P1": 1, "P2": 2}.get(problem_class(event), 3)
    detected = parse_time(event.get("detected_at")) or datetime.fromtimestamp(0, timezone.utc)
    return (severity_rank, -detected.timestamp(), str(event.get("event_id") or ""))


def compact_evidence(events: list[dict[str, Any]]) -> list[str]:
    snippets: list[str] = []
    for event in events[:5]:
        evidence = event.get("evidence")
        if not isinstance(evidence, list):
            continue
        for item in evidence[:2]:
            if isinstance(item, dict) and str(item.get("snippet") or "").strip():
                snippets.append(str(item["snippet"]).strip()[:240])
    return snippets[:5]


def validate_minimum_shape(proposal: dict[str, Any]) -> None:
    required = {
        "proposal_id",
        "source_events",
        "problem_class",
        "proposed_change",
        "rationale",
        "estimated_blast_radius",
        "estimated_risk_level",
        "autonomy_recommendation",
        "iron_law_check",
        "reviewer_a",
        "reviewer_b",
        "agreement",
        "escalation_target",
    }
    missing = sorted(required - set(proposal))
    if missing:
        fail("schema_validation", f"proposal is missing required fields: {', '.join(missing)}", "Fix synthesizer output.")
    if not re.fullmatch(r"P-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}", str(proposal["proposal_id"])):
        fail("schema_validation", "proposal_id does not match P-YYYY-MM-DD-NNN", "Fix ID generation.")
    if proposal["problem_class"] not in PROBLEM_VALUES:
        fail("schema_validation", "problem_class is outside P0/P1/P2", "Normalize event severity.")
    if proposal["estimated_risk_level"] not in RISK_VALUES:
        fail("schema_validation", "estimated_risk_level is invalid", "Normalize risk.")
    if proposal["autonomy_recommendation"] not in AUTONOMY_VALUES:
        fail("schema_validation", "autonomy_recommendation is invalid", "Normalize autonomy.")


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(repo_root))
    except ValueError:
        return str(path)


now = utc_now()
if not schema_path.exists():
    fail("missing_schema", f"proposal schema not found: {schema_path}", "Create .claude/schemas/evolution-proposal.yaml.")

events = filter_events(load_events())
events = sorted(events, key=sort_key)
primary = events[0]
source_events = [str(event.get("event_id") or "") for event in events[:5] if str(event.get("event_id") or "")]
target_file = normalize_target(forced_target or target_from_event(primary))
event_type = str(primary.get("event_type") or "ux_drift")
action = str(primary.get("proposed_action") or "update")
description = (
    f"Fixture synthesis: {action} {target_file} based on {len(events)} matched {event_type} event(s). "
    f"No automatic application is requested by this proposal."
)
check = iron_law_check(target_file, description)
status = "rejected" if check["status"] == "rejected" else "proposed"
risk = RISK_MAP.get(str(primary.get("estimated_risk") or "medium"), "medium")
if status == "rejected":
    risk = "critical"

proposal = {
    "proposal_id": proposal_id_for_today(),
    "schema": "orgos/evolution-proposal/v1",
    "status": status,
    "source_events": source_events,
    "problem_class": problem_class(primary),
    "proposed_change": {
        "target_file": target_file,
        "change_type": action if action in {"add", "remove", "update", "rename", "deduplicate", "escalate"} else "update",
        "description": description,
        "diff": None,
    },
    "rationale": {
        "summary": str(primary.get("recommended_next") or "Convert detected evolution signal into an owner-visible proposal."),
        "evidence": compact_evidence(events),
    },
    "estimated_blast_radius": BLAST_MAP.get(str(primary.get("blast_radius") or "single_file"), "local"),
    "estimated_risk_level": risk,
    "autonomy_recommendation": "owner_only" if status == "rejected" else str(primary.get("autonomy_candidate") or "ask_before_execute"),
    "iron_law_check": check,
    "reviewer_a": {
        "name": "fixture-synthesizer-a",
        "kind": "stub",
        "reviewed_at": now.isoformat().replace("+00:00", "Z"),
        "verdict": "reject" if status == "rejected" else "propose",
        "confidence": min(1.0, max(0.0, float(primary.get("confidence") or 0.5))),
        "notes": "LLM API intentionally not called for T-OS-324.",
    },
    "reviewer_b": None,
    "agreement": None,
    "escalation_target": None,
    "proposal_trace": [
        {
            "at": now.isoformat().replace("+00:00", "Z"),
            "stage": "synthesize",
            "event_count": len(events),
            "filters": {
                "last": last_filter or None,
                "problem_class": problem_filter or None,
                "event_id": event_id_filter or None,
                "event_type": event_type_filter or None,
                "target_file": forced_target or None,
            },
            "outcome": status,
        }
    ],
    "review_trace": [],
}
validate_minimum_shape(proposal)

output_path = output_dir / f"{proposal['proposal_id']}.yaml"
payload = yaml.safe_dump(proposal, allow_unicode=True, sort_keys=False, width=1000)
output_path.write_text(payload, encoding="utf-8")
print(
    json.dumps(
        {
            "level": "info",
            "trace": "proposal",
            "proposal_id": proposal["proposal_id"],
            "status": status,
            "path": display_path(output_path),
            "source_event_count": len(source_events),
        },
        ensure_ascii=False,
    ),
    file=sys.stderr,
)
if stdout_enabled:
    print(payload, end="")
else:
    print(display_path(output_path))

if status == "rejected":
    raise SystemExit(3)
PY
