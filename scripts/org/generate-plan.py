#!/usr/bin/env python3
"""Generate a Plan Contract YAML file from a Codex Work Order."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator


DEFAULT_VERIFICATION = ["bash tests/kernel/run-kernel-tests.sh"]
SCHEMA_VERSION = "orgos.plan_contract.v1"


class PlanGenerationError(Exception):
    """Raised when a Work Order cannot be converted into a valid plan."""


def _section_pattern(name: str) -> re.Pattern[str]:
    return re.compile(rf"^##\s+{re.escape(name)}(?:\s|$)", re.IGNORECASE)


def _find_h1(lines: list[str]) -> str:
    for line in lines:
        if line.startswith("# "):
            return line[2:].strip()
    raise PlanGenerationError("missing H1 title")


def _title_from_h1(h1: str, task_id: str) -> str:
    match = re.search(rf"\b{re.escape(task_id)}\b\s*[:\-–—]\s*(.+)$", h1)
    if match:
        title = match.group(1).strip()
    else:
        title = re.sub(rf"^.*\b{re.escape(task_id)}\b", "", h1).strip(" :-–—")

    if not title:
        raise PlanGenerationError(f"could not extract title after task id {task_id}")
    return title


def _extract_section(lines: list[str], section_name: str) -> list[str]:
    start = None
    pattern = _section_pattern(section_name)
    for index, line in enumerate(lines):
        if pattern.match(line):
            start = index + 1
            break

    if start is None:
        raise PlanGenerationError(f'missing "## {section_name}" section')

    end = len(lines)
    for index in range(start, len(lines)):
        if lines[index].startswith("## "):
            end = index
            break

    return lines[start:end]


def _strip_inline_code(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value.startswith("`") and value.endswith("`"):
        return value[1:-1].strip()
    return value


def _extract_bullets(section_lines: list[str], section_name: str) -> list[str]:
    items: list[str] = []
    for line in section_lines:
        match = re.match(r"^\s*[-*]\s+(.*\S)\s*$", line)
        if match:
            items.append(_strip_inline_code(match.group(1)))

    if not items:
        raise PlanGenerationError(f'"## {section_name}" section has no bullets')
    return items


def parse_work_order(path: Path, task_id: str) -> dict[str, Any]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError as exc:
        raise PlanGenerationError(f"work order not found: {path}") from exc

    h1 = _find_h1(lines)
    return {
        "schema_version": SCHEMA_VERSION,
        "task_id": task_id,
        "title": _title_from_h1(h1, task_id),
        "acceptance": _extract_bullets(_extract_section(lines, "Acceptance"), "Acceptance"),
        "allowed_paths": _extract_bullets(_extract_section(lines, "Allowed Paths"), "Allowed Paths"),
        "verification": DEFAULT_VERIFICATION,
    }


def validate_plan(plan_path: Path, schema_path: Path) -> None:
    if not schema_path.exists():
        raise PlanGenerationError(f"schema not found: {schema_path}")

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        data = yaml.safe_load(plan_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, yaml.YAMLError) as exc:
        raise PlanGenerationError(f"failed to load plan or schema: {exc}") from exc

    errors = sorted(Draft202012Validator(schema).iter_errors(data), key=lambda error: list(error.path))
    if errors:
        details = "; ".join(error.message for error in errors[:3])
        raise PlanGenerationError(f"generated plan failed schema validation: {details}")


def write_plan_atomic(plan: dict[str, Any], output_path: Path, schema_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.",
        suffix=".tmp",
        dir=str(output_path.parent),
        text=True,
    )
    tmp_path = Path(tmp_name)

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            yaml.safe_dump(plan, handle, sort_keys=False, allow_unicode=True)
            handle.flush()
            os.fsync(handle.fileno())

        validate_plan(tmp_path, schema_path)
        os.replace(tmp_path, output_path)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate .ai/plans/<TASK_ID>.plan.yaml from a Codex Work Order.",
    )
    parser.add_argument("task_id", help="Task id such as T-OS-455")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Repository root containing .ai/CODEX/ORDERS and .claude/schemas",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo_root = Path(args.repo_root).resolve()
    task_id = args.task_id
    order_path = repo_root / ".ai" / "CODEX" / "ORDERS" / f"{task_id}.md"
    output_path = repo_root / ".ai" / "plans" / f"{task_id}.plan.yaml"
    schema_path = repo_root / ".claude" / "schemas" / "plan-contract.v1.json"

    try:
        plan = parse_work_order(order_path, task_id)
        write_plan_atomic(plan, output_path, schema_path)
    except PlanGenerationError as exc:
        print(f"generate-plan: {exc}", file=sys.stderr)
        return 1

    print(output_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
