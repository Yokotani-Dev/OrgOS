#!/usr/bin/env python3
"""List OrgOS tasks from a SQLite database."""
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
LIST_COLUMNS = ("id", "title", "status", "priority", "owner_role", "updated_at", "created_at")


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


def selected_columns(columns: list[str], id_column: str) -> list[str]:
    selected: list[str] = []
    for column in LIST_COLUMNS:
        actual = id_column if column == "id" else column
        if actual in columns and actual not in selected:
            selected.append(actual)
    if id_column not in selected:
        selected.insert(0, id_column)
    return selected


def normalize_row(row: sqlite3.Row, id_column: str) -> dict[str, Any]:
    item = dict(row)
    if id_column != "id":
        item["id"] = item.pop(id_column)
    return item


def fetch_tasks(
    connection: sqlite3.Connection,
    table_name: str,
    columns: list[str],
    id_column: str,
    status: str | None,
    limit: int | None,
) -> list[dict[str, Any]]:
    selected = selected_columns(columns, id_column)
    sql = "SELECT " + ", ".join(quote_identifier(column) for column in selected)
    sql += f" FROM {quote_identifier(table_name)}"

    params: list[Any] = []
    if status is not None:
        if "status" not in columns:
            raise TaskQueryError("--status requires a status column")
        sql += " WHERE status = ?"
        params.append(status)

    sql += f" ORDER BY {quote_identifier(id_column)} ASC"
    if limit is not None:
        sql += " LIMIT ?"
        params.append(limit)

    rows = connection.execute(sql, params).fetchall()
    return [normalize_row(row, id_column) for row in rows]


def text_value(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("\n", " ")


def render_markdown(tasks: list[dict[str, Any]]) -> str:
    lines = [
        "| ID | Status | Priority | Title |",
        "| --- | --- | --- | --- |",
    ]
    for task in tasks:
        lines.append(
            "| {id} | {status} | {priority} | {title} |".format(
                id=text_value(task.get("id")),
                status=text_value(task.get("status")),
                priority=text_value(task.get("priority")),
                title=text_value(task.get("title")),
            )
        )
    return "\n".join(lines)


def render_json(tasks: list[dict[str, Any]]) -> str:
    return json.dumps({"tasks": tasks, "count": len(tasks)}, ensure_ascii=False, indent=2)


def positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("--limit must be an integer") from exc
    if value < 1:
        raise argparse.ArgumentTypeError("--limit must be greater than zero")
    return value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", help="SQLite database path; defaults to ORGOS_TASK_DB or .ai/tasks.sqlite")
    parser.add_argument("--status", help="filter by exact task status")
    parser.add_argument("--limit", type=positive_int, help="maximum number of tasks to return")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown", help="output format")
    return parser


def run(args: argparse.Namespace) -> int:
    db_path = resolve_db_path(args.db)
    with connect_db(db_path) as connection:
        table_name, columns = find_tasks_table(connection)
        id_column = find_id_column(columns)
        tasks = fetch_tasks(connection, table_name, columns, id_column, args.status, args.limit)

    if args.format == "json":
        print(render_json(tasks))
    else:
        print(render_markdown(tasks))
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
