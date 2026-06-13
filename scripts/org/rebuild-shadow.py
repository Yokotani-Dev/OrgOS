#!/usr/bin/env python3
"""Rebuild the OrgOS SQLite shadow store and its generated views.

This is the single entry point that materializes the v1.0.0-promised
"SQLite shadow + generated views" so the SessionStart checksum verifier has a
real baseline to check against.

Pipeline (all idempotent, rebuildable):

  1. init .ai/orgos.sqlite from .claude/schemas/orgos.sqlite.schema.sql
  2. load .ai/TASKS.yaml into the kernel `tasks` table
  3. regenerate the generated views:
       - .ai/TASKS.generated.yaml      (scripts/org/generate-tasks-yaml.py)
       - .ai/DASHBOARD.generated.md    (scripts/org/generate-dashboard.py)
       - .ai/GLOSSARY.generated.md     (scripts/org/generate-glossary.py)
  4. write view_checksums rows (path, sha256, source_event_seq, generated_at)
     so scripts/org/check-generated-checksums.py verifies cleanly.

.ai/orgos.sqlite and the generated views are *rebuildable projections*: they
are gitignored and rebuilt from the source ledgers on demand. The source of
truth remains .ai/TASKS.yaml + the event log.

stdlib only; bash macOS 3.2 compatible callers; no third-party deps required
(ruamel.yaml is used if available, else PyYAML, matching the sibling scripts).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from ruamel.yaml import YAML

    _USE_RUAMEL = True
except ImportError:  # pragma: no cover - exercised on hosts without ruamel
    _USE_RUAMEL = False


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent

DEFAULT_DB_PATH = REPO_ROOT / ".ai" / "orgos.sqlite"
DEFAULT_TASKS_PATH = REPO_ROOT / ".ai" / "TASKS.yaml"
DEFAULT_SCHEMA_PATH = REPO_ROOT / ".claude" / "schemas" / "orgos.sqlite.schema.sql"

GENERATED_VIEWS = (
    Path(".ai/TASKS.generated.yaml"),
    Path(".ai/DASHBOARD.generated.md"),
    Path(".ai/GLOSSARY.generated.md"),
)

# Kernel tasks.status / tasks.role CHECK vocabularies live in the schema; the
# loader passes live ledger values straight through. A value the schema does
# not accept is coerced to a safe default and the original is preserved in
# metadata_json so the projection never silently rewrites real data.
_STATUS_FALLBACK = "queued"
_ROLE_FALLBACK = "implementer"
_PRIORITY_FALLBACK = "P2"
_VALID_PRIORITIES = {"P0", "P1", "P2", "P3"}

# Columns the kernel `tasks` table owns directly. Everything else from a task
# entry is carried in metadata_json so the projection round-trips.
_DIRECT_FIELDS = {
    "id",
    "title",
    "status",
    "priority",
    "owner_role",
    "allowed_paths",
    "deps",
    "acceptance",
    "notes",
}


class RebuildError(Exception):
    pass


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_yaml(path: Path) -> Any:
    if _USE_RUAMEL:
        yaml = YAML(typ="safe")
        yaml.allow_duplicate_keys = False
        with path.open("r", encoding="utf-8") as handle:
            return yaml.load(handle)
    import yaml  # type: ignore

    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def run_script(args: list[str]) -> None:
    result = subprocess.run(
        [sys.executable, *args],
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    label = Path(args[0]).name if args else "script"
    if result.returncode != 0:
        raise RebuildError(f"{label} failed (exit {result.returncode}):\n{result.stdout}")
    if result.stdout.strip():
        print(f"  {label}: {result.stdout.strip().splitlines()[-1]}")


# --- step 1: schema ---------------------------------------------------------

def init_database(db_path: Path, schema_path: Path) -> None:
    run_script(
        [
            str(SCRIPT_DIR / "init-sqlite.py"),
            "--db-path",
            str(db_path),
            "--schema",
            str(schema_path),
            "--force",
        ]
    )


# --- step 2: load tasks -----------------------------------------------------

def _json_list(value: Any) -> str:
    if value is None:
        items: list[Any] = []
    elif isinstance(value, list):
        items = value
    else:
        items = [value]
    return json.dumps([str(item) for item in items], ensure_ascii=False, separators=(",", ":"))


def _normalize_priority(value: Any) -> str:
    text = str(value).strip().upper() if value is not None else ""
    return text if text in _VALID_PRIORITIES else _PRIORITY_FALLBACK


def _task_row(task: dict[str, Any], valid_status: set[str], valid_role: set[str]) -> dict[str, Any]:
    task_id = task.get("id")
    if not task_id:
        raise RebuildError("task entry missing id")
    task_id = str(task_id)

    raw_status = str(task.get("status") or "").strip()
    status = raw_status if raw_status in valid_status else _STATUS_FALLBACK

    raw_role = str(task.get("owner_role") or "").strip()
    role = raw_role if raw_role in valid_role else _ROLE_FALLBACK

    # metadata_json carries everything not mapped to a dedicated column, plus
    # the coerced originals when the CHECK vocabulary forced a fallback.
    metadata: dict[str, Any] = {
        key: value for key, value in task.items() if key not in _DIRECT_FIELDS
    }
    if raw_status and raw_status != status:
        metadata["original_status"] = raw_status
    if raw_role and raw_role != role:
        metadata["original_owner_role"] = raw_role
    if raw_role:
        metadata.setdefault("owner_role", raw_role)

    return {
        "id": task_id,
        "title": str(task.get("title") or task_id),
        "status": status,
        "role": role,
        "priority": _normalize_priority(task.get("priority")),
        "allowed_paths_json": _json_list(task.get("allowed_paths")),
        "acceptance_criteria_json": _json_list(task.get("acceptance")),
        "dependencies_json": _json_list(task.get("deps")),
        "metadata_json": json.dumps(metadata, ensure_ascii=False, sort_keys=True, default=str),
    }


def _check_vocabulary(connection: sqlite3.Connection, column: str) -> set[str]:
    """Probe the live CHECK by trial insert is overkill; parse table SQL."""
    row = connection.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='tasks'"
    ).fetchone()
    sql = row[0] if row else ""
    values: set[str] = set()
    needle = f"{column} IN ("
    idx = sql.find(needle)
    if idx != -1:
        segment = sql[idx + len(needle): sql.find(")", idx)]
        for piece in segment.split(","):
            piece = piece.strip().strip("'\"")
            if piece:
                values.add(piece)
    return values


def load_tasks(db_path: Path, tasks_path: Path) -> int:
    data = load_yaml(tasks_path)
    if not isinstance(data, dict):
        raise RebuildError("TASKS.yaml top-level must be a mapping")
    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        raise RebuildError("TASKS.yaml must contain a tasks list")

    connection = sqlite3.connect(str(db_path))
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        valid_status = _check_vocabulary(connection, "status")
        valid_role = _check_vocabulary(connection, "role")
        rows = [_task_row(task, valid_status, valid_role) for task in tasks if isinstance(task, dict)]

        seen: set[str] = set()
        for row in rows:
            if row["id"] in seen:
                raise RebuildError(f"duplicate task id: {row['id']}")
            seen.add(row["id"])

        with connection:
            connection.execute("DELETE FROM tasks")
            connection.executemany(
                """
                INSERT INTO tasks (
                  id, title, status, role, priority,
                  allowed_paths_json, acceptance_criteria_json,
                  dependencies_json, metadata_json
                ) VALUES (
                  :id, :title, :status, :role, :priority,
                  :allowed_paths_json, :acceptance_criteria_json,
                  :dependencies_json, :metadata_json
                )
                """,
                rows,
            )
        return len(rows)
    except sqlite3.Error as exc:
        raise RebuildError(f"task load failed: {exc}") from exc
    finally:
        connection.close()


# --- step 3: regenerate views ----------------------------------------------

def regenerate_views(db_path: Path, generated_at: str) -> None:
    run_script(
        [
            str(SCRIPT_DIR / "generate-tasks-yaml.py"),
            "--db",
            str(db_path),
            "--output",
            str(REPO_ROOT / ".ai" / "TASKS.generated.yaml"),
            "--generated-at",
            generated_at,
        ]
    )
    run_script(
        [
            str(SCRIPT_DIR / "generate-dashboard.py"),
            "--db",
            str(db_path),
            "--output",
            str(REPO_ROOT / ".ai" / "DASHBOARD.generated.md"),
            "--repo-root",
            str(REPO_ROOT),
        ]
    )
    # Glossary is derived from rules + synthesis, not SQLite, but it is one of
    # the checked generated views so we refresh it in the same pass.
    run_script(
        [
            str(SCRIPT_DIR / "generate-glossary.py"),
            "--repo-root",
            str(REPO_ROOT),
            "--output",
            str(REPO_ROOT / ".ai" / "GLOSSARY.generated.md"),
        ]
    )


# --- step 4: write checksum baseline ---------------------------------------

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def current_source_event_seq(db_path: Path) -> int:
    try:
        with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as connection:
            row = connection.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events'"
            ).fetchone()
            if not row:
                return 0
            count = connection.execute("SELECT COUNT(*) FROM events").fetchone()
            return int(count[0] or 0)
    except sqlite3.Error:
        return 0


def write_checksums(db_path: Path, generated_at: str) -> list[str]:
    source_seq = current_source_event_seq(db_path)
    written: list[str] = []
    connection = sqlite3.connect(str(db_path))
    try:
        with connection:
            for rel in GENERATED_VIEWS:
                abs_path = REPO_ROOT / rel
                if not abs_path.is_file():
                    continue
                connection.execute(
                    """
                    INSERT INTO view_checksums (path, sha256, source_event_seq, generated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        sha256 = excluded.sha256,
                        source_event_seq = excluded.source_event_seq,
                        generated_at = excluded.generated_at
                    """,
                    (rel.as_posix(), sha256_file(abs_path), source_seq, generated_at),
                )
                written.append(rel.as_posix())
        return written
    except sqlite3.Error as exc:
        raise RebuildError(f"checksum write failed: {exc}") from exc
    finally:
        connection.close()


# --- orchestration ----------------------------------------------------------

def rebuild(db_path: Path, tasks_path: Path, schema_path: Path) -> int:
    generated_at = utc_now_iso()
    print(f"rebuild-shadow: db={db_path}")
    init_database(db_path, schema_path)
    task_count = load_tasks(db_path, tasks_path)
    print(f"  loaded {task_count} task(s) from {tasks_path.name}")
    regenerate_views(db_path, generated_at)
    written = write_checksums(db_path, generated_at)
    print(f"  wrote {len(written)} view_checksum row(s): {', '.join(written)}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-path", default=str(DEFAULT_DB_PATH), help="SQLite shadow path")
    parser.add_argument("--tasks-file", default=str(DEFAULT_TASKS_PATH), help="TASKS.yaml path")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA_PATH), help="SQL schema path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        return rebuild(
            Path(args.db_path).expanduser(),
            Path(args.tasks_file).expanduser(),
            Path(args.schema).expanduser(),
        )
    except RebuildError as exc:
        print(f"rebuild-shadow: ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
