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

### 5. タスク委任
依存が解けた queued タスクを最大 `runtime.max_parallel_tasks` 件まで running にする。

#### owner_role による委任先の分岐

**`codex-implementer` / `codex-reviewer` の場合：**
1. Work Order を `.ai/CODEX/ORDERS/<TASK_ID>.md` に生成
2. 以下のいずれかを実行：
   - **自動実行（CONTROL.yaml で codex_auto_exec: true の場合）**：
     ```bash
     codex exec --approval-mode full-auto "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"
     ```
   - **手動実行待ち（デフォルト）**：
     タスクを `running` にし、DASHBOARDに「Codex実行待ち」と記載。
     Ownerが以下を実行：
     ```bash
     codex exec "AGENTS.md を読み、.ai/CODEX/ORDERS/<TASK_ID>.md の指示に従って実行せよ"
     ```

**`org-planner` / `org-architect` / `org-integrator` / `org-scribe` の場合：**
- 従来通り Claude subagent へ委任

### 6. レビュー処理
- Implementer完了タスクは review へ移動
- Review Packet が `.ai/REVIEW/PACKETS/<TASK_ID>.md` にあることを確認
- codex-reviewer に委任する場合は Work Order を生成

### 7. 統合委任
統合準備が整ったら org-integrator へ委任（main反映はOwner Reviewポリシーに従う）

### 8. 台帳更新
`DASHBOARD.md` と `RUN_LOG.md` と `STATUS.md` を更新し、CONTROL.yaml の runtime.tick_count を+1する

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

## 原則
- ブラックボックス化を避けるため、必ず差分要約と意図を台帳に残す
- 不確実性/判断はDECISIONSへ（B2はOwnerへ）
- **Codexは共有台帳を編集しない** - Managerだけが更新する
- Codex結果の回収は毎Tick冒頭で行う
