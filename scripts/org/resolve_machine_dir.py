#!/usr/bin/env python3
"""Resolve an OrgOS machine-dir base name to an absolute path (new-then-legacy).

Safety net for the layout migration (T-OS-497, .ai/DESIGN/LAYOUT_MIGRATION_COMPAT.md
§3 機構2). New layout keeps machine dirs under ``.ai/_machine/<name>``. Older repos
keep them at ``.ai/<OLD>`` where ``<OLD>`` is the historical (often CamelCase) name.

Resolution order for ``resolve_machine_dir(name)``:
  1. ``<root>/.ai/_machine/<name>`` if it exists -> return it
  2. else ``<root>/.ai/<legacy>`` if any historical alias exists -> return that legacy path
  3. else default to the new ``<root>/.ai/_machine/<name>`` path (created on ``ensure``)

This lets new code read old data during the brief window before
``scripts/org/migrate-layout.sh`` runs (belt-and-suspenders).

stdlib only; python3.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Canonical machine-dir mapping (new lowercase base name -> historical aliases).
# Source of truth: .ai/DESIGN/ORGOS_TOBE_V3.md §4.3 and
# .ai/DESIGN/LAYOUT_MIGRATION_COMPAT.md. The first existing legacy alias wins.
LEGACY_ALIASES: dict[str, list[str]] = {
    "events": ["events"],
    "leases": ["leases"],
    "codex": ["CODEX"],
    "evolution": ["EVOLUTION"],
    "queue": ["queue"],
    "intelligence": ["INTELLIGENCE"],
    "metrics": ["METRICS"],
    "review": ["REVIEW"],
    "sessions": ["sessions"],
    "scheduler": ["SCHEDULER"],
    # artifacts historically split across CamelCase + lowercase (4.3); prefer
    # the larger ARTIFACTS, then artifacts.
    "artifacts": ["ARTIFACTS", "artifacts"],
    # Stage-1 LOW-risk dirs (kept here so the resolver is complete).
    "supervisor-review": ["SUPERVISOR_REVIEW"],
    "learnings": ["LEARNED", "LEARNINGS"],
    "approvals": ["APPROVALS"],
    "os": ["OS"],
    "backups": ["BACKUPS"],
    "integrity": ["INTEGRITY"],
}


def find_repo_root(start: Path | None = None) -> Path:
    """Walk up from ``start`` (default cwd) to the OrgOS repo root.

    A directory is the root if it has a ``.git`` entry or a ``scripts/org`` dir.
    Falls back to ``start`` when no marker is found.
    """
    current = (start or Path.cwd()).resolve()
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists() or (candidate / "scripts" / "org").is_dir():
            return candidate
    return current


def resolve_machine_dir(
    name: str,
    root: Path | str | None = None,
    ensure: bool = False,
) -> Path:
    """Return the absolute path for machine-dir base ``name``.

    Args:
        name: machine-dir base name, e.g. ``events``, ``leases``, ``codex``.
        root: repo root; defaults to auto-detection from cwd.
        ensure: when True, create the resolved directory's parent (and the
            directory itself for the new-layout default) if it does not exist.

    Resolution prefers the new ``.ai/_machine/<name>`` path, then any existing
    legacy ``.ai/<OLD>`` path, then defaults to the new path.
    """
    base = (Path(root) if root is not None else find_repo_root()).resolve()
    ai_dir = base / ".ai"
    new_path = ai_dir / "_machine" / name

    if new_path.exists():
        resolved = new_path
    else:
        resolved = None
        for alias in LEGACY_ALIASES.get(name, []):
            legacy_path = ai_dir / alias
            if legacy_path.exists():
                resolved = legacy_path
                break
        if resolved is None:
            resolved = new_path

    if ensure:
        if resolved == new_path:
            resolved.mkdir(parents=True, exist_ok=True)
        else:
            resolved.parent.mkdir(parents=True, exist_ok=True)

    return resolved


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", help="machine-dir base name (events, leases, codex, ...)")
    parser.add_argument("--root", help="repo root (default: auto-detect from cwd)")
    parser.add_argument(
        "--ensure",
        action="store_true",
        help="create the resolved (or its parent) directory if missing",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    path = resolve_machine_dir(args.name, root=args.root, ensure=args.ensure)
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
