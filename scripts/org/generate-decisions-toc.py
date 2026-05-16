#!/usr/bin/env python3
"""Generate or refresh the H2 table of contents in .ai/DECISIONS.md."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


DEFAULT_DECISIONS_PATH = Path(".ai/DECISIONS.md")
TOC_START = "<!-- TOC start -->"
TOC_END = "<!-- TOC end -->"
H2_RE = re.compile(r"^##\s+(.+?)\s*$", re.MULTILINE)


class TocError(Exception):
    pass


def strip_existing_toc(content: str) -> str:
    pattern = re.compile(
        rf"\n?{re.escape(TOC_START)}\n.*?\n{re.escape(TOC_END)}\n?",
        re.DOTALL,
    )
    return pattern.sub("\n", content, count=1)


def normalize_heading_for_anchor(heading: str) -> str:
    text = re.sub(r"`([^`]+)`", r"\1", heading)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[*_~]", "", text).strip().lower()
    text = re.sub(r"[^\w\s\-\u3000-\u30ff\u3400-\u9fff]", "", text, flags=re.UNICODE)
    text = re.sub(r"[\s_]+", "-", text, flags=re.UNICODE)
    text = re.sub(r"-+", "-", text).strip("-")
    return text or "section"


def build_unique_anchors(headings: list[str]) -> list[str]:
    seen: dict[str, int] = {}
    anchors: list[str] = []
    for heading in headings:
        base = normalize_heading_for_anchor(heading)
        count = seen.get(base, 0)
        seen[base] = count + 1
        anchors.append(base if count == 0 else f"{base}-{count}")
    return anchors


def extract_h2_headings(content: str) -> list[str]:
    return [match.group(1).strip() for match in H2_RE.finditer(content)]


def build_toc(headings: list[str]) -> str:
    anchors = build_unique_anchors(headings)
    lines = [TOC_START, "## Table of Contents", ""]
    lines.extend(f"- [{heading}](#{anchor})" for heading, anchor in zip(headings, anchors))
    lines.extend(["", TOC_END])
    return "\n".join(lines)


def insertion_index(content: str) -> int:
    match = H2_RE.search(content)
    if match:
        return match.start()
    return len(content)


def render_with_toc(content: str) -> str:
    content_without_toc = strip_existing_toc(content).strip() + "\n"
    headings = extract_h2_headings(content_without_toc)
    if not headings:
        raise TocError("no H2 headings found")

    toc = build_toc(headings)
    index = insertion_index(content_without_toc)
    prefix = content_without_toc[:index].rstrip()
    suffix = content_without_toc[index:].lstrip()
    return f"{prefix}\n\n{toc}\n\n{suffix}"


def update_file(path: Path, check: bool = False) -> int:
    if not path.exists():
        raise TocError(f"decisions file not found: {path}")

    original = path.read_text(encoding="utf-8")
    updated = render_with_toc(original)
    if check:
        if original != updated:
            print(f"TOC is out of date: {path}", file=sys.stderr)
            return 1
        return 0

    if original != updated:
        path.write_text(updated, encoding="utf-8")
        print(f"updated TOC in {path}")
    else:
        print(f"TOC already up to date in {path}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--file",
        default=str(DEFAULT_DECISIONS_PATH),
        help="DECISIONS.md path to update (default: .ai/DECISIONS.md)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="return non-zero if the TOC would change, without writing",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    try:
        return update_file(Path(args.file), check=args.check)
    except TocError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
