#!/bin/sh

set -u

force=0
write_control=1
control_path=".ai/CONTROL.yaml"
owner_inbox_path=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/platform/detect.sh [--force] [--no-write] [--control PATH] [--owner-inbox PATH]

Detects the current platform and prints one enum to stdout:
  macos | linux | windows-msys | windows-wsl | windows-native

Options:
  --force             overwrite an existing CONTROL.yaml platform value
  --no-write          only detect and log; do not modify CONTROL.yaml
  --control PATH      CONTROL.yaml path to update (default: .ai/CONTROL.yaml)
  --owner-inbox PATH  append Windows WSL guidance to OWNER_INBOX when Windows is detected
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      force=1
      ;;
    --no-write)
      write_control=0
      ;;
    --control)
      if [ "$#" -lt 2 ]; then
        echo "detect.sh: --control requires a path" >&2
        exit 2
      fi
      control_path=$2
      shift
      ;;
    --owner-inbox)
      if [ "$#" -lt 2 ]; then
        echo "detect.sh: --owner-inbox requires a path" >&2
        exit 2
      fi
      owner_inbox_path=$2
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "detect.sh: unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

detect_platform() {
  uname_s=$(uname -s 2>/dev/null || printf '%s' "")
  uname_r=$(uname -r 2>/dev/null || printf '%s' "")
  ostype=${OSTYPE-}

  case "$uname_s:$uname_r:$ostype" in
    *Microsoft*|*microsoft*|*WSL*|*wsl*)
      printf '%s\n' "windows-wsl"
      return
      ;;
  esac

  if [ -n "${WSL_DISTRO_NAME-}" ] || [ -n "${WSL_INTEROP-}" ]; then
    printf '%s\n' "windows-wsl"
    return
  fi

  case "$uname_s" in
    MINGW*|MSYS*|CYGWIN*)
      printf '%s\n' "windows-msys"
      return
      ;;
  esac

  case "$uname_s:$ostype" in
    Darwin:*)
      printf '%s\n' "macos"
      return
      ;;
    Linux:*)
      printf '%s\n' "linux"
      return
      ;;
    *:msys*|*:mingw*|*:cygwin*)
      printf '%s\n' "windows-msys"
      return
      ;;
  esac

  if [ "${OS-}" = "Windows_NT" ] || [ -n "${ComSpec-}" ] || [ -n "${SystemRoot-}" ]; then
    printf '%s\n' "windows-native"
    return
  fi

  printf '%s\n' "linux"
}

wsl_status() {
  if command -v wsl >/dev/null 2>&1; then
    if wsl --status >/dev/null 2>&1; then
      printf '%s\n' "available"
    else
      printf '%s\n' "unavailable"
    fi
  elif command -v wsl.exe >/dev/null 2>&1; then
    if wsl.exe --status >/dev/null 2>&1; then
      printf '%s\n' "available"
    else
      printf '%s\n' "unavailable"
    fi
  else
    printf '%s\n' "not-found"
  fi
}

warn_windows() {
  status=$1
  cat >&2 <<'GUIDE'
[!] Windows 環境を検出しました。Codex CLI の sandbox は WSL 経由を強く推奨します。

セットアップ手順:
1. wsl --install -d Ubuntu
2. WSL Ubuntu に Node.js 22 + Codex CLI をインストール
3. ~/.codex/auth.json を WSL に同期
4. 詳細: T-OS-WIN-3 で生成される codex-wsl.sh を参照
GUIDE
  echo "WSL status: $status" >&2
}

strip_yaml_value() {
  sed 's/[[:space:]]*#.*$//' \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//' \
    | sed 's/^"//' \
    | sed 's/"$//' \
    | sed "s/^'//" \
    | sed "s/'$//"
}

current_platform_value() {
  sed -n 's/^[[:space:]]*platform:[[:space:]]*//p' "$control_path" 2>/dev/null \
    | sed -n '1p' \
    | strip_yaml_value
}

update_control() {
  platform=$1

  if [ "$write_control" -ne 1 ]; then
    return 0
  fi

  if [ ! -f "$control_path" ]; then
    echo "detect.sh: CONTROL.yaml not found; platform not recorded: $control_path" >&2
    return 0
  fi

  existing=$(current_platform_value)
  if [ -n "$existing" ] && [ "$force" -ne 1 ]; then
    echo "detect.sh: platform already set to '$existing'; not overwriting (use --force to replace)" >&2
    return 0
  fi

  dir=$(dirname "$control_path")
  tmp="$dir/.platform-detect.$$"

  if grep -q '^[[:space:]]*platform:' "$control_path"; then
    awk -v value="$platform" '
      BEGIN { done = 0 }
      /^[[:space:]]*platform:/ && done == 0 {
        print "platform: \"" value "\""
        done = 1
        next
      }
      { print }
    ' "$control_path" > "$tmp"
  else
    awk -v value="$platform" '
      BEGIN { inserted = 0 }
      {
        print
        if (inserted == 0 && $0 ~ /^project_name:/) {
          print ""
          print "# プラットフォーム (detect.sh で自動設定、手動上書き可)"
          print "# enum: macos | linux | windows-msys | windows-wsl | windows-native"
          print "platform: \"" value "\""
          inserted = 1
        }
      }
      END {
        if (inserted == 0) {
          print ""
          print "# プラットフォーム (detect.sh で自動設定、手動上書き可)"
          print "# enum: macos | linux | windows-msys | windows-wsl | windows-native"
          print "platform: \"" value "\""
        }
      }
    ' "$control_path" > "$tmp"
  fi

  mv "$tmp" "$control_path"
}

append_owner_inbox_windows() {
  platform=$1

  case "$platform" in
    windows-*) ;;
    *) return 0 ;;
  esac

  if [ -z "$owner_inbox_path" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$owner_inbox_path")"
  touch "$owner_inbox_path"

  if grep -q '<!-- orgos:platform-windows-setup -->' "$owner_inbox_path"; then
    return 0
  fi

  cat >> "$owner_inbox_path" <<'INBOX'

<!-- orgos:platform-windows-setup -->
## Windows / WSL セットアップ案内

[!] Windows 環境を検出しました。Codex CLI の sandbox は WSL 経由を強く推奨します。

セットアップ手順:
1. wsl --install -d Ubuntu
2. WSL Ubuntu に Node.js 22 + Codex CLI をインストール
3. ~/.codex/auth.json を WSL に同期
4. 詳細: T-OS-WIN-3 で生成される codex-wsl.sh を参照
INBOX
}

write_audit_log() {
  platform=$1
  status=$2

  if [ ! -d ".ai" ]; then
    return 0
  fi

  mkdir -p ".ai/AUDIT"
  log_date=$(date '+%Y-%m-%d')
  timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
  uname_s=$(uname -s 2>/dev/null || printf '%s' "unknown")
  uname_r=$(uname -r 2>/dev/null || printf '%s' "unknown")

  {
    printf '%s platform=%s uname_s=%s uname_r=%s ostype=%s wsl_status=%s\n' \
      "$timestamp" "$platform" "$uname_s" "$uname_r" "${OSTYPE-}" "$status"
  } >> ".ai/AUDIT/platform-$log_date.log"
}

platform=$(detect_platform)
wsl_state="n/a"

case "$platform" in
  windows-*)
    wsl_state=$(wsl_status)
    warn_windows "$wsl_state"
    ;;
esac

update_control "$platform"
append_owner_inbox_windows "$platform"
write_audit_log "$platform" "$wsl_state"

printf '%s\n' "$platform"
