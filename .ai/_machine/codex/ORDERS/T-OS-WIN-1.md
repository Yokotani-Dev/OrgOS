# Work Order: T-OS-WIN-1 (Issue #4)

## Task
- ID: T-OS-WIN-1
- Title: プラットフォーム検出 + CONTROL.yaml への記録
- Role: implementer
- Priority: P1

## Allowed Paths
- `scripts/platform/` (新規ディレクトリ)
- `.claude/commands/org-start.md` (編集)
- `.claude/commands/org-import.md` (編集)
- `.ai/CONTROL.example.yaml` (編集 - 存在しない場合は新規)
- `.ai/CODEX/RESULTS/T-OS-WIN-1.md`

## Reference
- GitHub Issue #4: https://github.com/Yokotani-Dev/OrgOS/issues/4
- 上流問題: openai/codex#15850, #17179, #18821 (Windows sandbox 未解決)

## Context

Windows 環境で Codex CLI の `workspace-write` / `full-auto` sandbox が動作しない。Manager が代行する「意図しないフォールバック」を防ぐため、プラットフォーム検出を OS レベルで標準化する。

## Acceptance Criteria

### A1: scripts/platform/detect.sh 実装
- uname / `$OSTYPE` / Windows 環境変数で判定
- 出力 enum: `macos` | `linux` | `windows-msys` | `windows-wsl` | `windows-native`
- Windows 検出時は `wsl --status` (Git Bash 等) で WSL 有無確認
- 推奨セットアップ手順を stderr に出力

```bash
scripts/platform/detect.sh
# 出力例: "macos" or "windows-wsl" 等
```

### A2: /org-start 起動時にプラットフォーム検出
`.claude/commands/org-start.md` のフローに追加:
- 起動時 detect.sh を呼ぶ
- 結果を CONTROL.yaml の `platform` フィールドに記録 (上書き禁止: 既設定なら警告のみ)
- Windows 検出時は WSL セットアップ案内を OWNER_INBOX に追記

### A3: /org-import 起動時にプラットフォーム検出
`.claude/commands/org-import.md` も同様に detect.sh を呼ぶ。
新規プロジェクト初期化時に platform を確定する。

### A4: CONTROL.example.yaml に platform フィールド追加
```yaml
# プラットフォーム (detect.sh で自動設定、手動上書き可)
# enum: macos | linux | windows-wsl | windows-native
platform: ""  # detect.sh 実行時に自動入力
```

### A5: detect.sh の冪等性
- 既に platform が設定済みなら上書きせず警告 only
- `--force` オプションで上書き許可
- 出力は決定的 (同一環境で常に同じ結果)

### A6: Windows 推奨セットアップガイド
detect.sh が Windows 検出時に表示する内容:
```
[!] Windows 環境を検出しました。Codex CLI の sandbox は WSL 経由を強く推奨します。

セットアップ手順:
1. wsl --install -d Ubuntu
2. WSL Ubuntu に Node.js 22 + Codex CLI をインストール
3. ~/.codex/auth.json を WSL に同期
4. 詳細: T-OS-WIN-3 で生成される codex-wsl.sh を参照
```

### A7: 検証
- macOS で実行 → `macos` 出力
- (もし可能なら) WSL で実行確認
- 冪等性確認 (2 回実行で diff なし)

### A8: ログ
- detect 結果を `.ai/AUDIT/platform-YYYY-MM-DD.log` に記録 (gitignored)

## Instructions

1. Issue #4 本文 (TASKS.yaml notes) を確認
2. scripts/platform/detect.sh をシェルで実装 (依存最小、posix sh 互換推奨)
3. /org-start と /org-import への組み込みは「手順追加」のみ (大規模改修禁止)
4. CONTROL.example.yaml は schema 例として参考用 (本物の CONTROL.yaml は触らない)
5. **重要**: .ai/DECISIONS.md, .ai/TASKS.yaml, .ai/CONTROL.yaml (実体), CLAUDE.md, manager.md 編集禁止

## Report

`.ai/CODEX/RESULTS/T-OS-WIN-1.md`:
1. 変更ファイル一覧
2. A1-A8 対応表
3. detect.sh 実行サンプル (macOS で 1 回)
4. T-OS-WIN-2 への示唆
5. ステータス

## Handoff Packet (必須)
schema 準拠の packet を返却。
