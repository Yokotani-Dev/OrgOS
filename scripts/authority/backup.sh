#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/authority/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'USAGE'
usage: scripts/authority/backup.sh --target TARGET [--tar-gz]
USAGE
  exit 2
}

target=""
tar_gz=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || usage
      target="$2"
      shift 2
      ;;
    --tar-gz)
      tar_gz=true
      shift
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
target="$(repo_relpath "$target")"
[[ -e "$REPO_ROOT/$target" ]] || die "target does not exist: $target"

backup_dir="$REPO_ROOT/.ai/BACKUPS/$(date +%F)"
mkdir -p "$backup_dir"

safe_name="$(basename "$target").bak"
backup_path="$backup_dir/$safe_name"
cp "$REPO_ROOT/$target" "$backup_path"

if [[ "$tar_gz" == true ]]; then
  tar_path="$backup_path.tar.gz"
  tar -czf "$tar_path" -C "$backup_dir" "$(basename "$backup_path")"
  rm -f "$backup_path"
  backup_path="$tar_path"
fi

jq -n \
  --arg target "$target" \
  --arg backup "$(repo_relpath "$backup_path")" \
  '{target: $target, backup: $backup}'
