#!/usr/bin/env python3
"""Gate task completion on explicit evidence events."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_EVENTS_PATH = REPO_ROOT / ".ai" / "_machine" / "evolution" / "events.jsonl"
REQUIRED_EVENTS = {"VerificationPassed", "CommitIntegrated"}


class EvidenceGateError(Exception):
    pass


def event_kinds(event: dict[str, Any]) -> list[str]:
    kinds: list[str] = []
    for key in ("event_type", "type", "event", "name", "event_name", "evidence_event", "kind"):
        value = event.get(key)
        if isinstance(value, str) and value.strip():
            kinds.append(value.strip())
    return kinds


def task_matches(event: dict[str, Any], task_id: str) -> bool:
    if str(event.get("task_id") or "") == task_id:
        return True

    task = event.get("task")
    if isinstance(task, dict) and str(task.get("id") or "") == task_id:
        return True

    evidence = event.get("evidence")
    if isinstance(evidence, dict) and str(evidence.get("task_id") or "") == task_id:
        return True

    return False


def load_task_events(path: Path, task_id: str) -> list[dict[str, Any]]:
    if not path.is_file():
        raise EvidenceGateError(f"events file not found: {path}")

    matches: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, start=1):
            if not raw.strip():
                continue
            try:
                event = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise EvidenceGateError(f"{path}:{line_no} is not valid JSON: {exc}") from exc
            if not isinstance(event, dict):
                raise EvidenceGateError(f"{path}:{line_no} must be a JSON object")
            if task_matches(event, task_id):
                matches.append(event)
    return matches


def check_evidence(task_id: str, events_path: Path) -> tuple[bool, str]:
    events = load_task_events(events_path, task_id)
    if not events:
        return False, f"no evidence events found for task {task_id}"

    observed = [kind for event in events for kind in event_kinds(event)]
    sufficient = sorted(set(observed).intersection(REQUIRED_EVENTS))
    if sufficient:
        return True, f"evidence sufficient for {task_id}: {', '.join(sufficient)}"

    observed_text = ", ".join(kind for kind in observed if kind) or "none"
    required_text = " or ".join(sorted(REQUIRED_EVENTS))
    return (
        False,
        f"missing required evidence for {task_id}: need {required_text}; observed {observed_text}",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task_id", help="task id to check")
    parser.add_argument(
        "--events",
        default=os.environ.get("EVENTS_PATH", str(DEFAULT_EVENTS_PATH)),
        help="path to events.jsonl (default: .ai/_machine/evolution/events.jsonl or EVENTS_PATH)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        ok, message = check_evidence(args.task_id, Path(args.events))
    except EvidenceGateError as exc:
        print(f"evidence insufficient: {exc}", file=sys.stderr)
        return 1

    if ok:
        print(message)
        return 0

    print(f"evidence insufficient: {message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
