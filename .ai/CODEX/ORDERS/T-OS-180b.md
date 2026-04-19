# Work Order: T-OS-180b

## Task
- ID: T-OS-180b
- Title: SessionStart hook に session/bootstrap.sh を統合 (単発チャット問題の最終解決)
- Role: implementer
- Priority: P0

## Allowed Paths
- `.claude/settings.json` (編集 - **Owner 承認済み**)
- `.ai/CODEX/RESULTS/T-OS-180b.md`

## Owner Authorization
Owner 明示承認: `[A] 全部進める` (2026-04-19 朝)。
authority-layer.md の `allow_os_mutation=true` + `edit_existing_settings_json` の明示承認。

## Dependencies
- T-OS-180: done (scripts/session/bootstrap.sh 実装済み)

## Context

現 `.claude/settings.json` の SessionStart hook は `.ai/DASHBOARD.md`, `.ai/OWNER_INBOX.md`, `.ai/CONTROL.yaml` の 3 ファイルを cat するだけ。
本タスクで bootstrap.sh を追加し、新規セッションで **自動的に OrgOS モードへ突入** する。

## Acceptance Criteria

### A1: settings.json の現状確認
- 既存 SessionStart hook の構造を読む (壊さない)
- 既存の cat コマンドはそのまま残す

### A2: bootstrap.sh の呼び出し追加
SessionStart hook の末尾に以下を追加:
```json
{
  "type": "command",
  "command": "bash scripts/session/bootstrap.sh 2>/dev/null || echo 'bootstrap skipped'"
}
```
graceful: bootstrap 失敗してもセッションは継続する。

### A3: 最小差分
- 既存の他設定 (permissions, env 等) は変更しない
- 追加は hooks 配列の該当イベントのみ

### A4: 検証
- jq で settings.json が valid JSON であること確認
- `cat .claude/settings.json | jq '.hooks.SessionStart'` で追加された確認

### A5: 失敗時の復旧性
- 変更前の内容を `.ai/BACKUPS/settings.json.2026-04-19.bak` に保存
- rollback 手順を RESULT に記述

### A6: 動作確認 (シミュレート)
実際のセッション再起動はできないので、hook コマンドを手動実行して動くか確認:
```bash
bash scripts/session/bootstrap.sh
```

## Instructions

1. 現 settings.json を読む
2. バックアップ保存
3. hooks.SessionStart に bootstrap.sh 呼び出しを追加
4. JSON validity 確認
5. bootstrap.sh 手動実行で動作確認

## Report

1. 変更前後の diff
2. バックアップ場所
3. rollback 手順
4. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED
