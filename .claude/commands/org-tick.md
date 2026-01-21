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

### 5. 状況診断とエージェント自動選択

状況を分析し、必要なエージェントを自動的に選択・実行する。

#### 5.1 診断チェック

以下の順序で状況をチェックし、該当するエージェントを起動:

| 優先度 | 状況 | 起動エージェント | 説明 |
|--------|------|------------------|------|
| **P0** | ビルドエラーがある | `org-build-fixer` | エラー修正が最優先 |
| **P0** | セキュリティアラートあり | `org-security-reviewer` | 脆弱性対応 |
| **P1** | 要件が不明確 | `org-planner` | タスク詳細化 |
| **P1** | 設計判断が必要 | `org-architect` | アーキテクチャ決定 |
| **P2** | 実装完了タスクあり（レビュー待ち） | `org-reviewer` + `org-security-reviewer` | 並列レビュー |
| **P2** | テストカバレッジ不足 | `org-tdd-coach` | テスト追加ガイド |
| **P2** | E2Eテスト対象あり | `org-e2e-runner` | E2Eテスト実行 |
| **P3** | 死コード検出 | `org-refactor-cleaner` | クリーンアップ |
| **P3** | ドキュメント乖離 | `org-doc-updater` | ドキュメント更新 |
| **P4** | レビュー承認済みタスクあり | `org-integrator` | main統合 |
| **常時** | Tick終了時 | `org-scribe` | 台帳記録 |

#### 5.2 診断の実行方法

```python
# 疑似コード
def diagnose_and_select_agents():
    agents_to_run = []

    # P0: 緊急対応
    if check_build_errors():
        agents_to_run.append("org-build-fixer")
        return agents_to_run  # ビルドエラーは最優先で修正

    if check_security_alerts():
        agents_to_run.append("org-security-reviewer")

    # P1: 計画フェーズ
    if stage in ["KICKOFF", "REQUIREMENTS", "DESIGN"]:
        if has_unclear_requirements():
            agents_to_run.append("org-planner")
        if needs_architecture_decision():
            agents_to_run.append("org-architect")

    # P2: 実装フェーズ
    if stage == "IMPLEMENTATION":
        if has_completed_tasks_awaiting_review():
            agents_to_run.extend(["org-reviewer", "org-security-reviewer"])
        if coverage_below_threshold():
            agents_to_run.append("org-tdd-coach")
        if has_e2e_test_targets():
            agents_to_run.append("org-e2e-runner")

    # P3: メンテナンス
    if detect_dead_code():
        agents_to_run.append("org-refactor-cleaner")
    if detect_doc_drift():
        agents_to_run.append("org-doc-updater")

    # P4: 統合
    if has_approved_tasks():
        agents_to_run.append("org-integrator")

    # 常時
    agents_to_run.append("org-scribe")

    return agents_to_run
```

#### 5.3 ビルドエラー検出

```bash
# TypeScript プロジェクト
npx tsc --noEmit 2>&1 | head -20

# Next.js
npm run build 2>&1 | head -20

# エラーがあれば org-build-fixer を起動
```

#### 5.4 カバレッジ検出

```bash
# カバレッジレポートを確認
npm test -- --coverage --coverageReporters=json-summary 2>/dev/null

# 80% 未満なら org-tdd-coach を起動
```

### 6. タスク委任

依存が解けた queued タスクを検出し、`runtime.max_parallel_tasks` 件まで自動的に委任する。

#### 6.1 実行可能タスクの検出

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

#### 6.2 owner_role による自動分岐

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

**Claude subagent タスク：**
- Task ツールで該当エージェントを起動
- 診断結果に基づいて自動選択（5.1 参照）

#### 6.3 Codex 実行の案内（auto_exec: false の場合）

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
```

実行後、再度 `/org-tick` で結果を回収します。
```

### 7. レビュー処理
- Implementer完了タスクは review へ移動
- Review Packet が `.ai/REVIEW/PACKETS/<TASK_ID>.md` にあることを確認
- org-reviewer + org-security-reviewer を並列で起動

### 8. 統合処理
レビュー承認済みタスクがあれば：
- org-integrator に統合を委任
- main反映は Owner Reviewポリシーに従う
- 統合完了後、worktree を削除

### 9. Worktree クリーンアップ
`done` になったタスクの worktree を削除：
```bash
git worktree remove .worktrees/<TASK_ID> --force
git branch -d task/<TASK_ID>-<slug>
```

### 10. 台帳更新（org-scribe）
- `DASHBOARD.md` と `RUN_LOG.md` と `STATUS.md` を更新
- CONTROL.yaml の runtime.tick_count を+1
- 学習抽出の提案（セッション終了時）

---

## 利用可能なエージェント一覧

| エージェント | 役割 | 自動起動条件 |
|--------------|------|--------------|
| `org-planner` | 要件分析、タスク分解 | 要件不明確時 |
| `org-architect` | システム設計、Contract定義 | 設計判断必要時 |
| `org-build-fixer` | ビルドエラー修正 | ビルドエラー検出時 |
| `org-refactor-cleaner` | 死コード削除、重複排除 | 死コード検出時 |
| `org-tdd-coach` | TDDガイド、カバレッジ監視 | カバレッジ不足時 |
| `org-reviewer` | 設計・品質レビュー | レビュー待ちタスクあり |
| `org-security-reviewer` | セキュリティレビュー | レビュー時 or アラート時 |
| `org-e2e-runner` | E2Eテスト実行 | E2Eテスト対象あり |
| `org-doc-updater` | ドキュメント自動更新 | ドキュメント乖離検出時 |
| `org-scribe` | 台帳記録 | 毎Tick |
| `org-integrator` | main統合 | 承認済みタスクあり |
| `org-os-maintainer` | OrgOS改善提案 | 定期的 |

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
- .claude/skills/*（該当するもの）
- .claude/rules/*（該当するもの）
```

---

## 原則

- **OrgOSが自動判断** - ユーザーは `/org-tick` を実行するだけ。エージェント選択も並列実行もOrgOSが行う
- **状況診断ベース** - 現在の状況を分析し、必要なエージェントを自動選択
- ブラックボックス化を避けるため、必ず差分要約と意図を台帳に残す
- 不確実性/判断はDECISIONSへ（B2はOwnerへ）
- **Codexは共有台帳を編集しない** - Managerだけが更新する
- Codex結果の回収は毎Tick冒頭で行う
