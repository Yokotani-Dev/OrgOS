#!/usr/bin/env python3
"""Import .ai/TASKS.yaml into a shadow SQLite tasks table."""
from __future__ import annotations

import argparse
import json
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from ruamel.yaml import YAML

    USE_RUAMEL = True
except ImportError:
    USE_RUAMEL = False


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_TASKS_PATH = Path(".ai/TASKS.yaml")
DEFAULT_DB_PATH = Path(".ai/tasks-shadow.sqlite3")
ACTIVE_STATUSES = {"queued", "running", "blocked", "review"}


class ImportTasksError(Exception):
    pass


@dataclass(frozen=True)
class TaskRecord:
    id: str
    title: str | None
    status: str
    priority: str | None
    allowed_paths: str
    notes: str | None
    source_json: str

    def comparable(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "status": self.status,
            "priority": self.priority,
            "allowed_paths": json.loads(self.allowed_paths),
            "notes": self.notes,
        }


def validate_file(path: Path) -> tuple[bool, str]:
    validator = SCRIPT_DIR / "validate-tasks-yaml.py"
    result = subprocess.run(
        [sys.executable, str(validator), str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.returncode == 0, result.stderr.strip() or result.stdout.strip()


def ensure_valid_source(path: Path) -> None:
    ok, output = validate_file(path)
    if not ok:
        raise ImportTasksError(f"source TASKS yaml failed validation: {output}")


def load_yaml_file(path: Path) -> Any:
    if USE_RUAMEL:
        yaml = YAML(typ="safe")
        yaml.allow_duplicate_keys = False
        with path.open("r", encoding="utf-8") as handle:
            return yaml.load(handle)

    import yaml

    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def get_tasks(data: Any) -> list[Any]:
    if not isinstance(data, dict):
        raise ImportTasksError("top-level YAML must be a mapping")
    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        raise ImportTasksError("tasks must be a list")
    return tasks


def normalize_text(value: Any, field: str, required: bool = False) -> str | None:
    if value is None:
        if required:
            raise ImportTasksError(f"{field} is required")
        return None
    text = str(value)
    if required and not text:
        raise ImportTasksError(f"{field} must not be empty")
    return text


def normalize_allowed_paths(value: Any, task_id: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ImportTasksError(f"{task_id}: allowed_paths must be a list")
    return [str(path) for path in value]


def normalize_notes(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def task_records(tasks: list[Any]) -> list[TaskRecord]:
    records: list[TaskRecord] = []
    seen: set[str] = set()
    for index, task in enumerate(tasks):
        if not isinstance(task, dict):
            raise ImportTasksError(f"tasks[{index}] must be a mapping")

        task_id = normalize_text(task.get("id"), "id", required=True)
        assert task_id is not None
        if task_id in seen:
            raise ImportTasksError(f"duplicate task id: {task_id}")
        seen.add(task_id)

        status = normalize_text(task.get("status"), f"{task_id}.status", required=True)
        assert status is not None
        allowed_paths = normalize_allowed_paths(task.get("allowed_paths"), task_id)

        record = TaskRecord(
            id=task_id,
            title=normalize_text(task.get("title"), f"{task_id}.title"),
            status=status,
            priority=normalize_text(task.get("priority"), f"{task_id}.priority"),
            allowed_paths=json.dumps(allowed_paths, ensure_ascii=False, separators=(",", ":")),
            notes=normalize_notes(task.get("notes")),
            source_json=json.dumps(task, ensure_ascii=False, sort_keys=True, default=str),
        )
        records.append(record)
    return records


def is_active_status(status: str | None) -> bool:
    return str(status or "").strip().lower() in ACTIVE_STATUSES


def active_count(records: list[TaskRecord]) -> int:
    return sum(1 for record in records if is_active_status(record.status))


def connect_existing_readonly(path: Path) -> sqlite3.Connection | None:
    if not path.exists():
        return None
    uri = f"file:{path.resolve()}?mode=ro"
    return sqlite3.connect(uri, uri=True)


def table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table_name,),
    ).fetchone()
    return row is not None


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT,
            status TEXT NOT NULL,
            priority TEXT,
            allowed_paths TEXT NOT NULL,
            notes TEXT,
            source_json TEXT NOT NULL,
            imported_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        """
    )
    columns = existing_columns(conn)
    migrations = {
        "title": "ALTER TABLE tasks ADD COLUMN title TEXT",
        "priority": "ALTER TABLE tasks ADD COLUMN priority TEXT",
        "notes": "ALTER TABLE tasks ADD COLUMN notes TEXT",
        "source_json": "ALTER TABLE tasks ADD COLUMN source_json TEXT NOT NULL DEFAULT '{}'",
        "imported_at": "ALTER TABLE tasks ADD COLUMN imported_at TEXT",
    }
    for column, statement in migrations.items():
        if column not in columns:
            conn.execute(statement)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority)")


def existing_columns(conn: sqlite3.Connection) -> set[str]:
    return {str(row[1]) for row in conn.execute("PRAGMA table_info(tasks)").fetchall()}


def load_existing_records(conn: sqlite3.Connection | None) -> dict[str, TaskRecord]:
    if conn is None or not table_exists(conn, "tasks"):
        return {}

    columns = existing_columns(conn)
    required = {"id", "status", "allowed_paths"}
    missing = required - columns
    if missing:
        raise ImportTasksError(f"existing tasks table missing column(s): {', '.join(sorted(missing))}")

    selected = [
        "id",
        "title" if "title" in columns else "NULL AS title",
        "status",
        "priority" if "priority" in columns else "NULL AS priority",
        "allowed_paths",
        "notes" if "notes" in columns else "NULL AS notes",
        "source_json" if "source_json" in columns else "NULL AS source_json",
    ]
    rows = conn.execute(f"SELECT {', '.join(selected)} FROM tasks").fetchall()
    records: dict[str, TaskRecord] = {}
    for row in rows:
        raw_allowed_paths = row[4] or "[]"
        try:
            parsed_allowed_paths = json.loads(raw_allowed_paths)
        except json.JSONDecodeError:
            parsed_allowed_paths = raw_allowed_paths
        normalized_allowed_paths = json.dumps(parsed_allowed_paths, ensure_ascii=False, separators=(",", ":"))
        records[str(row[0])] = TaskRecord(
            id=str(row[0]),
            title=row[1],
            status=str(row[2]),
            priority=row[3],
            allowed_paths=normalized_allowed_paths,
            notes=row[5],
            source_json=row[6] or "{}",
        )
    return records


def diff_records(source: list[TaskRecord], existing: dict[str, TaskRecord]) -> tuple[list[str], list[str], list[str]]:
    source_by_id = {record.id: record for record in source}
    added = sorted(set(source_by_id) - set(existing))
    removed = sorted(set(existing) - set(source_by_id))
    modified = sorted(
        task_id
        for task_id in set(source_by_id) & set(existing)
        if source_by_id[task_id].comparable() != existing[task_id].comparable()
    )
    return added, removed, modified


def print_diff(source: list[TaskRecord], existing: dict[str, TaskRecord]) -> None:
    added, removed, modified = diff_records(source, existing)
    print(f"diff added={len(added)} removed={len(removed)} modified={len(modified)}")
    for label, ids in (("added", added), ("removed", removed), ("modified", modified)):
        for task_id in ids:
            print(f"{label}: {task_id}")


def import_records(db_path: Path, records: list[TaskRecord]) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db_path) as conn:
        ensure_schema(conn)
        with conn:
            conn.execute("DELETE FROM tasks")
            conn.executemany(
                """
                INSERT INTO tasks (id, title, status, priority, allowed_paths, notes, source_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        record.id,
                        record.title,
                        record.status,
                        record.priority,
                        record.allowed_paths,
                        record.notes,
                        record.source_json,
                    )
                    for record in records
                ],
            )


def sqlite_active_count(db_path: Path) -> int:
    with sqlite3.connect(db_path) as conn:
        ensure_schema(conn)
        placeholders = ",".join("?" for _ in ACTIVE_STATUSES)
        row = conn.execute(
            f"SELECT COUNT(*) FROM tasks WHERE lower(status) IN ({placeholders})",
            tuple(sorted(ACTIVE_STATUSES)),
        ).fetchone()
    return int(row[0])


def load_source_records(tasks_path: Path) -> list[TaskRecord]:
    ensure_valid_source(tasks_path)
    data = load_yaml_file(tasks_path)
    return task_records(get_tasks(data))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tasks-file", default=str(DEFAULT_TASKS_PATH), help="TASKS.yaml path")
    parser.add_argument("--db-file", default=str(DEFAULT_DB_PATH), help="SQLite DB path")
    parser.add_argument("--dry-run", action="store_true", help="parse and report without writing SQLite")
    parser.add_argument(
        "--diff-with-existing",
        action="store_true",
        help="print source-vs-existing tasks table diff before import",
    )
    return parser


def run(args: argparse.Namespace) -> int:
    tasks_path = Path(args.tasks_file)
    db_path = Path(args.db_file)
    records = load_source_records(tasks_path)
    yaml_active = active_count(records)

    existing_conn = connect_existing_readonly(db_path)
    try:
        existing = load_existing_records(existing_conn)
    finally:
        if existing_conn is not None:
            existing_conn.close()

    if args.diff_with_existing:
        print_diff(records, existing)

    if args.dry_run:
        print(f"dry-run: would import {len(records)} task(s) into {db_path}")
        print(f"active_count yaml={yaml_active} sqlite_after={yaml_active}")
        return 0

    import_records(db_path, records)
    sqlite_count = sqlite_active_count(db_path)
    print(f"imported {len(records)} task(s) into {db_path}")
    print(f"active_count yaml={yaml_active} sqlite={sqlite_count}")
    if sqlite_count != yaml_active:
        print(
            f"WARNING: active count mismatch yaml={yaml_active} sqlite={sqlite_count}",
            file=sys.stderr,
        )
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return run(args)
    except (ImportTasksError, OSError, sqlite3.Error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
