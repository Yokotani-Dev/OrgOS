#!/usr/bin/env python3
"""Safely append one decision record to .ai/DECISIONS.md.

This is the sanctioned org-tool mutator for DECISIONS.md (a kernel
PROTECTED_STATE_FILE). Direct Edit/Write of .ai/DECISIONS.md is denied
by the StateMutationViaOrgTool invariant; use this script instead.

Appends a well-formed section:

    ## <id>: <title> (<date>)

    <body>
"""
from __future__ import annotations

import argparse
import datetime
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

DEFAULT_DECISIONS_PATH = Path(".ai/DECISIONS.md")
# e.g. PLAN-UPDATE-025, TECH-DECISION-001, ISSUE-OS-001, PLAN-UPDATE-T-OS-461
ID_PATTERN = re.compile(r"^[A-Z][A-Z0-9]*(-[A-Za-z0-9]+)+$")
DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class AppendDecisionError(Exception):
    pass


def validate_id(decision_id: str) -> str:
    decision_id = decision_id.strip()
    if not ID_PATTERN.match(decision_id):
        raise AppendDecisionError(
            f"invalid decision id: {decision_id!r} "
            "(expected e.g. PLAN-UPDATE-025 or TECH-DECISION-001)"
        )
    return decision_id


def validate_date(raw: str) -> str:
    raw = raw.strip()
    if not DATE_PATTERN.match(raw):
        raise AppendDecisionError(f"invalid date: {raw!r} (expected YYYY-MM-DD)")
    try:
        datetime.date.fromisoformat(raw)
    except ValueError as exc:
        raise AppendDecisionError(f"invalid date: {raw!r} ({exc})") from exc
    return raw


def heading_exists(text: str, decision_id: str) -> bool:
    pattern = re.compile(rf"^##\s+{re.escape(decision_id)}(?=[:\s(])", re.MULTILINE)
    return bool(pattern.search(text))


def resolve_body(args: argparse.Namespace) -> str:
    if args.body is not None and args.body_file is not None:
        raise AppendDecisionError("use either --body or --body-file, not both")
    if args.body is not None:
        body = args.body
    elif args.body_file is not None:
        if args.body_file == "-":
            body = sys.stdin.read()
        else:
            body_path = Path(args.body_file)
            if not body_path.is_file():
                raise AppendDecisionError(f"body file not found: {body_path}")
            body = body_path.read_text(encoding="utf-8")
    else:
        raise AppendDecisionError("a body is required: pass --body or --body-file (use '-' for stdin)")
    body = body.strip("\n")
    if not body.strip():
        raise AppendDecisionError("decision body must not be empty")
    return body


def build_section(decision_id: str, title: str, date: str, body: str) -> str:
    title = " ".join(title.split())
    if not title:
        raise AppendDecisionError("--title must not be empty")
    return f"## {decision_id}: {title} ({date})\n\n{body}\n"


def atomic_append(path: Path, section: str) -> None:
    if not path.is_file():
        raise AppendDecisionError(f"decisions file not found: {path}")
    original = path.read_text(encoding="utf-8")
    updated = original.rstrip("\n") + "\n\n" + section

    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    os.close(fd)
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
        os.chmod(tmp_path, mode)
        tmp_path.write_text(updated, encoding="utf-8")
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Append a decision record to .ai/DECISIONS.md (sanctioned org-tool path)."
    )
    parser.add_argument("--id", required=True, dest="decision_id",
                        help="decision id, e.g. PLAN-UPDATE-025 or TECH-DECISION-001")
    parser.add_argument("--title", required=True, help="one-line decision title")
    parser.add_argument("--body", help="decision body (markdown)")
    parser.add_argument("--body-file", help="read body from file, or '-' for stdin")
    parser.add_argument("--date", default=datetime.date.today().isoformat(),
                        help="record date YYYY-MM-DD (default: today)")
    parser.add_argument("--file", default=str(DEFAULT_DECISIONS_PATH), help="DECISIONS.md path")
    return parser


def run(args: argparse.Namespace) -> int:
    path = Path(args.file)
    decision_id = validate_id(args.decision_id)
    date = validate_date(args.date)
    body = resolve_body(args)

    if not path.is_file():
        raise AppendDecisionError(f"decisions file not found: {path}")
    existing = path.read_text(encoding="utf-8")
    if heading_exists(existing, decision_id):
        raise AppendDecisionError(f"decision already exists: {decision_id} (refusing duplicate)")

    section = build_section(decision_id, args.title, date, body)
    atomic_append(path, section)
    print(f"appended {decision_id} to {path}")
    return 0


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return run(args)
    except AppendDecisionError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
