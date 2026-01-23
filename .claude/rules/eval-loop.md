# 評価ループ（Verification Loops）

> タスク完了時・ステージ遷移時の品質検証ルール

---

## 概要

OrgOS は評価ループ（Verification Loops）を使って、実装品質を継続的に検証する。
評価は自動で行われ、問題があれば次のタスクに進む前に修正を促す。

---

## 評価モード

`CONTROL.yaml` の `eval_policy.mode` で設定:

| モード | 説明 | 適したケース |
|--------|------|--------------|
| `checkpoint` | ステージ遷移時にのみ評価 | 線形ワークフロー、明確なマイルストーンがある |
| `continuous` | Nタスクごとに評価 | 探索的リファクタリング、長期セッション |
| `disabled` | 評価なし | 調査・ドキュメントのみのタスク |

---

## チェックポイント評価

ステージ遷移時（DESIGN → IMPLEMENTATION など）に以下を確認:

### 1. 自動チェック

```yaml
checks:
  - tests_pass        # テストが通る
  - build_success     # ビルドが通る
  - no_regressions    # 既存機能が壊れていない
```

### 2. 実行方法

`/org-tick` 実行時、ステージ遷移が検出されたら:

1. 評価を実行
2. 結果を `DECISIONS.md` に記録
3. 失敗があれば修正タスクを自動生成

### 3. 出力例

```markdown
## EVAL-001: Design → Implementation 評価 (2026-01-23)

### 結果: ✅ PASS

| チェック | 結果 |
|----------|------|
| tests_pass | ✅ |
| build_success | ✅ |
| no_regressions | ✅ |

### 次のアクション
ステージを IMPLEMENTATION に進める。
```

---

## 継続的評価

`continuous` モードでは、`continuous_interval_tasks` タスクごとに評価:

1. タスク完了時に `tasks_since_last_eval` をインクリメント
2. 閾値に達したら評価を実行
3. カウンターをリセット

---

## 評価メトリクス

### pass@k

「k回中1回でも成功すればOK」

- 探索的タスクに適している
- 複数のアプローチを試すケース
- 例: k=3 → 3回中1回成功すればPASS

### pass^k

「k回全て成功が必要」

- 一貫性が重要なタスクに適している
- 決定論的な出力が必要なケース
- 例: k=3 → 3回全て成功でないとPASS

### OrgOS でのデフォルト

通常は `pass@1`（1回の実行で成功すればOK）。
クリティカルな変更（本番デプロイ前など）では `pass^2` を使用。

---

## /org-tick での統合

`/org-tick` は以下のタイミングで評価を実行:

1. **ステージ遷移時**（checkpoint モード）
   - 次のステージに進む前に評価
   - 失敗したら遷移をブロック

2. **タスク完了時**（continuous モード）
   - `tasks_since_last_eval` が閾値に達したら評価
   - 失敗したら修正タスクを生成

3. **明示的な評価依頼**
   - Owner が「評価して」と依頼した場合
   - `/org-tick eval` で強制評価

---

## 評価失敗時の対応

### 自動対応

1. 失敗チェックを特定
2. 修正タスクを `TASKS.yaml` に追加
3. 優先度 P0 で次の Tick で実行

### 例

```yaml
- id: T-FIX-EVAL-001
  title: "Fix: テスト失敗を修正"
  status: queued
  priority: P0
  deps: []
  owner_role: "org-build-fixer"
  notes: "EVAL-001 で tests_pass 失敗"
```

---

## 設定例

### 厳格モード（本番前）

```yaml
eval_policy:
  mode: "checkpoint"
  checkpoint_stages:
    - design
    - implementation
    - integration
  criteria:
    default_metric: "pass^2"
    checks:
      - tests_pass
      - build_success
      - no_regressions
      - security_scan
      - lint_clean
```

### 軽量モード（プロトタイプ）

```yaml
eval_policy:
  mode: "continuous"
  continuous_interval_tasks: 10
  criteria:
    default_metric: "pass@1"
    checks:
      - build_success
```

---

## 参考

- 記事: "Verification Loops and Evals"
- Anthropic: "Demystifying evals for AI agents" (Jan 2026)
- [.claude/rules/testing.md](testing.md)
