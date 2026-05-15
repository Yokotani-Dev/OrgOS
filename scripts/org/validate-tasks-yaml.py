#!/usr/bin/env python3
"""Validate .ai/TASKS.yaml against duplicate keys and basic schema."""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

try:
    from ruamel.yaml import YAML, constructor

    USE_RUAMEL = True
except ImportError:
    USE_RUAMEL = False


def _load_with_pyyaml(path: Path) -> Any:
    import yaml

    class DuplicateKeyLoader(yaml.SafeLoader):
        pass

    def no_duplicate_mapping(loader: DuplicateKeyLoader, node: yaml.MappingNode, deep: bool = False) -> dict:
        mapping = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            if key in mapping:
                mark = key_node.start_mark
                raise ValueError(f"line {mark.line + 1}, column {mark.column + 1}: duplicate key {key!r}")
            mapping[key] = loader.construct_object(value_node, deep=deep)
        return mapping

    DuplicateKeyLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
        no_duplicate_mapping,
    )

    content = path.read_text(encoding="utf-8")
    data = yaml.load(content, Loader=DuplicateKeyLoader)
    _heuristic_duplicate_key_scan(content)
    return data


def _heuristic_duplicate_key_scan(content: str) -> None:
    current_task_line = None
    seen_keys_in_task: dict[str, int] = {}

    for line_number, line in enumerate(content.splitlines(), 1):
        if re.match(r"^\s*-\s+id:\s+", line):
            current_task_line = line_number
            seen_keys_in_task = {"id": line_number}
            continue

        match = re.match(r"^ {4}([A-Za-z_][\w-]*):(?:\s|$)", line)
        if not match or current_task_line is None:
            continue

        key = match.group(1)
        if key in seen_keys_in_task:
            prev_line = seen_keys_in_task[key]
            raise ValueError(
                f"line {line_number}: duplicate key {key!r} from line {prev_line} "
                f"(task started at line {current_task_line})"
            )
        seen_keys_in_task[key] = line_number


def _load_yaml(path: Path) -> Any:
    if USE_RUAMEL:
        yaml = YAML(typ="safe")
        yaml.allow_duplicate_keys = False
        try:
            with path.open("r", encoding="utf-8") as handle:
                return yaml.load(handle)
        except constructor.DuplicateKeyError as exc:
            print(f"DUPLICATE_KEY: {exc}", file=sys.stderr)
            raise SystemExit(1) from exc

    try:
        return _load_with_pyyaml(path)
    except ValueError as exc:
        print(f"DUPLICATE_KEY: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


def _validate_task_ids(tasks: list[Any]) -> int:
    seen: dict[str, list[int]] = {}
    for index, task in enumerate(tasks):
        if isinstance(task, dict) and "id" in task:
            seen.setdefault(str(task["id"]), []).append(index)

    dupes = {task_id: indexes for task_id, indexes in seen.items() if len(indexes) > 1}
    if dupes:
        print(f"DUPLICATE_TASK_ID: {dupes}", file=sys.stderr)
        return 1
    return 0


def _validate_required_fields(tasks: list[Any]) -> int:
    for task in tasks:
        if not isinstance(task, dict):
            continue
        for field in ("id", "title", "status"):
            if field not in task:
                print(f"MISSING_FIELD: {field} in task {task.get('id', '?')}", file=sys.stderr)
                return 1
    return 0


def validate(path: str | Path) -> int:
    target = Path(path)
    try:
        data = _load_yaml(target)
    except SystemExit as exc:
        return int(exc.code)
    except Exception as exc:
        print(f"YAML_ERROR: {exc}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print("SCHEMA_ERROR: top-level YAML must be a mapping", file=sys.stderr)
        return 1

    tasks = data.get("tasks", [])
    if not isinstance(tasks, list):
        print("SCHEMA_ERROR: tasks must be a list", file=sys.stderr)
        return 1

    return _validate_task_ids(tasks) or _validate_required_fields(tasks)


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else ".ai/TASKS.yaml"
    return validate(path)


if __name__ == "__main__":
    sys.exit(main())
