# Codex Worker Integration

このディレクトリはCodex workerとの連携に使用する。

## ディレクトリ構成

```
.ai/CODEX/
  ORDERS/       # Manager が生成する Work Order
  RESULTS/      # Codex が出力する実行結果
  LOGS/         # Codex 実行ログ（オプション）
```

## フロー

1. Manager が `/org-tick` でタスクを `codex-implementer` / `codex-reviewer` に委任
2. Manager が `.ai/CODEX/ORDERS/<TASK_ID>.md` に Work Order を生成
3. Codex を実行（手動 or `codex exec`）
4. Codex が `.ai/CODEX/RESULTS/<TASK_ID>.json` に結果を出力
5. Manager が結果を読み取り、`.ai/TASKS.yaml` を更新

## Work Order フォーマット

```markdown
# Work Order: <TASK_ID>

## Task
- ID: T-XXX
- Title: タスクタイトル
- Role: implementer | reviewer

## Allowed Paths
- src/
- tests/

## Acceptance Criteria
- [ ] 基準1
- [ ] 基準2

## Dependencies
- T-YYY (completed)

## Instructions
追加の指示があればここに記載

## Reference
- 関連ドキュメントへのパス
```

## 結果ファイル

詳細は `AGENTS.md` を参照。
