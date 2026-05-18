#!/usr/bin/env python3
"""Generate .ai/DASHBOARD.generated.md from the OrgOS SQLite shadow store."""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


DEFAULT_DB = Path(".ai/orgos.sqlite")
DEFAULT_OUTPUT = Path(".ai/DASHBOARD.generated.md")
TASK_STATUSES = {"queued", "running", "in_progress"}
PRIORITY_RANK = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
JSON_COLUMNS = ("payload", "data", "metadata", "json", "body_json", "content_json")


class DashboardError(Exception):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def quote_ident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def parse_json_value(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    if isinstance(value, bytes):
        try:
            value = value.decode("utf-8")
        except UnicodeDecodeError:
            return {}
    if isinstance(value, str):
        value = value.strip()
        if not value or not value.startswith(("{", "[")):
            return {}
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError:
            return {}
    else:
        parsed = value
    return parsed if isinstance(parsed, dict) else {}


def merge_payload(target: dict[str, Any], payload: dict[str, Any]) -> None:
    for key, value in payload.items():
        target.setdefault(key, value)
        target.setdefault(str(key).lower(), value)


def normalize_row(row: sqlite3.Row) -> dict[str, Any]:
    data: dict[str, Any] = {}
    for key in row.keys():
        if key.lower() in JSON_COLUMNS:
            merge_payload(data, parse_json_value(row[key]))
    for key in row.keys():
        value = row[key]
        if value is not None:
            data[key] = value
            data[key.lower()] = value
    return data


def value_of(row: dict[str, Any], *names: str, default: Any = "") -> Any:
    for name in names:
        if name in row and row[name] not in (None, ""):
            return row[name]
        lowered = name.lower()
        if lowered in row and row[lowered] not in (None, ""):
            return row[lowered]
    return default


def as_text(value: Any, default: str = "") -> str:
    if value is None:
        return default
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    text = str(value).strip()
    return text if text else default


def md_escape(value: Any) -> str:
    return as_text(value, "-").replace("|", "\\|").replace("\n", " ")


def markdown_table(headers: list[str], rows: list[list[Any]]) -> str:
    if not rows:
        return "_None._"
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(md_escape(cell) for cell in row) + " |" for row in rows)
    return "\n".join(lines)


def connect_readonly(db_path: Path) -> sqlite3.Connection:
    if not db_path.exists():
        raise DashboardError(f"SQLite database not found: {db_path}")
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only = ON")
    return conn


def table_names(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
    ).fetchall()
    return {str(row["name"]) for row in rows}


def table_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {str(row["name"]) for row in conn.execute(f"PRAGMA table_info({quote_ident(table)})")}


def first_existing(tables: set[str], candidates: Iterable[str]) -> str | None:
    for table in candidates:
        if table in tables:
            return table
    return None


def fetch_rows(conn: sqlite3.Connection, table: str | None) -> list[dict[str, Any]]:
    if not table:
        return []
    rows = conn.execute(f"SELECT * FROM {quote_ident(table)}").fetchall()
    return [normalize_row(row) for row in rows]


def max_integer(conn: sqlite3.Connection, table: str, candidates: Iterable[str]) -> int | None:
    columns = table_columns(conn, table)
    for column in candidates:
        if column not in columns:
            continue
        row = conn.execute(
            f"SELECT MAX(CAST({quote_ident(column)} AS INTEGER)) AS max_value FROM {quote_ident(table)}"
        ).fetchone()
        if row and row["max_value"] is not None:
            return int(row["max_value"])
    return None


def source_event_seq(conn: sqlite3.Connection, tables: set[str]) -> int:
    events_table = first_existing(tables, ("events", "event_log", "org_events"))
    if events_table:
        value = max_integer(conn, events_table, ("seq", "event_seq", "source_event_seq", "id"))
        if value is not None:
            return value

    max_seen = 0
    for table in tables:
        value = max_integer(conn, table, ("source_event_seq", "event_seq"))
        if value is not None:
            max_seen = max(max_seen, value)
    return max_seen


def active_milestones(conn: sqlite3.Connection, tables: set[str]) -> list[dict[str, Any]]:
    table = first_existing(tables, ("active_milestones", "milestones", "goal_milestones"))
    rows = fetch_rows(conn, table)
    if table != "active_milestones":
        rows = [row for row in rows if as_text(value_of(row, "status")).lower() == "active"]
    return sorted(rows, key=lambda row: (as_text(value_of(row, "target_date", default="9999")), as_text(value_of(row, "id"))))


def queued_running_tasks(conn: sqlite3.Connection, tables: set[str]) -> list[dict[str, Any]]:
    table = first_existing(tables, ("tasks", "task_projection", "current_tasks"))
    rows = fetch_rows(conn, table)
    selected = [
        row
        for row in rows
        if as_text(value_of(row, "status")).lower() in TASK_STATUSES
    ]

    def sort_key(row: dict[str, Any]) -> tuple[int, str, str]:
        priority = as_text(value_of(row, "priority"), "P9").upper()
        updated = as_text(value_of(row, "updated_at", "created_at", "queued_at", default=""))
        return (PRIORITY_RANK.get(priority, 9), updated, as_text(value_of(row, "id")))

    return sorted(selected, key=sort_key)[:10]


def recent_decisions(conn: sqlite3.Connection, tables: set[str]) -> list[dict[str, Any]]:
    table = first_existing(tables, ("decisions", "decision_cards", "owner_decisions"))
    rows = fetch_rows(conn, table)

    def sort_key(row: dict[str, Any]) -> tuple[str, str]:
        timestamp = as_text(value_of(row, "decided_at", "resolved_at", "created_at", "updated_at", default=""))
        return (timestamp, as_text(value_of(row, "id")))

    return sorted(rows, key=sort_key, reverse=True)[:5]


def kernel_mode(conn: sqlite3.Connection, tables: set[str]) -> dict[str, Any]:
    table = first_existing(tables, ("kernel_mode", "kernel_modes", "kernel_state", "state"))
    rows = fetch_rows(conn, table)
    if not rows:
        return {"mode": "unknown", "updated_at": "", "source_event_seq": "", "enforced": ""}

    if table == "state":
        keyed = [row for row in rows if as_text(value_of(row, "key", "name")).lower() in {"kernel_mode", "kernel-mode"}]
        rows = keyed or rows

    rows = sorted(
        rows,
        key=lambda row: as_text(value_of(row, "updated_at", "created_at", "set_at", default="")),
        reverse=True,
    )
    row = rows[0]
    value_payload = parse_json_value(value_of(row, "value"))
    merge_payload(row, value_payload)
    invariants = value_of(row, "invariants", default="")
    if isinstance(invariants, str):
        parsed_invariants = parse_json_value(invariants)
        invariants = parsed_invariants or invariants
    if isinstance(invariants, dict):
        enforced = sorted(key for key, value in invariants.items() if str(value) == "enforce")
        invariants = ", ".join(enforced)
    return {
        "mode": value_of(row, "mode", "default", "default_mode", default="unknown"),
        "updated_at": value_of(row, "updated_at", "set_at", "created_at", default=""),
        "source_event_seq": value_of(row, "source_event_seq", "event_seq", default=""),
        "enforced": invariants,
    }


def render_dashboard(conn: sqlite3.Connection, generated_at: str) -> tuple[str, int, str]:
    tables = table_names(conn)
    seq = source_event_seq(conn, tables)
    milestones = active_milestones(conn, tables)
    tasks = queued_running_tasks(conn, tables)
    decisions = recent_decisions(conn, tables)
    mode = kernel_mode(conn, tables)

    milestone_rows = [
        [
            value_of(row, "id"),
            value_of(row, "title", "name"),
            value_of(row, "target_date", "due_at", default="-"),
            value_of(row, "status", default="active"),
        ]
        for row in milestones
    ]
    task_rows = [
        [
            value_of(row, "id", "task_id"),
            value_of(row, "status"),
            value_of(row, "priority", default="-"),
            value_of(row, "title", "summary", "name"),
            value_of(row, "owner_role", "assignee", default="-"),
        ]
        for row in tasks
    ]
    decision_rows = [
        [
            value_of(row, "id", "decision_id"),
            value_of(row, "decided_at", "resolved_at", "created_at", "updated_at", default="-"),
            value_of(row, "title", "decision", "summary"),
            value_of(row, "status", default="-"),
        ]
        for row in decisions
    ]
    mode_rows = [[mode["mode"], mode["updated_at"] or "-", mode["source_event_seq"] or seq, mode["enforced"] or "-"]]

    body = "\n".join(
        [
            "# DASHBOARD.generated.md",
            "",
            "> Shadow dashboard generated from SQLite. Do not edit by hand.",
            "",
            "## Kernel Mode",
            "",
            markdown_table(["Mode", "Updated At", "Source Event Seq", "Enforced Invariants"], mode_rows),
            "",
            "## Active Milestones",
            "",
            markdown_table(["ID", "Title", "Target Date", "Status"], milestone_rows),
            "",
            "## Queued / Running Tasks (Top 10)",
            "",
            markdown_table(["ID", "Status", "Priority", "Title", "Owner"], task_rows),
            "",
            "## Recent Decisions",
            "",
            markdown_table(["ID", "When", "Decision", "Status"], decision_rows),
            "",
        ]
    )
    checksum = hashlib.sha256(body.encode("utf-8")).hexdigest()
    header = "\n".join(
        [
            "---",
            "generated_by: scripts/org/generate-dashboard.py",
            f"generated_at: {generated_at}",
            f"source_event_seq: {seq}",
            f"checksum_sha256: {checksum}",
            "---",
            "",
        ]
    )
    return header + body, seq, checksum


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(path.parent),
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(content)
        tmp_path = Path(handle.name)
    tmp_path.replace(path)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(DEFAULT_DB), help="SQLite database path (default: .ai/orgos.sqlite)")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="dashboard output path")
    parser.add_argument("--repo-root", default=".", help="repository root for relative paths")
    parser.add_argument("--check", action="store_true", help="fail if output would change; do not write")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    repo_root = Path(args.repo_root).resolve()
    db_path = Path(args.db)
    output_path = Path(args.output)
    if not db_path.is_absolute():
        db_path = repo_root / db_path
    if not output_path.is_absolute():
        output_path = repo_root / output_path

    try:
        with connect_readonly(db_path) as conn:
            content, seq, checksum = render_dashboard(conn, utc_now())
        if args.check:
            existing = output_path.read_text(encoding="utf-8") if output_path.exists() else ""
            if existing != content:
                print(f"dashboard is out of date: {output_path}", file=sys.stderr)
                return 1
            return 0
        atomic_write(output_path, content)
        print(f"generated {output_path} from {db_path} (source_event_seq={seq}, checksum={checksum})")
        return 0
    except (OSError, sqlite3.Error, DashboardError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
