#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/rollback.sh --target TARGET --backup BACKUP
USAGE
  exit 2
}

target=""
backup=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || usage
      target="$2"
      shift 2
      ;;
    --backup)
      [[ $# -ge 2 ]] || usage
      backup="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$target" ]] || usage
[[ -n "$backup" ]] || usage

target="$(repo_relpath "$target")"
backup="$(repo_relpath "$backup")"
[[ -e "$REPO_ROOT/$backup" ]] || die "backup does not exist: $backup"

pre_restore_backup=""
if [[ -e "$REPO_ROOT/$target" ]]; then
  pre_restore_backup="$("$SCRIPT_DIR/backup.sh" --target "$target" | jq -r '.backup')"
fi

mkdir -p "$REPO_ROOT/$(dirname "$target")"
case "$backup" in
  *.tar.gz)
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    tar -xzf "$REPO_ROOT/$backup" -C "$tmp_dir"
    restored_file="$(find "$tmp_dir" -type f | head -n 1)"
    [[ -n "$restored_file" ]] || die "tar.gz backup did not contain a file"
    cp "$restored_file" "$REPO_ROOT/$target"
    ;;
  *)
    cp "$REPO_ROOT/$backup" "$REPO_ROOT/$target"
    ;;
esac

jq -n \
  --arg target "$target" \
  --arg backup "$backup" \
  --arg pre_restore_backup "$pre_restore_backup" \
  '{target: $target, restored_from: $backup, pre_restore_backup: $pre_restore_backup}'
