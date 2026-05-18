#!/usr/bin/env python3
"""Initialize the OrgOS SQLite database."""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB_PATH = REPO_ROOT / ".ai" / "orgos.sqlite"
DEFAULT_SCHEMA_PATH = REPO_ROOT / ".claude" / "schemas" / "orgos.sqlite.schema.sql"


class InitSqliteError(Exception):
    pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Initialize .ai/orgos.sqlite from the OrgOS schema.")
    parser.add_argument(
        "--db-path",
        default=str(DEFAULT_DB_PATH),
        help="SQLite database path (default: .ai/orgos.sqlite)",
    )
    parser.add_argument(
        "--schema",
        default=str(DEFAULT_SCHEMA_PATH),
        help="SQL schema path (default: .claude/schemas/orgos.sqlite.schema.sql)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Remove the existing database and WAL sidecar files before initializing.",
    )
    return parser.parse_args(argv)


def remove_existing_database(db_path: Path) -> None:
    for path in (db_path, Path(f"{db_path}-wal"), Path(f"{db_path}-shm")):
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_dir():
            raise InitSqliteError(f"refusing to remove directory: {path}")
        path.unlink()


def load_schema(schema_path: Path) -> str:
    if not schema_path.is_file():
        raise InitSqliteError(f"schema file not found: {schema_path}")
    return schema_path.read_text(encoding="utf-8")


def initialize_database(db_path: Path, schema_path: Path, force: bool) -> str:
    schema_sql = load_schema(schema_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    if force:
        remove_existing_database(db_path)

    connection = sqlite3.connect(str(db_path))
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        journal_mode = connection.execute("PRAGMA journal_mode = WAL").fetchone()[0]
        if str(journal_mode).lower() != "wal":
            raise InitSqliteError(f"failed to enable WAL journal mode: {journal_mode}")
        connection.executescript(schema_sql)
        connection.commit()
        return str(journal_mode).lower()
    except sqlite3.Error as exc:
        connection.rollback()
        raise InitSqliteError(str(exc)) from exc
    finally:
        connection.close()


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    db_path = Path(args.db_path).expanduser()
    schema_path = Path(args.schema).expanduser()

    try:
        journal_mode = initialize_database(db_path, schema_path, args.force)
    except InitSqliteError as exc:
        print(f"init-sqlite: {exc}", file=sys.stderr)
        return 1

    print(f"database={db_path}")
    print(f"schema={schema_path}")
    print(f"journal_mode={journal_mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
