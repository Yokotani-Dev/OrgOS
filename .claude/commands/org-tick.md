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

### 5. セッション管理チェック

コンテキスト使用率と作業の論理的区切りをチェックし、セッション終了を提案すべきか判断する。

#### 5.1 セッション終了提案の判定

```python
# 疑似コード
def should_suggest_session_end(context):
    """
    セッション終了を提案すべきか判定

    Returns:
        {
            "suggest": bool,
            "priority": "P0" | "P1" | "P2",
            "reason": str,
            "force": bool  # True なら選択肢を出さず強制終了
        }
    """

    # P0: 必ず提案（論理的な区切り）
    if context.stage_transitioned:
        return {
            "suggest": True,
            "priority": "P0",
            "reason": f"ゲート通過（{context.prev_stage} → {context.current_stage}）",
            "force": False
        }

    if context.feature_completed and context.review_passed:
        return {
            "suggest": True,
            "priority": "P0",
            "reason": "機能実装・レビュー完了",
            "force": False
        }

    if context.integration_completed:
        return {
            "suggest": True,
            "priority": "P0",
            "reason": "統合完了（ブランチマージ済み）",
            "force": False
        }

    # P1: 推奨（タスクグループ完了）
    if context.task_group_completed:
        return {
            "suggest": True,
            "priority": "P1",
            "reason": f"{context.completed_task_count} 個のタスクグループが完了",
            "force": False
        }

    if context.major_decision_made:
        return {
            "suggest": True,
            "priority": "P1",
            "reason": "大きな設計判断が完了",
            "force": False
        }

    if context.awaiting_owner:
        return {
            "suggest": True,
            "priority": "P1",
            "reason": "Owner の判断待ち",
            "force": False
        }

    # P2: コンテキスト依存
    usage = context.context_usage_percent

    if usage >= 95:
        return {
            "suggest": True,
            "priority": "P2",
            "reason": f"コンテキスト使用率 {usage}% - 自動圧縮を回避",
            "force": True  # 強制終了
        }

    if usage >= 90 and context.has_logical_breakpoint:
        return {
            "suggest": True,
            "priority": "P2",
            "reason": f"コンテキスト使用率 {usage}% - 区切りが良いタイミング",
            "force": False
        }

    if usage >= 80:
        # 警告のみ、提案はしない
        context.log_warning(f"🟡 コンテキスト使用率 {usage}% - 次の区切りで終了推奨")
        # 台帳更新を強化
        context.prioritize_ledger_updates = True
        return {"suggest": False}

    return {"suggest": False}
```

#### 5.2 セッション終了の提案方法

**論理的区切りの場合（P0, P1）:**

```markdown
✅ [完了した作業] が完了しました

📊 セッション状態:
   - コンテキスト使用率: XX%
   - 完了タスク数: N 個
   - 現在のステージ: [STAGE]

📌 次のセッション推奨

**理由**: [ゲート通過した / 機能実装が完了した / など]

このセッションを終了して、次の作業を新しいセッションで開始することを推奨します。

**メリット**:
- ✅ コンテキストが fresh になり、判断精度が上がる
- ✅ 台帳が整理され、全体像が明確になる
- ✅ 次の作業に集中できる

**次のセッションでやること**:
- [具体的な次のタスク]

---

**[A] 新しいセッションを開始（推奨）**
   → 台帳を更新して終了します
   → 次のチャットで `/org-tick` を実行してください

**[B] このセッションを継続**
   → このまま次のタスクに進みます

どちらにしますか？
```

**コンテキスト95%超の場合（P2, 強制終了）:**

```markdown
⚠️ コンテキスト使用率: 95%

自動圧縮を回避するため、このセッションを終了します。

実行中:
1. ✅ DECISIONS.md に今セッションの判断を記録
2. ✅ TASKS.yaml を最新状態に更新
3. ✅ DASHBOARD.md に次のアクションを記載

📌 次のセッションを開始してください

新しいチャットで以下を入力:
→ /org-tick

**次のセッションでやること**:
- [具体的な次のタスク]

台帳から自動的に継続します。
```

---

### 6. 計画整合性チェック（Plan Sync）

実態と計画の乖離を検出し、必要に応じて計画を更新する。

#### 6.1 チェック項目

| チェック | 検出内容 | 対応 |
|----------|----------|------|
| **ad-hoc 作業** | TASKS.yaml にないファイル変更・コミット | TASKS.yaml に追加 or RUN_LOG に記録 |
| **スコープ外作業** | project_scope 外の依頼を実行 | 警告を出して Owner に確認 |
| **スコープ変更** | 新しい要件、取り下げられた要件 | PROJECT.md + TASKS.yaml を更新 |
| **タスク追加** | 実装中に判明した追加作業 | TASKS.yaml に新タスク追加 |
| **依存関係変更** | 前提が変わった、順序変更が必要 | TASKS.yaml の deps を修正 |
| **見積もり乖離** | 想定より大きい/小さいタスク | タスク分割 or 統合 |
| **リスク顕在化** | RISKS.md のリスクが発生 | 対応タスクを追加 |
| **ブロッカー発生** | 外部依存、Owner 作業待ち | status: blocked に変更 |

#### 6.2 計画更新のトリガー

以下の条件で計画を更新する：

```python
# 疑似コード
def check_plan_sync():
    updates_needed = []

    # ad-hoc 作業の検出（OIP-001）
    # STATUS.md の RUN_LOG に記録されているが TASKS.yaml にないタスク
    adhoc_work = detect_adhoc_work()
    if adhoc_work:
        for work in adhoc_work:
            if work.is_significant:  # 中〜大のタスクと判定
                updates_needed.append({
                    "type": "add_task",
                    "task": create_task_from_adhoc(work),
                    "warning": f"⚠️ ad-hoc 作業を検出: {work.description}"
                })

    # スコープ外作業の検出（OIP-001）
    # project_scope と異なる作業が行われていないか
    scope_violations = detect_scope_violations()
    if scope_violations:
        for violation in scope_violations:
            updates_needed.append({
                "type": "warning",
                "message": f"⚠️ スコープ外作業: {violation.description}",
                "action": "Owner に確認が必要"
            })

    # 新しい課題が発生した
    if new_issues_detected():
        for issue in new_issues:
            updates_needed.append({
                "type": "add_task",
                "task": create_fix_task(issue)
            })

    # 完了タスクから追加作業が判明
    for task in completed_tasks:
        if task.discovered_work:
            updates_needed.append({
                "type": "add_task",
                "task": create_followup_task(task.discovered_work)
            })

    # リスクが顕在化
    for risk in active_risks:
        if risk.materialized:
            updates_needed.append({
                "type": "add_task",
                "task": create_mitigation_task(risk)
            })
            updates_needed.append({
                "type": "update_risk",
                "risk": risk,
                "status": "materialized"
            })

    # スコープ変更（OWNER_COMMENTS から検出）
    if scope_changes_requested():
        updates_needed.append({
            "type": "update_project",
            "changes": parse_scope_changes()
        })

    return updates_needed
```

#### 6.3 計画更新の実行

更新が必要な場合：

1. **TASKS.yaml を更新**
   - 新タスク追加（適切な deps を設定）
   - 既存タスクの status/blocker を更新
   - 不要になったタスクを削除または archived に

2. **PROJECT.md を更新**（スコープ変更時）
   - ゴール/成果物の変更を反映
   - 変更理由を DECISIONS.md に記録

3. **DASHBOARD.md に反映**
   - 計画変更を Owner に通知
   - 影響範囲を説明

#### 6.4 計画更新の記録

```markdown
## DECISIONS.md に追記
- **PLAN-UPDATE-001**: TASKS.yaml を更新
  - 追加: T-FIX-001 (Client Secret 更新)
  - 変更: T-004 の deps に T-FIX-001 を追加
  - 理由: ISSUE-005 対応のため
```

---

### 7. 状況診断とエージェント自動選択

状況を分析し、必要なエージェントを自動的に選択・実行する。

#### 7.1 診断チェック

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

#### 7.2 診断の実行方法

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

#### 7.3 ビルドエラー検出

```bash
# TypeScript プロジェクト
npx tsc --noEmit 2>&1 | head -20

# Next.js
npm run build 2>&1 | head -20

# エラーがあれば org-build-fixer を起動
```

#### 7.4 カバレッジ検出

```bash
# カバレッジレポートを確認
npm test -- --coverage --coverageReporters=json-summary 2>/dev/null

# 80% 未満なら org-tdd-coach を起動
```

### 8. タスク委任

依存が解けた queued タスクを検出し、`runtime.max_parallel_tasks` 件まで自動的に委任する。

#### 8.1 実行可能タスクの検出

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

#### 8.2 owner_role による自動分岐

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

#### 8.3 Codex 実行の案内（auto_exec: false の場合）

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

### 9. レビュー処理（ポリシーベース）

`CONTROL.yaml` の `owner_review_policy` に従ってレビューを実行する。

#### 9.1 レビュートリガー判定

```python
# 疑似コード
def should_trigger_review(control, completed_task):
    policy = control.owner_review_policy

    # オーバーライド条件（常にトリガー）
    if policy.on_stage_transition and stage_changed:
        return True, "stage_transition"
    if policy.always_before_merge_to_main and is_merge_to_main:
        return True, "merge_to_main"
    if policy.always_before_release and is_release:
        return True, "release"

    # OWNER_COMMENTS.md に「レビューして」等の要求があればトリガー
    if owner_requested_review():
        return True, "owner_request"

    # モードによる判定（デフォルトは every_n_tasks）
    mode = policy.get("mode", "every_n_tasks")

    if mode == "every_tick":
        return True, "every_tick"

    elif mode == "every_n_tasks":
        tasks_done = policy.tasks_since_last_review + 1
        if tasks_done >= policy.every_n_tasks:
            # カウンターリセット
            update_counter(0)
            return True, "every_n_tasks"
        else:
            # カウンター更新、レビュースキップ
            update_counter(tasks_done)
            return False, None

    elif mode == "batch":
        # 全タスク完了時のみレビュー
        if all_tasks_completed():
            return True, "batch_complete"
        return False, None

    elif mode == "manual":
        # 手動要求がないのでスキップ
        return False, None

    return True, "default"  # フォールバック
```

#### 9.2 レビュー実行（トリガー時）

レビューをトリガーする場合：
- 完了タスクを `review` ステータスに移動
- Review Packet が `.ai/REVIEW/PACKETS/<TASK_ID>.md` にあることを確認
- `org-reviewer` + `org-security-reviewer` を並列で起動
- `tasks_since_last_review` カウンターをリセット

#### 9.3 レビュースキップ（非トリガー時）

レビューをスキップする場合：
- 完了タスクを `pending_review` ステータスに保持（batch/manual モード）
- または直接 `done` に移動（信頼度が高い場合）
- RUN_LOG に記録: `"レビュースキップ (mode: <mode>, counter: <n>/<total>)"`
- `tasks_since_last_review` カウンターを +1

#### 9.4 手動レビュー要求

OWNER_COMMENTS.md に以下のようなキーワードがあれば、モードに関係なくレビューをトリガー：
- 「レビューして」「レビュー依頼」「確認して」「review」

トリガー後はカウンターをリセット。

#### 9.5 バッチレビュー（mode=batch の場合）

全タスク完了時にまとめてレビュー：
- `pending_review` ステータスのタスクを全て `review` に移動
- 各タスクの Review Packet を確認
- `org-reviewer` + `org-security-reviewer` を実行

### 10. 統合処理
レビュー承認済みタスクがあれば：
- org-integrator に統合を委任
- main反映は Owner Reviewポリシーに従う
- 統合完了後、worktree を削除

### 11. Worktree クリーンアップ
`done` になったタスクの worktree を削除：
```bash
git worktree remove .worktrees/<TASK_ID> --force
git branch -d task/<TASK_ID>-<slug>
```

### 12. 台帳更新（org-scribe）
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
