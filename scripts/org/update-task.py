#!/usr/bin/env python3
"""Safely update one task entry in .ai/TASKS.yaml."""
from __future__ import annotations

import argparse
import ast
import os
import stat
import subprocess
import sys
import tempfile
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


class UpdateTaskError(Exception):
    pass


def parse_value(raw: str) -> Any:
    lowered = raw.strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered == "null":
        return None

    try:
        return ast.literal_eval(raw)
    except (SyntaxError, ValueError):
        return raw


def parse_set(value: str) -> tuple[str, Any]:
    if "=" not in value:
        raise UpdateTaskError(f"--set requires FIELD=VALUE, got {value!r}")
    key, raw = value.split("=", 1)
    key = key.strip()
    if not key:
        raise UpdateTaskError("--set field name must not be empty")
    return key, parse_value(raw)


def load_tasks_file(path: Path) -> tuple[Any, Any]:
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


LEGACY_HEADER = "# ORGOS-LEGACY: use scripts/org/update-task.py\n"


def dump_tasks_file(yaml_obj: Any, data: Any, path: Path) -> None:
    if USE_RUAMEL:
        with path.open("w", encoding="utf-8") as handle:
            handle.write(LEGACY_HEADER)
            yaml_obj.dump(data, handle)
        return

    import yaml

    with path.open("w", encoding="utf-8") as handle:
        handle.write(LEGACY_HEADER)
        yaml.dump(
            data,
            handle,
            Dumper=yaml_obj,
            allow_unicode=True,
            default_flow_style=False,
            sort_keys=False,
        )


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
        raise UpdateTaskError(f"source TASKS yaml failed validation: {output}")


def get_tasks(data: Any) -> list[Any]:
    if not isinstance(data, dict):
        raise UpdateTaskError("top-level YAML must be a mapping")
    tasks = data.get("tasks")
    if not isinstance(tasks, list):
        raise UpdateTaskError("tasks must be a list")
    return tasks


def find_task(tasks: list[Any], task_id: str) -> Any | None:
    for task in tasks:
        if isinstance(task, dict) and str(task.get("id", "")) == task_id:
            return task
    return None


def new_mapping() -> Any:
    return CommentedMap() if USE_RUAMEL else {}


def create_task(tasks: list[Any], args: argparse.Namespace) -> Any:
    if find_task(tasks, args.task_id) is not None:
        raise UpdateTaskError(f"task already exists: {args.task_id}")
    if not args.title:
        raise UpdateTaskError("--create requires --title")
    if not args.status:
        raise UpdateTaskError("--create requires --status")

    task = new_mapping()
    task["id"] = args.task_id
    task["title"] = args.title
    task["status"] = args.status
    if args.priority:
        task["priority"] = args.priority
    tasks.append(task)
    return task


def add_note(task: Any, note: str) -> None:
    existing = task.get("notes")
    if existing in (None, ""):
        task["notes"] = note
    elif isinstance(existing, list):
        existing.append(note)
    else:
        task["notes"] = f"{existing}\n{note}"


def atomic_write(path: Path, yaml_obj: Any, data: Any) -> None:
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    os.close(fd)

    try:
        if path.exists():
            mode = stat.S_IMODE(path.stat().st_mode)
            os.chmod(tmp_path, mode)
        dump_tasks_file(yaml_obj, data, tmp_path)
        ok, output = validate_file(tmp_path)
        if not ok:
            raise UpdateTaskError(f"updated TASKS yaml failed validation: {output}")
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task_id", nargs="?", help="task id to update")
    parser.add_argument("--file", default=str(DEFAULT_TASKS_PATH), help="TASKS.yaml path")
    parser.add_argument("--list-ids", action="store_true", help="print task ids and exit")
    parser.add_argument("--create", action="store_true", help="create a new task entry")
    parser.add_argument("--title", help="title for --create")
    parser.add_argument("--status", help="status for --create")
    parser.add_argument("--priority", help="priority for --create")
    parser.add_argument("--set", dest="sets", action="append", default=[], help="set FIELD=VALUE")
    parser.add_argument("--add-note", action="append", default=[], help="append to notes")
    return parser


def run(args: argparse.Namespace) -> int:
    path = Path(args.file)
    ensure_valid_source(path)
    yaml_obj, data = load_tasks_file(path)
    tasks = get_tasks(data)

    if args.list_ids:
        for task in tasks:
            if isinstance(task, dict) and "id" in task:
                print(task["id"])
        return 0

    if not args.task_id:
        raise UpdateTaskError("task_id is required unless --list-ids is used")

    if args.create:
        task = create_task(tasks, args)
    else:
        task = find_task(tasks, args.task_id)
        if task is None:
            raise UpdateTaskError(f"task not found: {args.task_id}")

    for item in args.sets:
        key, value = parse_set(item)
        task[key] = value

    for note in args.add_note:
        add_note(task, note)

    if not args.create and not args.sets and not args.add_note:
        raise UpdateTaskError("no update requested")

    atomic_write(path, yaml_obj, data)
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return run(args)
    except UpdateTaskError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
