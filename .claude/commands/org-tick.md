---
description: OrgOSの進行を1Tick進める（台帳更新→タスク分配→レビュー→次の手）
---

OrgOS ManagerとしてTickを1回実行する。

## 手順

### 1. 状態集約
`.ai/CONTROL.yaml` / `.ai/TASKS.yaml` / `.ai/OWNER_COMMENTS.md` / `.ai/OWNER_INBOX.md` / `.ai/STATUS.md` / `.ai/DASHBOARD.md` を読み、状態を集約

### 2. Ownerコメント処理
Ownerコメントがあれば、DECISIONS/TASKS/PROJECT/CONTROLへ反映し、処理済みをOWNER_COMMENTSに明記

### 3. Owner待ちチェック
awaiting_owner=true なら、進行を止め、DASHBOARDを更新して終了

### 4. Codex結果の回収
`.ai/CODEX/RESULTS/` に新しい結果ファイルがあれば：
- 結果を読み取り、タスクステータスを更新
- `completed` → review へ移動（implementer）、または done へ移動（reviewer approved）
- `blocked` / `failed` → blocked へ移動し、理由を記録
- `changes_requested` → running へ戻し、修正タスクとして再委任
- 完了したタスクの worktree をクリーンアップ対象としてマーク

### 5. タスク委任（自動判断）

依存が解けた queued タスクを検出し、`runtime.max_parallel_tasks` 件まで自動的に委任する。

#### 5.1 実行可能タスクの検出

```python
# 疑似コード
executable = []
for task in tasks:
    if task.status == "queued":
        if all(get_task(dep).status == "done" for dep in task.deps):
            executable.append(task)

# 現在 running のタスク数を考慮
slots = max_parallel_tasks - count(running_tasks)
to_run = executable[:slots]
```

#### 5.2 owner_role による自動分岐

**Codex タスク（`codex-implementer` / `codex-reviewer`）：**

複数タスクがあれば **並列実行** を自動で準備：

1. 各タスクの Worktree を作成
   ```bash
   git worktree add .worktrees/<TASK_ID> -b task/<TASK_ID>-<slug>
   ```

2. Work Order を生成（`.ai/CODEX/ORDERS/<TASK_ID>.md`）

3. 実行方法を決定：
   - **`codex.auto_exec: true`** → バックグラウンドで自動実行
   - **`codex.auto_exec: false`（デフォルト）** → Ownerに実行コマンドを提示

**Claude subagent タスク（`org-planner` / `org-architect` / `org-integrator` / `org-scribe`）：**
- 1件ずつ順序実行（Claude SDK の制限）
- Task ツールで該当エージェントを起動

#### 5.3 Codex 実行の案内（auto_exec: false の場合）

Ownerに以下を表示：

```markdown
## Codex タスク実行

以下のタスクが実行可能です：

| ID | Title | Worktree |
|----|-------|----------|
| T-003 | ユーザー認証モジュール | .worktrees/T-003 |
| T-004 | 商品カタログAPI | .worktrees/T-004 |

**実行コマンド：**
```bash
# 並列実行（推奨）
./.claude/scripts/run-parallel.sh T-003 T-004

# または個別実行
cd .worktrees/T-003 && codex exec "AGENTS.md を読み、../.ai/CODEX/ORDERS/T-003.md に従って実行"
cd .worktrees/T-004 && codex exec "AGENTS.md を読み、../.ai/CODEX/ORDERS/T-004.md に従って実行"
```

実行後、再度 `/org-tick` で結果を回収します。
```

### 6. レビュー処理
- Implementer完了タスクは review へ移動
- Review Packet が `.ai/REVIEW/PACKETS/<TASK_ID>.md` にあることを確認
- codex-reviewer に委任する場合は Work Order を生成

### 7. 統合処理
レビュー承認済みタスクがあれば：
- org-integrator に統合を委任
- main反映は Owner Reviewポリシーに従う
- 統合完了後、worktree を削除

### 8. Worktree クリーンアップ
`done` になったタスクの worktree を削除：
```bash
git worktree remove .worktrees/<TASK_ID> --force
git branch -d task/<TASK_ID>-<slug>
```

### 9. 台帳更新
`DASHBOARD.md` と `RUN_LOG.md` と `STATUS.md` を更新し、CONTROL.yaml の runtime.tick_count を+1する

---

## Work Order テンプレート

```markdown
# Work Order: <TASK_ID>

## Task
- ID: <TASK_ID>
- Title: <タスクタイトル>
- Role: implementer | reviewer

## Allowed Paths
<allowed_paths から展開>

## Acceptance Criteria
<acceptance から展開>

## Dependencies
<完了した依存タスクを列挙>

## Instructions
<追加の指示>

## Reference
- AGENTS.md（必読）
- .ai/PROJECT.md
- .ai/GIT_WORKFLOW.md
```

---

## 原則

- **OrgOSが自動判断** - ユーザーは `/org-tick` を実行するだけ。並列実行の判断はOrgOSが行う
- ブラックボックス化を避けるため、必ず差分要約と意図を台帳に残す
- 不確実性/判断はDECISIONSへ（B2はOwnerへ）
- **Codexは共有台帳を編集しない** - Managerだけが更新する
- Codex結果の回収は毎Tick冒頭で行う
