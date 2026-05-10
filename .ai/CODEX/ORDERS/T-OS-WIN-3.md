# Work Order: T-OS-WIN-3 (Issue #4 Phase β 完遂)

## Task
- ID: T-OS-WIN-3
- Title: WSL ラッパースクリプトテンプレート提供
- Role: implementer
- Priority: P2

## Allowed Paths
- `.ai/CODEX/codex-wsl.sh` (新規)
- `.ai/TEMPLATES/codex-wsl.sh` (新規)
- `scripts/platform/codex-wrapper.sh` (新規)
- `.ai/CODEX/RESULTS/T-OS-WIN-3.md`

## Reference
- Issue #4: https://github.com/Yokotani-Dev/OrgOS/issues/4
- T-OS-WIN-1 成果物: scripts/platform/detect.sh
- T-OS-WIN-2 成果物: agent-coordination.md にプラットフォーム分岐記載済み

## Dependencies
- T-OS-WIN-2: done

## Context

Windows-WSL で Codex CLI を呼ぶときの統一ラッパー。
- 引数の安全な転送 (printf %q quote、eval 禁止)
- Windows パス → /mnt/c/... 自動変換
- ~/.codex/auth.json の Windows ↔ WSL 同期チェック

## Acceptance Criteria

### A1: .ai/CODEX/codex-wsl.sh 実装
```bash
#!/usr/bin/env bash
# WSL 経由で codex exec を呼ぶラッパー
# 使い方: bash .ai/CODEX/codex-wsl.sh exec --full-auto ...

set -euo pipefail

# 1. Windows パス検出 + /mnt/c/... 変換
# 2. 引数を printf %q で安全に quote
# 3. wsl -d Ubuntu -- bash -c '...' で実行
# 4. eval 使用禁止 (シェルインジェクション対策)
```

シェルインジェクション対策の具体例:
```bash
# OK
quoted_args=""
for arg in "$@"; do
  quoted_args+="$(printf %q "$arg") "
done
wsl -d Ubuntu -- bash -c "cd '$wsl_path' && codex $quoted_args"

# NG (eval は禁止)
# eval wsl -d Ubuntu -- bash -c "..."
```

### A2: Windows パス → /mnt/c/... 変換
- `C:\Users\foo` → `/mnt/c/Users/foo`
- `C:/Users/foo` (slash 形式) も対応
- 相対パスはそのまま転送

### A3: auth.json 同期チェック
- Windows 側 `~/.codex/auth.json` の mtime 取得
- WSL 側 `~/.codex/auth.json` の mtime 取得 (wsl 内で stat)
- Windows 側が新しい → WSL に copy 提案 (warning 出力)
- WSL 側が新しい or 同じ → そのまま実行

### A4: TEMPLATES/codex-wsl.sh 配布
- /org-import で展開される雛形として `.ai/TEMPLATES/codex-wsl.sh` も用意
- 中身は同一 (将来 customize 可能性のため別保管)

### A5: scripts/platform/codex-wrapper.sh 共通化
- detect.sh 結果に応じて codex 実行を分岐する高位ラッパー
- macos/linux: 直接 codex 実行
- windows-wsl: codex-wsl.sh 経由
- windows-native: read-only fallback warning

```bash
#!/usr/bin/env bash
# 統一エントリポイント
platform=$(bash scripts/platform/detect.sh)
case "$platform" in
  macos)        /opt/homebrew/bin/codex "$@" ;;
  linux)        codex "$@" ;;
  windows-wsl)  bash .ai/CODEX/codex-wsl.sh "$@" ;;
  windows-native) echo "[WARN] WSL を推奨" >&2; codex "$@" ;;
esac
```

### A6: ShellCheck パス
- `shellcheck .ai/CODEX/codex-wsl.sh scripts/platform/codex-wrapper.sh` がエラーなし
- warning は許容 (info level)

### A7: 簡易 e2e テスト
特殊文字を含む引数で壊れないか:
```bash
# Test cases (実行はせず、構文確認のみで OK):
# - スペース含む: "Hello World"
# - シングルクォート: "It's a test"
# - ドルマーク: '$HOME'
# - 改行 (literal): "$'line1\nline2'"
```

### A8: 検証
- macOS で codex-wrapper.sh が macos branch に行くこと
- (Windows 環境がなければ実測テストは skip OK)
- bash -n で構文 check

## Instructions

1. T-OS-WIN-1 の detect.sh と T-OS-WIN-2 の規約を参照
2. A1-A8 を実装 (新規 3 ファイル)
3. シェルインジェクション対策を厳格に (printf %q + eval 禁止)
4. **重要**: 既存 OS 中核編集禁止

## Report

`.ai/CODEX/RESULTS/T-OS-WIN-3.md`:
1. 変更ファイル一覧
2. A1-A8 対応表
3. ShellCheck 結果
4. 構文 check (bash -n) 結果
5. ステータス

## Handoff Packet (必須)
schema 準拠で返却。
