#!/usr/bin/env python3
"""Generate TASKS.generated.yaml from the OrgOS SQLite tasks projection."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import stat
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from ruamel.yaml import YAML

    USE_RUAMEL = True
except ImportError:
    USE_RUAMEL = False


DEFAULT_DB_PATH = Path(".ai/orgos.sqlite")
DEFAULT_OUTPUT_PATH = Path(".ai/TASKS.generated.yaml")
REQUIRED_TASK_COLUMNS = ("id", "title", "status")
PREFERRED_TASK_FIELD_ORDER = (
    "id",
    "title",
    "status",
    "priority",
    "deps",
    "owner_role",
    "allowed_paths",
    "autonomy_level",
    "blast_radius",
    "owner_input_needed",
    "risk_level",
    "default_if_no_response",
    "reversibility",
    "acceptance",
    "blocker",
    "notes",
    "description",
    "project_id",
    "source",
    "created_at",
    "updated_at",
)


class GenerateTasksYamlError(Exception):
    pass


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def open_readonly_db(path: Path) -> sqlite3.Connection:
    if not path.exists():
        raise GenerateTasksYamlError(f"database not found: {path}")
    uri = f"file:{path.resolve()}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def table_exists(connection: sqlite3.Connection, table_name: str) -> bool:
    row = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table_name,),
    ).fetchone()
    return row is not None


def task_columns(connection: sqlite3.Connection) -> list[str]:
    if not table_exists(connection, "tasks"):
        raise GenerateTasksYamlError("SQLite database must contain a tasks table")

    rows = connection.execute("PRAGMA table_info(tasks)").fetchall()
    columns = [str(row["name"]) for row in rows]
    missing = [column for column in REQUIRED_TASK_COLUMNS if column not in columns]
    if missing:
        raise GenerateTasksYamlError(f"tasks table missing required column(s): {', '.join(missing)}")
    return columns


def event_columns(connection: sqlite3.Connection) -> list[str]:
    rows = connection.execute("PRAGMA table_info(events)").fetchall()
    return [str(row["name"]) for row in rows]


def source_event_seq(connection: sqlite3.Connection, columns: list[str]) -> int:
    if table_exists(connection, "events"):
        event_cols = event_columns(connection)
        # Prefer an explicit monotonic sequence column when present (kernel
        # fixture schema uses `seq`). The live kernel schema
        # (.claude/schemas/orgos.sqlite.schema.sql) has no `seq` column, so
        # fall back to a count of events as the projection's source seq.
        if "seq" in event_cols:
            row = connection.execute("SELECT COALESCE(MAX(seq), 0) AS seq FROM events").fetchone()
            return int(row["seq"] or 0)
        row = connection.execute("SELECT COUNT(*) AS seq FROM events").fetchone()
        return int(row["seq"] or 0)

    if "source_event_seq" in columns:
        row = connection.execute("SELECT COALESCE(MAX(source_event_seq), 0) AS seq FROM tasks").fetchone()
        return int(row["seq"] or 0)

    return 0


def parse_json_column(raw: Any, column: str, task_id: str) -> Any:
    if raw is None or raw == "":
        return None
    if not isinstance(raw, str):
        return raw
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GenerateTasksYamlError(f"invalid JSON in tasks.{column} for {task_id}: {exc.msg}") from exc


def projected_field_name(column: str) -> str:
    if column.endswith("_json"):
        return column[: -len("_json")]
    return column


def reorder_task_fields(task: dict[str, Any]) -> dict[str, Any]:
    ordered: dict[str, Any] = {}
    for field in PREFERRED_TASK_FIELD_ORDER:
        if field in task:
            ordered[field] = task[field]
    for field in sorted(task):
        if field not in ordered:
            ordered[field] = task[field]
    return ordered


def row_to_task(row: sqlite3.Row, columns: list[str]) -> dict[str, Any]:
    task_id = str(row["id"])
    task: dict[str, Any] = {}
    for column in columns:
        value = row[column]
        if column.endswith("_json"):
            value = parse_json_column(value, column, task_id)
        if value is None or value == "":
            continue
        task[projected_field_name(column)] = value

    return reorder_task_fields(task)


def load_tasks(connection: sqlite3.Connection, columns: list[str]) -> list[dict[str, Any]]:
    rows = connection.execute("SELECT * FROM tasks ORDER BY id ASC").fetchall()
    return [row_to_task(row, columns) for row in rows]


def payload_sha256(source_seq: int, tasks: list[dict[str, Any]]) -> str:
    payload = {
        "source_event_seq": source_seq,
        "tasks": tasks,
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def generated_data(connection: sqlite3.Connection, generated_at: str) -> dict[str, Any]:
    columns = task_columns(connection)
    tasks = load_tasks(connection, columns)
    source_seq = source_event_seq(connection, columns)
    return {
        "ORGOS-GENERATED": True,
        "source_event_seq": source_seq,
        "sha256": payload_sha256(source_seq, tasks),
        "generated_at": generated_at,
        "tasks": tasks,
    }


def dump_yaml(data: dict[str, Any], path: Path) -> None:
    if USE_RUAMEL:
        yaml = YAML()
        yaml.default_flow_style = False
        yaml.indent(mapping=2, sequence=4, offset=2)
        with path.open("w", encoding="utf-8") as handle:
            yaml.dump(data, handle)
        return

    import yaml

    class IndentDumper(yaml.SafeDumper):
        def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
            return super().increase_indent(flow, False)

    with path.open("w", encoding="utf-8") as handle:
        yaml.dump(
            data,
            handle,
            Dumper=IndentDumper,
            allow_unicode=True,
            default_flow_style=False,
            sort_keys=False,
        )


def atomic_write_yaml(data: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{output_path.name}.", suffix=".tmp", dir=str(output_path.parent))
    tmp_path = Path(tmp_name)
    os.close(fd)

    try:
        if output_path.exists():
            mode = stat.S_IMODE(output_path.stat().st_mode)
            os.chmod(tmp_path, mode)
        dump_yaml(data, tmp_path)
        os.replace(tmp_path, output_path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite database path")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="generated TASKS YAML path")
    parser.add_argument("--generated-at", help="override generated_at timestamp for deterministic tests")
    return parser


def run(args: argparse.Namespace) -> int:
    db_path = Path(args.db)
    output_path = Path(args.output)
    generated_at = args.generated_at or utc_now_iso()

    connection = open_readonly_db(db_path)
    try:
        data = generated_data(connection, generated_at)
    finally:
        connection.close()

    atomic_write_yaml(data, output_path)
    print(f"generated {output_path} from {db_path} ({len(data['tasks'])} task(s))")
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return run(args)
    except (GenerateTasksYamlError, sqlite3.Error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
