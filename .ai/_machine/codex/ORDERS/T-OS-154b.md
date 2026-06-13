# Work Order: T-OS-154b

## Task
- ID: T-OS-154b
- Title: manager.md + CLAUDE.md に request-intake-loop 10 ステップ統合
- Role: implementer
- Priority: P0

## Allowed Paths
- `.claude/agents/manager.md` (編集 - **Owner 承認済み**)
- `CLAUDE.md` (編集 - **Owner 承認済み**)
- `.ai/BACKUPS/` (バックアップ保存)
- `.ai/CODEX/RESULTS/T-OS-154b.md`

## Owner Authorization
Owner 明示承認: `[A] 全部進める` (2026-04-19 朝)。

## Dependencies
- T-OS-154: done (.claude/rules/request-intake-loop.md 存在)

## Context

現在 `manager.md` の Tick フロー (Step 1-6) と `request-intake-loop.md` の 10 ステップは別物。
T-OS-154R で指摘された「Manager の自発的参照に委ねている」問題を解消する。

## Acceptance Criteria

### A1: 変更前のバックアップ
- `.claude/agents/manager.md` → `.ai/BACKUPS/manager.md.2026-04-19.bak`
- `CLAUDE.md` → `.ai/BACKUPS/CLAUDE.md.2026-04-19.bak`

### A2: manager.md の改訂
- 既存の「Tick フロー Step 1-6」を **request-intake-loop の Step 1-10 に対応させる** 形に書き換え
- Tick 先頭で以下を強制する旨を Iron Law として明記:
  1. `bash scripts/session/bootstrap.sh` (未実行なら実行)
  2. USER_PROFILE.yaml 参照 (Step 2)
  3. CAPABILITIES.yaml 参照 (Step 4)
  4. Work Graph bind (Step 3: TASKS / GOALS / DECISIONS)
  5. Request Intake Loop Step 1-10 を応答前に実施
- 旧 Step 1-6 を request-intake-loop の Step X の一部として再マッピング
- 既存の「エージェント起動テーブル」「並列タスク衝突防止」等は維持

### A3: CLAUDE.md の最小改訂
- 「守るべきこと」テーブルに `request-intake-loop.md` と `session-bootstrap.md` と `authority-layer.md` を最上位として追加
- 「最優先ルール」セクションの冒頭に以下を追加:
  ```
  **最高位 Iron Law**: 全依頼は .claude/rules/request-intake-loop.md の 10 ステップを適用する。例外なし。
  ```
- その他の記述は最小差分で維持

### A4: 参照整合性
- manager.md が request-intake-loop.md を明確に参照
- CLAUDE.md が新規 3 ルール (request-intake-loop, session-bootstrap, authority-layer) への参照を持つ
- 既存ルールへの参照を壊さない

### A5: 退行防止
- 既存の Codex 起動ロジック、ゴール管理、literacy adaptation 等は維持
- manager.md の詳細指示は保持しつつ、ループ構造のみを書き換え

### A6: 検証
- Manager Quality Eval 再実行 (19/20 以上を維持)
- Regression report で退行なし確認

### A7: 変更 diff を RESULT に記録
- 何を追加、何を削除、何を書き換えたかを明示

### A8: rollback 手順
- バックアップから復元するコマンド例を RESULT に記述

## Instructions

1. 現 manager.md と CLAUDE.md を読む
2. バックアップ保存
3. request-intake-loop.md と整合する形に改訂
4. 最小差分で他記述は維持
5. 検証

## Report

`.ai/CODEX/RESULTS/T-OS-154b.md`:
1. 変更前後の diff (または変更箇所の要約)
2. バックアップ場所
3. eval 結果 (退行なし確認)
4. rollback 手順
5. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED
