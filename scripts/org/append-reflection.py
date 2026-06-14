#!/usr/bin/env python3
"""Append (or update) one reflection in the REFLECTIONS ledger.

This is the sanctioned org-tool mutator for the Reflection Loop CORE
ledger (.ai/REFLECTIONS.jsonl). It mirrors the conventions of
scripts/org/append-decision.py and scripts/org/update-task.py:

  - atomic write via tempfile + os.replace
  - enum validation up front (invalid input -> non-zero exit, no write)
  - stdlib only (python3), no third-party deps

The REFLECTIONS ledger is a human-facing, durable per-repo knowledge
log: one JSON object per line under the .ai root (NOT .ai/_machine,
which is gitignored runtime state). See .ai/REFLECTIONS.md and
.ai/DESIGN/OBSERVABILITY_LEARNING_V2.md (課題 #4) for the design.

Reflection schema (one JSON object per line):

    {
      "id": "REF-YYYYMMDD-NNN",        # auto, scan existing ids
      "ts": "<UTC ISO8601>",            # stamped by this tool (datetime, UTC)
      "trigger": "owner_correction | self_error | principle",
      "text": "<the reflection>",
      "category": "behavioral | systemic | philosophical | one_off | unclassified",
      "status": "open | integrated | discarded",
      "integrated_into": "",            # promotion home path, when integrated
      "notes": ""
    }

Append mode (default):

    append-reflection.py --text "..." --trigger owner_correction \
        [--category behavioral] [--note "..."]

Update mode:

    append-reflection.py --id REF-20260614-001 --set-status integrated \
        [--set-category systemic] [--integrated-into ".claude/rules/foo.md"] \
        [--note "..."]
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

DEFAULT_LEDGER_RELPATH = Path(".ai/REFLECTIONS.jsonl")

TRIGGERS = ("owner_correction", "self_error", "principle")
CATEGORIES = ("behavioral", "systemic", "philosophical", "one_off", "unclassified")
STATUSES = ("open", "integrated", "discarded")

DEFAULT_CATEGORY = "unclassified"
DEFAULT_STATUS = "open"

# Title length cap for the best-effort activity-ledger mirror.
ACTIVITY_TITLE_MAX = 80


class AppendReflectionError(Exception):
    pass


def utc_now_iso() -> str:
    """UTC ISO8601 with a trailing Z (stdlib datetime, this is a normal script)."""
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .strftime("%Y-%m-%dT%H:%M:%SZ")
    )


def git_toplevel() -> Path | None:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    top = result.stdout.strip()
    return Path(top) if top else None


def resolve_repo_root(raw: str | None) -> Path:
    if raw:
        root = Path(raw).expanduser()
        if not root.is_dir():
            raise AppendReflectionError(f"--repo-root not a directory: {root}")
        return root.resolve()
    top = git_toplevel()
    if top is not None and top.is_dir():
        return top.resolve()
    return Path.cwd().resolve()


def validate_enum(label: str, value: str, allowed: tuple[str, ...]) -> str:
    value = value.strip()
    if value not in allowed:
        raise AppendReflectionError(
            f"invalid {label}: {value!r} (expected one of {', '.join(allowed)})"
        )
    return value


def read_records(path: Path) -> list[dict[str, Any]]:
    """Read existing reflection records, tolerating blank lines."""
    if not path.is_file():
        return []
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise AppendReflectionError(
                    f"corrupt ledger at {path} line {lineno}: {exc}"
                ) from exc
            if not isinstance(obj, dict):
                raise AppendReflectionError(
                    f"corrupt ledger at {path} line {lineno}: not a JSON object"
                )
            records.append(obj)
    return records


def next_id(records: list[dict[str, Any]], day: str) -> str:
    """Idempotent per-day id: REF-YYYYMMDD-NNN, NNN auto-incremented."""
    prefix = f"REF-{day}-"
    max_seq = 0
    for rec in records:
        rid = str(rec.get("id", ""))
        if rid.startswith(prefix):
            tail = rid[len(prefix):]
            if tail.isdigit():
                max_seq = max(max_seq, int(tail))
    return f"{prefix}{max_seq + 1:03d}"


def atomic_write_all(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps(rec, ensure_ascii=False, sort_keys=False) for rec in records]
    payload = "\n".join(lines) + "\n" if lines else ""

    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    os.close(fd)
    try:
        if path.exists():
            mode = stat.S_IMODE(path.stat().st_mode)
            os.chmod(tmp_path, mode)
        tmp_path.write_text(payload, encoding="utf-8")
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def mirror_to_activity(repo_root: Path, text: str) -> None:
    """Best-effort mirror into the central activity ledger. Never fails the run."""
    script = repo_root / "scripts" / "activity" / "log-event.sh"
    if not script.is_file():
        return
    title = " ".join(text.split())
    if len(title) > ACTIVITY_TITLE_MAX:
        title = title[: ACTIVITY_TITLE_MAX - 1].rstrip() + "…"
    try:
        subprocess.run(
            ["bash", str(script), "--type", "thought", "--title", title, "--source", "cli"],
            cwd=str(repo_root),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def do_append(args: argparse.Namespace, repo_root: Path, ledger: Path) -> int:
    text = (args.text or "").strip()
    if not text:
        raise AppendReflectionError("--text must not be empty")
    trigger = validate_enum("trigger", args.trigger, TRIGGERS)
    category = validate_enum("category", args.category, CATEGORIES)

    records = read_records(ledger)
    now = datetime.datetime.now(datetime.timezone.utc)
    day = now.strftime("%Y%m%d")
    record = {
        "id": next_id(records, day),
        "ts": utc_now_iso(),
        "trigger": trigger,
        "text": text,
        "category": category,
        "status": DEFAULT_STATUS,
        "integrated_into": "",
        "notes": args.note.strip() if args.note else "",
    }
    records.append(record)
    atomic_write_all(ledger, records)
    mirror_to_activity(repo_root, text)
    print(f"appended {record['id']} to {ledger}")
    return 0


def do_update(args: argparse.Namespace, ledger: Path) -> int:
    reflection_id = args.reflection_id.strip()

    new_status = (
        validate_enum("status", args.set_status, STATUSES) if args.set_status else None
    )
    new_category = (
        validate_enum("category", args.set_category, CATEGORIES) if args.set_category else None
    )
    integrated_into = args.integrated_into
    note = args.note.strip() if args.note else None

    if not any([new_status, new_category, integrated_into is not None, note]):
        raise AppendReflectionError(
            "update mode requires at least one of "
            "--set-status / --set-category / --integrated-into / --note"
        )

    records = read_records(ledger)
    target = None
    for rec in records:
        if str(rec.get("id", "")) == reflection_id:
            target = rec
            break
    if target is None:
        raise AppendReflectionError(f"reflection not found: {reflection_id}")

    if new_status is not None:
        target["status"] = new_status
    if new_category is not None:
        target["category"] = new_category
    if integrated_into is not None:
        target["integrated_into"] = integrated_into.strip()
    if note:
        existing = str(target.get("notes", "")).strip()
        target["notes"] = f"{existing}\n{note}".strip() if existing else note

    atomic_write_all(ledger, records)
    print(f"updated {reflection_id} in {ledger}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Append or update a reflection in .ai/REFLECTIONS.jsonl "
        "(sanctioned org-tool path; Reflection Loop CORE)."
    )
    # append mode
    parser.add_argument("--text", help="reflection text (append mode, required)")
    parser.add_argument(
        "--trigger",
        choices=TRIGGERS,
        help="what produced this reflection (append mode, required)",
    )
    parser.add_argument(
        "--category",
        default=DEFAULT_CATEGORY,
        choices=CATEGORIES,
        help=f"classification (append mode, default: {DEFAULT_CATEGORY})",
    )
    parser.add_argument("--note", help="free-form note (append or update mode)")
    # update mode
    parser.add_argument("--id", dest="reflection_id", help="reflection id to update")
    parser.add_argument("--set-status", choices=STATUSES, help="update mode: new status")
    parser.add_argument("--set-category", choices=CATEGORIES, help="update mode: new category")
    parser.add_argument(
        "--integrated-into",
        help="update mode: promotion home path (e.g. .claude/rules/foo.md)",
    )
    # common
    parser.add_argument(
        "--repo-root",
        help="repo root (default: git toplevel, else cwd). Used to locate the ledger.",
    )
    parser.add_argument(
        "--file",
        help="explicit ledger path (overrides --repo-root resolution)",
    )
    return parser


def resolve_ledger(args: argparse.Namespace, repo_root: Path) -> Path:
    if args.file:
        return Path(args.file).expanduser()
    return repo_root / DEFAULT_LEDGER_RELPATH


def run(args: argparse.Namespace) -> int:
    repo_root = resolve_repo_root(args.repo_root)
    ledger = resolve_ledger(args, repo_root)

    update_mode = args.reflection_id is not None
    if update_mode:
        if args.text is not None or args.trigger is not None:
            raise AppendReflectionError(
                "cannot mix update mode (--id) with append args (--text/--trigger)"
            )
        return do_update(args, ledger)

    # append mode
    if not args.text or not args.trigger:
        raise AppendReflectionError(
            "append mode requires both --text and --trigger "
            "(or use --id ... for update mode)"
        )
    return do_append(args, repo_root, ledger)


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return run(args)
    except AppendReflectionError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
