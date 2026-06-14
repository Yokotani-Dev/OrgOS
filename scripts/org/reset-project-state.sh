#!/usr/bin/env bash
#
# reset-project-state.sh — OrgOS sanctioned tool
#
# 新規プロジェクト（クローン）に紛れ込んだ OrgOS 開発専用の実行時状態
# (.ai/_machine 配下の events/codex/sessions/evolution 等) を退避し、
# OS が必要とする空のディレクトリ骨格を再作成する。
#
# 安全設計:
#   - is_orgos_dev: true（OrgOS 本体）では絶対に実行しない（自己状態の消去防止）。
#   - 既定は「退避」: 既存内容を ~/.orgos/import-backups/<repo>-<ts>/ へ move してから骨格再作成。
#     --no-backup で退避せず削除。--dry-run で計画のみ。
#   - 冪等: 既に空骨格なら no-op。
#
# Usage:
#   reset-project-state.sh [--repo-root PATH] [--no-backup] [--dry-run] [--quiet] [--force]
set -euo pipefail

REPO_ROOT=""
NO_BACKUP=0
DRY_RUN=0
QUIET=0
FORCE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
CONTROL="$REPO_ROOT/.ai/CONTROL.yaml"
MACHINE="$REPO_ROOT/.ai/_machine"

# OrgOS 本体は対象外（--force でも保護）
if [ -f "$CONTROL" ] && grep -Eq '^[[:space:]]*is_orgos_dev:[[:space:]]*true\b' "$CONTROL"; then
  say "reset-project-state: is_orgos_dev=true（OrgOS 本体）のため実行しません"
  exit 0
fi

# OS が必要とする骨格ディレクトリ
SKELETON="codex codex/ORDERS codex/RESULTS events leases queue sessions evolution evolution/proposals metrics review scheduler scheduler/runs intelligence artifacts integrity approvals backups learnings os supervisor-review"

# 退避対象 = _machine 直下で骨格に含まれ、かつ中身があるもの（README/.gitkeep は残す）
has_content=0
if [ -d "$MACHINE" ]; then
  # .gitkeep / README.md 以外のファイルが1つでもあれば退避対象
  if find "$MACHINE" -type f ! -name '.gitkeep' ! -name 'README.md' -print -quit 2>/dev/null | grep -q .; then
    has_content=1
  fi
fi

if [ "$has_content" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
  # 骨格だけ確実に用意して終了
  if [ "$DRY_RUN" -eq 0 ]; then
    for d in $SKELETON; do mkdir -p "$MACHINE/$d"; [ -e "$MACHINE/$d/.gitkeep" ] || : > "$MACHINE/$d/.gitkeep"; done
  fi
  say "reset-project-state: 既にクリーン（骨格のみ）。新プロジェクトとして利用可"
  exit 0
fi

# 退避先（リポジトリ外・~/.orgos 配下。ORGOS_ACTIVITY_DIR と同根の管理領域）
STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo manual)"
REPO_NAME="$(basename "$REPO_ROOT")"
BACKUP_DIR="${HOME}/.orgos/import-backups/${REPO_NAME}-${STAMP}"

if [ "$DRY_RUN" -eq 1 ]; then
  say "[dry-run] 退避対象: $MACHINE の dev 状態"
  [ "$NO_BACKUP" -eq 1 ] && say "[dry-run] --no-backup: 退避せず削除予定" || say "[dry-run] 退避先: $BACKUP_DIR"
  say "[dry-run] 骨格を再作成: $SKELETON"
  exit 0
fi

# 退避 or 削除
if [ "$NO_BACKUP" -eq 1 ]; then
  find "$MACHINE" -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec rm -rf {} +
  say "reset-project-state: _machine の dev 状態を削除しました（--no-backup）"
else
  mkdir -p "$BACKUP_DIR"
  # README.md は残し、それ以外を退避
  find "$MACHINE" -mindepth 1 -maxdepth 1 ! -name 'README.md' -exec mv {} "$BACKUP_DIR/" \; 2>/dev/null || true
  say "reset-project-state: _machine の dev 状態を退避しました → $BACKUP_DIR"
fi

# 骨格再作成
for d in $SKELETON; do mkdir -p "$MACHINE/$d"; [ -e "$MACHINE/$d/.gitkeep" ] || : > "$MACHINE/$d/.gitkeep"; done
say "reset-project-state: 空の骨格を再作成しました。新プロジェクトとして利用可"
exit 0
