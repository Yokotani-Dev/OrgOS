#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
DASHBOARD_PATH="${DASHBOARD_PATH:-$REPO_ROOT/.ai/DASHBOARD.md}"

log_event() {
  local level="$1"
  local event="$2"
  local message="$3"
  printf '{"level":"%s","event":"%s","message":"%s"}\n' "$level" "$event" "$message" >&2
}

log_event "info" "dashboard_render_start" "rendering result-first dashboard"

python3 - "$REPO_ROOT" "$DASHBOARD_PATH" <<'PY'
from __future__ import annotations

import json
import re
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


REPO_ROOT = Path(sys.argv[1])
DASHBOARD_PATH = Path(sys.argv[2])
OWNER_INBOX = REPO_ROOT / ".ai" / "OWNER_INBOX.md"
TASKS_PATH = REPO_ROOT / ".ai" / "TASKS.yaml"
EVENTS_PATH = REPO_ROOT / ".ai" / "EVOLUTION" / "events.jsonl"
APPLIED_DIR = REPO_ROOT / ".ai" / "EVOLUTION" / "applied"
BEGIN = "<!-- ORGOS:RESULT-FIRST-DASHBOARD:BEGIN -->"
END = "<!-- ORGOS:RESULT-FIRST-DASHBOARD:END -->"
CARD_RE = re.compile(r"```decision-card\n(?P<yaml>.*?)\n```", re.DOTALL)


def log(level: str, event: str, message: str, **fields: Any) -> None:
    row = {"level": level, "event": event, "message": message}
    row.update(fields)
    print(json.dumps(row, ensure_ascii=False, sort_keys=True), file=sys.stderr)


def read_text(path: Path) -> str:
    if not path.exists():
        log("warning", "missing_input", "input file is absent", path=str(path.relative_to(REPO_ROOT)))
        return ""
    return path.read_text(encoding="utf-8")


def parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        try:
            dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def in_window(value: Any, now: datetime, days: int) -> bool:
    dt = parse_dt(value)
    if dt is None:
        return False
    delta = now - dt
    return 0 <= delta.total_seconds() <= days * 24 * 60 * 60


def md_escape(value: Any) -> str:
    text = "" if value is None else str(value)
    return text.replace("|", "\\|").replace("\n", " ").strip()


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    if not rows:
        return "(なし)"
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(md_escape(cell) for cell in row) + " |")
    return "\n".join(lines)


def load_decision_cards() -> list[dict[str, Any]]:
    text = read_text(OWNER_INBOX)
    cards: list[dict[str, Any]] = []
    for match in CARD_RE.finditer(text):
        try:
            card = yaml.safe_load(match.group("yaml")) or {}
        except yaml.YAMLError as exc:
            log("warning", "decision_card_parse_failed", "skipping invalid decision-card", error=str(exc))
            continue
        if isinstance(card, dict):
            cards.append(card)
    log("info", "decision_cards_loaded", "loaded decision cards", count=len(cards))
    return cards


def load_application_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if not APPLIED_DIR.exists():
        log("warning", "missing_input", "applied directory is absent", path=str(APPLIED_DIR.relative_to(REPO_ROOT)))
        return records
    for path in sorted(APPLIED_DIR.glob("*.yaml")):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as exc:
            log("warning", "application_record_parse_failed", "skipping invalid application record", path=str(path.relative_to(REPO_ROOT)), error=str(exc))
            continue
        if isinstance(data, dict):
            data["_path"] = str(path.relative_to(REPO_ROOT))
            records.append(data)
    log("info", "application_records_loaded", "loaded application records", count=len(records))
    return records


def load_tasks() -> list[dict[str, Any]]:
    text = read_text(TASKS_PATH)
    if not text:
        return []
    try:
        data = yaml.safe_load(text) or {}
    except yaml.YAMLError as exc:
        log("warning", "tasks_parse_failed", "unable to parse TASKS.yaml", error=str(exc))
        return []
    tasks = data.get("tasks", []) if isinstance(data, dict) else []
    if not isinstance(tasks, list):
        return []
    return [task for task in tasks if isinstance(task, dict)]


def load_events() -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    text = read_text(EVENTS_PATH)
    for line_no, raw in enumerate(text.splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            log("warning", "event_parse_failed", "skipping invalid event row", line=line_no, error=str(exc))
            continue
        if isinstance(row, dict):
            events.append(row)
    log("info", "events_loaded", "loaded evolution events", count=len(events))
    return events


def preserved_body(existing: str) -> str:
    if BEGIN in existing and END in existing:
        body = existing.split(END, 1)[1].strip()
        return re.sub(r"^(?:---\s*)+", "", body).strip()
    match = re.search(r"(?m)^##\s+", existing)
    if match:
        return existing[match.start():].strip()
    return existing.strip()


def first_target(row: dict[str, Any]) -> str:
    artifacts = row.get("target_artifacts") or []
    if artifacts and isinstance(artifacts[0], dict):
        return str(artifacts[0].get("path") or "")
    return ""


def build_dashboard() -> str:
    now = datetime.now(timezone.utc)
    existing = read_text(DASHBOARD_PATH)
    cards = load_decision_cards()
    records = load_application_records()
    tasks = load_tasks()
    events = load_events()

    pending_cards = [card for card in cards if str(card.get("status", "pending")) == "pending"]
    weekly_decisions = [
        card
        for card in cards
        if str(card.get("status", "pending")) != "pending" and in_window(card.get("resolved_at"), now, 7)
    ]
    records_7d = [record for record in records if in_window(record.get("applied_at"), now, 7)]
    records_30d = [record for record in records if in_window(record.get("applied_at"), now, 30)]
    blocked_tasks = [task for task in tasks if str(task.get("status")) == "blocked"]
    events_30d = [row for row in events if in_window(row.get("detected_at"), now, 30)]

    question_counts = Counter(str(row.get("severity", "unknown")) for row in events_30d)
    problem_counts = Counter(str(row.get("problem_class") or row.get("severity") or "unknown") for row in events_30d)
    capability_events = [
        row for row in events_30d if str(row.get("event_type", "")).startswith("capability_")
    ]
    capability_counts = Counter(str(row.get("event_type", "unknown")) for row in capability_events)
    capability_autonomy = Counter(str(row.get("autonomy_candidate", "unknown")) for row in capability_events)

    log(
        "info",
        "dashboard_metrics",
        "computed dashboard metrics",
        pending_decisions=len(pending_cards),
        weekly_owner_decisions=len(weekly_decisions),
        applied_7d=len(records_7d),
        applied_30d=len(records_30d),
        blocked=len(blocked_tasks),
        events_30d=len(events_30d),
    )

    decision_rows = [
        [
            card.get("id", ""),
            card.get("type", ""),
            card.get("decision", ""),
            card.get("recommendation", ""),
            card.get("risk", ""),
            card.get("deadline", ""),
            card.get("default_if_no_response", ""),
        ]
        for card in pending_cards
    ]

    bandwidth_rows = [
        ["Owner decisions", "7d", len(weekly_decisions), ".ai/OWNER_INBOX.md"],
        ["Autonomous applies", "30d", len(records_30d), ".ai/EVOLUTION/applied/"],
        [
            "Questions by priority",
            "30d",
            f"P0:{question_counts.get('P0', 0)} / P1:{question_counts.get('P1', 0)} / P2:{question_counts.get('P2', 0)}",
            ".ai/EVOLUTION/events.jsonl",
        ],
    ]

    applied_rows = [
        [
            record.get("record_id", ""),
            record.get("applied_at", ""),
            record.get("rollout_stage", ""),
            record.get("autonomy_level_at_apply", ""),
            record.get("applied_by", ""),
            record.get("target_file", ""),
        ]
        for record in records_7d
    ]

    blocked_rows = [
        [
            task.get("id", ""),
            task.get("title", ""),
            task.get("owner_role", ""),
            task.get("autonomy_level", ""),
            task.get("risk_level", ""),
            task.get("default_if_no_response", ""),
        ]
        for task in blocked_tasks
    ]

    problem_order = ["P0", "P1", "P2", "P3", "unknown"]
    problem_rows = [
        [key, problem_counts[key]]
        for key in problem_order
        if problem_counts.get(key, 0)
    ]
    for key in sorted(problem_counts):
        if key not in problem_order:
            problem_rows.append([key, problem_counts[key]])

    capability_rows = [[key, capability_counts[key]] for key in sorted(capability_counts)]
    capability_auto_rows = [[key, capability_autonomy[key]] for key in sorted(capability_autonomy)]
    recent_event_rows = [
        [
            row.get("event_id", ""),
            row.get("severity", ""),
            row.get("event_type", ""),
            row.get("source", ""),
            first_target(row),
        ]
        for row in sorted(events_30d, key=lambda item: str(item.get("detected_at", "")), reverse=True)[:5]
    ]

    generated = f"""# DASHBOARD

{BEGIN}
## Decision Table

Pending Decision Cards from `.ai/OWNER_INBOX.md`.

{markdown_table(["ID", "Type", "Decision", "Recommendation", "Risk", "Deadline", "Default"], decision_rows)}

### Owner Bandwidth

{markdown_table(["Metric", "Window", "Value", "Source"], bandwidth_rows)}

## Autonomous Results

Recent application records from `.ai/EVOLUTION/applied/` within 7 days.

{markdown_table(["Record", "Applied At", "Stage", "Autonomy", "Applied By", "Target"], applied_rows)}

## Blocked

Current blocked tasks from `.ai/TASKS.yaml` after T-OS-322 autonomy backfill.

{markdown_table(["Task", "Title", "Owner Role", "Autonomy", "Risk", "Default"], blocked_rows)}

## Evolution Trace

Recent 30-day evolution signals from `.ai/EVOLUTION/events.jsonl`. When `problem_class` is not present, severity is used as the dashboard class.

### Problem Class Counts

{markdown_table(["Problem Class", "Count"], problem_rows)}

### AI Capability Evolution

{markdown_table(["Capability Signal", "Count"], capability_rows)}

{markdown_table(["Autonomy Candidate", "Capability Event Count"], capability_auto_rows)}

### Recent Signals

{markdown_table(["Event", "Priority", "Type", "Source", "Target"], recent_event_rows)}
{END}
"""

    body = preserved_body(existing)
    if body:
        return f"{generated}\n---\n\n{body.rstrip()}\n"
    return f"{generated}\n"


output = build_dashboard()
DASHBOARD_PATH.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=DASHBOARD_PATH.parent, delete=False) as handle:
    tmp_path = Path(handle.name)
    handle.write(output)
tmp_path.replace(DASHBOARD_PATH)
log("info", "dashboard_render_complete", "dashboard rendered", path=str(DASHBOARD_PATH.relative_to(REPO_ROOT)))
PY

log_event "info" "dashboard_render_end" "render complete"
