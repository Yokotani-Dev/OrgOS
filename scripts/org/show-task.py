#!/usr/bin/env python3
"""Show one OrgOS task from a SQLite database."""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any


DEFAULT_DB_PATH = Path(".ai/tasks.sqlite")
TABLE_CANDIDATES = ("tasks", "task")
ID_COLUMN_CANDIDATES = ("id", "task_id")
PREFERRED_FIELDS = (
    "id",
    "title",
    "status",
    "priority",
    "owner_role",
    "milestone_ref",
    "created_at",
    "updated_at",
    "started_at",
    "done_at",
    "allowed_paths",
    "acceptance",
    "notes",
)


class TaskQueryError(Exception):
    pass


def quote_identifier(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def resolve_db_path(raw_path: str | None) -> Path:
    if raw_path:
        return Path(raw_path)
    env_path = os.environ.get("ORGOS_TASK_DB")
    if env_path:
        return Path(env_path)
    return DEFAULT_DB_PATH


def connect_db(path: Path) -> sqlite3.Connection:
    if not path.exists():
        raise TaskQueryError(f"SQLite database not found: {path}")
    connection = sqlite3.connect(str(path))
    connection.row_factory = sqlite3.Row
    return connection


def list_tables(connection: sqlite3.Connection) -> set[str]:
    rows = connection.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    return {str(row["name"]) for row in rows}


def table_columns(connection: sqlite3.Connection, table_name: str) -> list[str]:
    rows = connection.execute(f"PRAGMA table_info({quote_identifier(table_name)})").fetchall()
    return [str(row["name"]) for row in rows]


def find_tasks_table(connection: sqlite3.Connection) -> tuple[str, list[str]]:
    tables = list_tables(connection)
    for candidate in TABLE_CANDIDATES:
        if candidate in tables:
            columns = table_columns(connection, candidate)
            return candidate, columns
    raise TaskQueryError("SQLite database does not contain a tasks table")


def find_id_column(columns: list[str]) -> str:
    for candidate in ID_COLUMN_CANDIDATES:
        if candidate in columns:
            return candidate
    raise TaskQueryError("tasks table must contain id or task_id")


def normalize_row(row: sqlite3.Row, id_column: str) -> dict[str, Any]:
    item = dict(row)
    if id_column != "id":
        item["id"] = item.pop(id_column)
    return item


def fetch_task(
    connection: sqlite3.Connection,
    table_name: str,
    columns: list[str],
    id_column: str,
    task_id: str,
) -> dict[str, Any]:
    sql = "SELECT * FROM {table} WHERE {id_column} = ? LIMIT 1".format(
        table=quote_identifier(table_name),
        id_column=quote_identifier(id_column),
    )
    row = connection.execute(sql, (task_id,)).fetchone()
    if row is None:
        raise TaskQueryError(f"task not found: {task_id}")
    return normalize_row(row, id_column)


def field_order(task: dict[str, Any]) -> list[str]:
    ordered = [field for field in PREFERRED_FIELDS if field in task]
    ordered.extend(sorted(field for field in task if field not in ordered))
    return ordered


def text_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def render_markdown(task: dict[str, Any]) -> str:
    title = text_value(task.get("title"))
    heading = text_value(task.get("id"))
    if title:
        heading = f"{heading}: {title}"

    lines = [
        f"# {heading}",
        "",
        "| Field | Value |",
        "| --- | --- |",
    ]
    for field in field_order(task):
        value = text_value(task.get(field)).replace("\n", "<br>")
        lines.append(f"| {field} | {value} |")
    return "\n".join(lines)


def render_json(task: dict[str, Any]) -> str:
    return json.dumps({"task": task}, ensure_ascii=False, indent=2)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task_id", help="task id to show")
    parser.add_argument("--db", help="SQLite database path; defaults to ORGOS_TASK_DB or .ai/tasks.sqlite")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown", help="output format")
    return parser


def run(args: argparse.Namespace) -> int:
    db_path = resolve_db_path(args.db)
    with connect_db(db_path) as connection:
        table_name, columns = find_tasks_table(connection)
        id_column = find_id_column(columns)
        task = fetch_task(connection, table_name, columns, id_column, args.task_id)

    if args.format == "json":
        print(render_json(task))
    else:
        print(render_markdown(task))
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return run(args)
    except (sqlite3.Error, TaskQueryError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
