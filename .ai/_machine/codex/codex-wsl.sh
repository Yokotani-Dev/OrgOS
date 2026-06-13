#!/usr/bin/env bash
# WSL 経由で codex exec を呼ぶラッパー
# 使い方: bash .ai/CODEX/codex-wsl.sh exec --full-auto ...

set -euo pipefail

WSL_DISTRO=${ORGOS_WSL_DISTRO:-Ubuntu}
WINDOWS_AUTH_PATH=${CODEX_WINDOWS_AUTH:-"$HOME/.codex/auth.json"}

find_wsl() {
  if command -v wsl >/dev/null 2>&1; then
    printf '%s\n' "wsl"
    return 0
  fi

  if command -v wsl.exe >/dev/null 2>&1; then
    printf '%s\n' "wsl.exe"
    return 0
  fi

  return 1
}

mtime_or_zero() {
  local path=$1

  if [ ! -f "$path" ]; then
    printf '%s\n' "0"
    return 0
  fi

  if stat -c %Y "$path" >/dev/null 2>&1; then
    stat -c %Y "$path"
    return 0
  fi

  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
    return 0
  fi

  printf '%s\n' "0"
}

lower_drive() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

windows_path_to_wsl() {
  local path=$1
  local drive
  local rest

  case "$path" in
    [A-Za-z]: | [A-Za-z]:\\* | [A-Za-z]:/*)
      drive=$(lower_drive "${path:0:1}")
      rest=${path:2}
      rest=${rest//\\//}
      while [[ "$rest" == /* ]]; do
        rest=${rest#/}
      done
      if [ -n "$rest" ]; then
        printf '/mnt/%s/%s\n' "$drive" "$rest"
      else
        printf '/mnt/%s\n' "$drive"
      fi
      ;;
    /[A-Za-z]/*)
      drive=$(lower_drive "${path:1:1}")
      rest=${path:3}
      rest=${rest//\\//}
      printf '/mnt/%s/%s\n' "$drive" "$rest"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

wsl_auth_mtime() {
  local wsl_bin=$1

  MSYS2_ARG_CONV_EXCL='*' "$wsl_bin" -d "$WSL_DISTRO" -- bash -c \
    'auth="$HOME/.codex/auth.json"; if [ -f "$auth" ]; then stat -c %Y "$auth"; else printf "%s\n" "0"; fi' \
    2>/dev/null || printf '%s\n' "0"
}

warn_auth_sync_if_needed() {
  local wsl_bin=$1
  local windows_mtime
  local remote_mtime
  local windows_auth_wsl
  local quoted_auth

  windows_mtime=$(mtime_or_zero "$WINDOWS_AUTH_PATH")
  remote_mtime=$(wsl_auth_mtime "$wsl_bin")

  if ! [[ "$windows_mtime" =~ ^[0-9]+$ ]]; then
    windows_mtime=0
  fi
  if ! [[ "$remote_mtime" =~ ^[0-9]+$ ]]; then
    remote_mtime=0
  fi

  if [ "$windows_mtime" -gt 0 ] && [ "$windows_mtime" -gt "$remote_mtime" ]; then
    windows_auth_wsl=$(windows_path_to_wsl "$WINDOWS_AUTH_PATH")
    quoted_auth=$(printf '%q' "$windows_auth_wsl")
    {
      printf '%s\n' "[WARN] Windows ~/.codex/auth.json is newer than WSL ~/.codex/auth.json."
      printf '%s\n' "[WARN] If Codex authentication fails, sync it into WSL first:"
      printf '       %s -d %s -- bash -c %q\n' \
        "$wsl_bin" "$WSL_DISTRO" "mkdir -p ~/.codex && cp $quoted_auth ~/.codex/auth.json"
    } >&2
  fi
}

main() {
  local wsl_bin
  local wsl_cwd
  local quoted_cwd
  local command
  local arg
  local converted_arg
  local quoted_arg

  if ! wsl_bin=$(find_wsl); then
    printf '%s\n' "[ERROR] wsl command not found. Install WSL Ubuntu first." >&2
    exit 127
  fi

  warn_auth_sync_if_needed "$wsl_bin"

  wsl_cwd=$(windows_path_to_wsl "$PWD")
  quoted_cwd=$(printf '%q' "$wsl_cwd")
  command="cd $quoted_cwd && exec codex"

  for arg in "$@"; do
    converted_arg=$(windows_path_to_wsl "$arg")
    quoted_arg=$(printf '%q' "$converted_arg")
    command+=" $quoted_arg"
  done

  MSYS2_ARG_CONV_EXCL='*' exec "$wsl_bin" -d "$WSL_DISTRO" -- bash -c "$command"
}

main "$@"
