#!/usr/bin/env bash
# 統一エントリポイント

set -euo pipefail

run_codex() {
  if [ "${ORGOS_CODEX_WRAPPER_DRY_RUN:-}" = "1" ]; then
    printf 'platform=%s command=' "$platform"
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  exec "$@"
}

platform=$(bash scripts/platform/detect.sh --no-write)

case "$platform" in
  macos)
    run_codex /opt/homebrew/bin/codex "$@"
    ;;
  linux)
    run_codex codex "$@"
    ;;
  windows-wsl | windows-msys)
    run_codex bash .ai/_machine/codex/codex-wsl.sh "$@"
    ;;
  windows-native)
    printf '%s\n' "[WARN] WSL を推奨します。Windows native では read-only fallback になる可能性があります。" >&2
    run_codex codex "$@"
    ;;
  *)
    printf '[ERROR] unsupported platform: %s\n' "$platform" >&2
    exit 2
    ;;
esac
