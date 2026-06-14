#!/usr/bin/env python3
"""
set-project-name.py — OrgOS sanctioned tool

CONTROL.yaml の `project_name` を、クローン先フォルダ名（git toplevel の basename、
無ければ repo root の basename）に自動設定する。/org-start から呼ばれる想定。

設計:
- 既定では project_name が "<SET_ME>" / 空 / 未設定 のときだけ設定する（意図的な命名を壊さない）。
  --force で常に設定。
- is_orgos_dev: true のリポジトリ（OrgOS フレームワーク本体）は既定でスキップ（--force でも対象外）。
- CONTROL.yaml は人間向けコメントを多く含むため、PyYAML で読み書きせず
  `project_name:` の行だけを正規表現で置換し、他バイトは保持する（コメント温存）。
- 冪等。既に目的の名前なら no-op。

Usage:
  set-project-name.py [--repo-root PATH] [--name NAME] [--force] [--dry-run] [--quiet]
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

# 比較は current.strip().lower() で行うため、すべて小文字で定義する
PLACEHOLDERS = {"", "<set_me>", "set_me", "todo", "tbd", "<name>"}
LINE_RE = re.compile(r'^(?P<indent>[ \t]*)project_name:(?P<rest>.*)$', re.M)


def split_value_comment(rest: str) -> tuple[str, str]:
    """YAML スカラ値とインラインコメントを分離する。値はクォート除去済み。"""
    s = rest.lstrip()
    if s[:1] in ('"', "'"):
        q = s[0]
        end = s.find(q, 1)
        if end != -1:
            value = s[1:end]
            comment = s[end + 1:].strip()
            return value, comment
    m = re.search(r'\s#', s)
    if m:
        return s[:m.start()].strip(), s[m.start():].strip()
    return s.strip(), ""


def detect_repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
        top = out.stdout.strip()
        if top:
            return Path(top).resolve()
    except Exception:
        pass
    return Path.cwd().resolve()


def main() -> int:
    ap = argparse.ArgumentParser(description="Set CONTROL.yaml project_name from the repo folder name.")
    ap.add_argument("--repo-root", default=None, help="repo root (default: git toplevel or cwd)")
    ap.add_argument("--name", default=None, help="explicit name (default: folder basename)")
    ap.add_argument("--force", action="store_true", help="overwrite even a non-placeholder name (still skips is_orgos_dev)")
    ap.add_argument("--dry-run", action="store_true", help="print the planned change, write nothing")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    root = detect_repo_root(args.repo_root)
    control = root / ".ai" / "CONTROL.yaml"

    def say(msg: str) -> None:
        if not args.quiet:
            print(msg)

    if not control.is_file():
        say(f"set-project-name: .ai/CONTROL.yaml が見つかりません ({control}) — スキップ")
        return 0

    text = control.read_text(encoding="utf-8", errors="surrogatepass")

    # is_orgos_dev: true はフレームワーク本体 → 対象外
    if re.search(r"^[ \t]*is_orgos_dev:[ \t]*true\b", text, re.M):
        say("set-project-name: is_orgos_dev=true（OrgOS 本体）のため project_name は変更しません")
        return 0

    target = args.name if args.name else root.name
    target = target.strip()
    if not target:
        say("set-project-name: フォルダ名が空のため変更しません")
        return 0

    m = LINE_RE.search(text)
    if m:
        current, comment = split_value_comment(m.group("rest"))
    else:
        current, comment = None, ""

    if current == target:
        say(f"set-project-name: project_name は既に \"{target}\" です（変更なし）")
        return 0

    is_placeholder = (current is None) or (current.strip().lower() in PLACEHOLDERS)
    if not is_placeholder and not args.force:
        say(f"set-project-name: project_name は既に \"{current}\" に設定済み（--force で上書き可）— 変更しません")
        return 0

    comment_suffix = f"  {comment}" if comment else ""
    if m:
        new_line = f'{m.group("indent")}project_name: "{target}"{comment_suffix}'
        new_text = text[:m.start()] + new_line + text[m.end():]
    else:
        new_text = f'project_name: "{target}"\n' + text

    if args.dry_run:
        say(f"[dry-run] project_name: {current!r} -> \"{target}\"")
        return 0

    control.write_text(new_text, encoding="utf-8", errors="surrogatepass")
    say(f"set-project-name: project_name を \"{target}\" に設定しました（旧: {current!r}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
