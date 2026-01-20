---
description: 統合担当がマージ順制御してmainへ統合（ゲート遵守）
---

Integratorとして以下を行う：

## 対象タスク
- status が `review` で、レビューが approved のタスクのみ

## 統合手順

### 1. マージ順序の決定
- クリティカルパス優先
- 依存関係を考慮（deps の少ないタスクから）
- 競合リスクの低いタスクから

### 2. マージ実行
```bash
# タスクブランチをmainにsquash merge
git checkout main
git merge --squash task/<TASK_ID>-<slug>
git commit -m "feat(<scope>): <title> [<TASK_ID>]"
```

### 3. Worktree クリーンアップ
マージ完了後、対応するworktreeを削除：
```bash
# 個別削除
git worktree remove .worktrees/<TASK_ID> --force

# スクリプトでの削除も可能
# ./.claude/scripts/run-parallel.sh --cleanup <TASK_ID>
```

### 4. ブランチ削除
```bash
git branch -d task/<TASK_ID>-<slug>
```

### 5. タスク状態更新
- TASKS.yaml で status を `done` に更新
- DASHBOARD.md を更新

## ゲート確認
- mainへのpushは CONTROL.yaml の `allow_push_main: true` が必要
- main統合前に Owner Reviewポリシー（`always_before_merge_to_main` 等）を確認
- 必要なら `awaiting_owner: true` にして止める

## 一括クリーンアップ
完了したタスクのworktreeを一括削除：
```bash
# 個別に削除
for task_id in T-003 T-004 T-005; do
  git worktree remove .worktrees/$task_id --force
  git branch -d task/$task_id
done
```

## 注意事項
- squash merge を推奨（1タスク=1コミット）
- revert が必要な場合は `git revert <squash_commit>`
- push は Integrator のみが実行（CONTROL.yaml で制御）
