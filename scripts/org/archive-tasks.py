#!/usr/bin/env python3
"""Move terminal tasks from TASKS.yaml into TASKS_ARCHIVE.yaml."""
from __future__ import annotations

import argparse
import os
import stat
import subprocess
import sys
import tempfile
from copy import deepcopy
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

try:
    from ruamel.yaml import YAML
    from ruamel.yaml.comments import CommentedMap

    USE_RUAMEL = True
except ImportError:
    USE_RUAMEL = False
    CommentedMap = dict  # type: ignore[assignment,misc]


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_TASKS_PATH = Path(".ai/TASKS.yaml")
DEFAULT_ARCHIVE_PATH = Path(".ai/TASKS_ARCHIVE.yaml")
TERMINAL_STATUSES = {"done", "cancelled", "superseded"}
TIMESTAMP_FIELDS_BY_STATUS = {
    "done": ("done_at", "completed_at", "closed_at", "updated_at", "created_at"),
    "cancelled": ("cancelled_at", "canceled_at", "closed_at", "updated_at", "created_at"),
    "superseded": ("superseded_at", "closed_at", "updated_at", "created_at"),
}


class ArchiveTasksError(Exception):
    pass


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


def ensure_valid(path: Path, label: str) -> None:
    ok, output = validate_file(path)
    if not ok:
        raise ArchiveTasksError(f"{label} yaml failed validation: {output}")


def load_yaml_file(path: Path) -> tuple[Any, Any]:
    if USE_RUAMEL:
        yaml = YAML()
        yaml.preserve_quotes = True
        yaml.allow_duplicate_keys = False
        with path.open("r", encoding="utf-8") as handle:
            return yaml, yaml.load(handle)

    import yaml

    class IndentDumper(yaml.SafeDumper):
        def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
            return super().increase_indent(flow, False)

    with path.open("r", encoding="utf-8") as handle:
        return IndentDumper, yaml.safe_load(handle)


def dump_yaml_file(yaml_obj: Any, data: Any, path: Path) -> None:
    if USE_RUAMEL:
        with path.open("w", encoding="utf-8") as handle:
            yaml_obj.dump(data, handle)
        return

    import yaml

    with path.open("w", encoding="utf-8") as handle:
        yaml.dump(
            data,
            handle,
            Dumper=yaml_obj,
            allow_unicode=True,
            default_flow_style=False,
            sort_keys=False,
        )


def new_mapping() -> Any:
    return CommentedMap() if USE_RUAMEL else {}


def new_archive_data() -> Any:
    data = new_mapping()
    data["tasks"] = []
    return data


def get_tasks(data: Any, label: str) -> list[Any]:
    if not isinstance(data, dict):
        raise ArchiveTasksError(f"{label} yaml top-level must be a mapping")
    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        raise ArchiveTasksError(f"{label} yaml tasks must be a list")
    return tasks


def parse_datetime_value(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, date):
        parsed = datetime(value.year, value.month, value.day)
    elif isinstance(value, str):
        raw = value.strip()
        if not raw:
            return None
        if raw.endswith("Z"):
            raw = f"{raw[:-1]}+00:00"
        try:
            parsed = datetime.fromisoformat(raw)
        except ValueError:
            return None
    else:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def terminal_timestamp(task: dict[str, Any], status: str) -> datetime | None:
    for field in TIMESTAMP_FIELDS_BY_STATUS.get(status, ()):
        parsed = parse_datetime_value(task.get(field))
        if parsed is not None:
            return parsed
    return None


def threshold_allows(task: dict[str, Any], status: str, threshold_days: int | None, now: datetime) -> bool:
    if threshold_days is None:
        return True

    timestamp = terminal_timestamp(task, status)
    if timestamp is None:
        return False
    age_seconds = (now - timestamp).total_seconds()
    return age_seconds >= threshold_days * 24 * 60 * 60


def find_archive_candidates(
    tasks: list[Any],
    threshold_days: int | None,
    now: datetime,
) -> list[Any]:
    candidates = []
    for task in tasks:
        if not isinstance(task, dict):
            continue
        status = str(task.get("status", "")).strip().lower()
        if status not in TERMINAL_STATUSES:
            continue
        if threshold_allows(task, status, threshold_days, now):
            candidates.append(task)
    return candidates


def atomic_write(path: Path, yaml_obj: Any, data: Any, label: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    os.close(fd)

    try:
        if path.exists():
            mode = stat.S_IMODE(path.stat().st_mode)
            os.chmod(tmp_path, mode)
        dump_yaml_file(yaml_obj, data, tmp_path)
        ensure_valid(tmp_path, f"updated {label}")
        os.replace(tmp_path, path)
        ensure_valid(path, f"updated {label}")
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def parse_now(raw: str | None) -> datetime:
    if raw is None:
        return datetime.now(timezone.utc)
    parsed = parse_datetime_value(raw)
    if parsed is None:
        raise ArchiveTasksError(f"invalid --now value: {raw!r}")
    return parsed


def load_archive(path: Path) -> tuple[Any, Any]:
    if path.exists():
        ensure_valid(path, "archive")
        return load_yaml_file(path)

    if USE_RUAMEL:
        yaml = YAML()
        yaml.preserve_quotes = True
        yaml.allow_duplicate_keys = False
        return yaml, new_archive_data()

    import yaml

    class IndentDumper(yaml.SafeDumper):
        def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
            return super().increase_indent(flow, False)

    return IndentDumper, new_archive_data()


def task_id(task: Any) -> str:
    return str(task.get("id", "")) if isinstance(task, dict) else ""


def print_candidates(candidates: list[Any], threshold_days: int | None) -> None:
    threshold_note = "all terminal tasks" if threshold_days is None else f"terminal tasks older than {threshold_days} day(s)"
    print(f"would archive {len(candidates)} task(s) ({threshold_note})")
    for task in candidates:
        print(f"- {task_id(task)} [{task.get('status')}] {task.get('title', '')}")


def archive_tasks(args: argparse.Namespace) -> int:
    tasks_path = Path(args.tasks_file)
    archive_path = Path(args.archive_file)
    threshold_days = args.threshold_days
    if threshold_days is not None and threshold_days < 0:
        raise ArchiveTasksError("--threshold-days must be zero or greater")

    ensure_valid(tasks_path, "source TASKS")
    tasks_yaml, tasks_data = load_yaml_file(tasks_path)
    tasks = get_tasks(tasks_data, "source TASKS")
    now = parse_now(args.now)
    candidates = find_archive_candidates(tasks, threshold_days, now)

    if args.dry_run:
        print_candidates(candidates, threshold_days)
        return 0

    if not candidates:
        print("archived 0 task(s)")
        return 0

    archive_yaml, archive_data = load_archive(archive_path)
    archive_tasks_list = get_tasks(archive_data, "archive")

    candidate_ids = {task_id(task) for task in candidates}
    existing_archive_ids = {task_id(task) for task in archive_tasks_list}
    duplicate_ids = sorted(task_id for task_id in candidate_ids & existing_archive_ids if task_id)
    if duplicate_ids:
        raise ArchiveTasksError(f"archive already contains task id(s): {', '.join(duplicate_ids)}")

    archived_at = now.isoformat().replace("+00:00", "Z")
    for candidate in candidates:
        archived_task = deepcopy(candidate)
        archived_task["archived_at"] = archived_at
        archive_tasks_list.append(archived_task)

    tasks[:] = [task for task in tasks if task not in candidates]

    atomic_write(archive_path, archive_yaml, archive_data, "archive")
    atomic_write(tasks_path, tasks_yaml, tasks_data, "TASKS")

    print(f"archived {len(candidates)} task(s)")
    for candidate in candidates:
        print(f"- {task_id(candidate)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="show tasks that would be archived without writing files")
    parser.add_argument(
        "--threshold-days",
        type=int,
        default=None,
        help="archive only terminal tasks with a timestamp at least N days old; default archives all terminal tasks",
    )
    parser.add_argument("--tasks-file", default=str(DEFAULT_TASKS_PATH), help=argparse.SUPPRESS)
    parser.add_argument("--archive-file", default=str(DEFAULT_ARCHIVE_PATH), help=argparse.SUPPRESS)
    parser.add_argument("--now", help=argparse.SUPPRESS)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return archive_tasks(args)
    except ArchiveTasksError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
