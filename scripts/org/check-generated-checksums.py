#!/usr/bin/env python3
"""Verify generated view files against stored SQLite checksums."""
from __future__ import annotations

import argparse
import hashlib
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_DB_PATH = Path(".ai/orgos.sqlite")
GENERATED_VIEW_PATHS = (
    Path(".ai/DASHBOARD.generated.md"),
    Path(".ai/TASKS.generated.yaml"),
    Path(".ai/GLOSSARY.generated.md"),
    Path(".ai/DECISIONS.generated.md"),
)
SHA256_RE = re.compile(r"^(?:sha256:)?([0-9a-fA-F]{64})$")


@dataclass(frozen=True)
class CheckFailure:
    path: str
    expected: str
    actual: str
    reason: str


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare generated view file checksums with .ai/orgos.sqlite:view_checksums."
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="repository root containing .ai/ (default: current directory)",
    )
    parser.add_argument(
        "--db",
        default=None,
        help="SQLite database path (default: <repo-root>/.ai/orgos.sqlite)",
    )
    return parser.parse_args(argv)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_repo_path(path: str, repo_root: Path) -> str:
    candidate = Path(path)
    if candidate.is_absolute():
        try:
            candidate = candidate.resolve().relative_to(repo_root)
        except ValueError:
            pass
    normalized = candidate.as_posix()
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def normalize_sha256(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    match = SHA256_RE.fullmatch(value.strip())
    if not match:
        return None
    return match.group(1).lower()


def load_stored_checksums(db_path: Path, repo_root: Path) -> tuple[dict[str, str], str | None]:
    if not db_path.exists():
        return {}, f"checksum database not found: {db_path}"

    try:
        uri = f"file:{db_path.resolve().as_posix()}?mode=ro"
        with sqlite3.connect(uri, uri=True) as connection:
            rows = connection.execute("SELECT path, sha256 FROM view_checksums").fetchall()
    except sqlite3.Error as exc:
        return {}, f"cannot read view_checksums: {exc}"

    checksums: dict[str, str] = {}
    for raw_path, raw_sha256 in rows:
        if not isinstance(raw_path, str):
            continue
        normalized_path = normalize_repo_path(raw_path, repo_root)
        normalized_sha256 = normalize_sha256(raw_sha256)
        if normalized_sha256 is not None:
            checksums[normalized_path] = normalized_sha256
    return checksums, None


def check_generated_files(repo_root: Path, db_path: Path) -> tuple[list[str], list[CheckFailure]]:
    existing_paths = [
        path.as_posix()
        for path in GENERATED_VIEW_PATHS
        if (repo_root / path).is_file()
    ]
    if not existing_paths:
        return [], []

    stored_checksums, store_error = load_stored_checksums(db_path, repo_root)
    failures: list[CheckFailure] = []

    for rel_path in existing_paths:
        actual = sha256_file(repo_root / rel_path)
        expected = stored_checksums.get(rel_path)
        if store_error is not None:
            failures.append(
                CheckFailure(
                    path=rel_path,
                    expected="<unavailable>",
                    actual=actual,
                    reason=store_error,
                )
            )
        elif expected is None:
            failures.append(
                CheckFailure(
                    path=rel_path,
                    expected="<missing>",
                    actual=actual,
                    reason="missing row in view_checksums",
                )
            )
        elif expected != actual:
            failures.append(
                CheckFailure(
                    path=rel_path,
                    expected=expected,
                    actual=actual,
                    reason="checksum mismatch",
                )
            )

    return existing_paths, failures


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo_root = Path(args.repo_root).resolve()
    db_path = Path(args.db) if args.db else repo_root / DEFAULT_DB_PATH
    if not db_path.is_absolute():
        db_path = repo_root / db_path

    checked_paths, failures = check_generated_files(repo_root, db_path)
    if failures:
        print("generated checksum verification failed:", file=sys.stderr)
        for failure in failures:
            print(
                f"- {failure.path}: {failure.reason}; "
                f"expected={failure.expected} actual={failure.actual}",
                file=sys.stderr,
            )
        return 1

    if checked_paths:
        print(f"ok - verified {len(checked_paths)} generated checksum(s)")
    else:
        print("ok - no generated files present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
