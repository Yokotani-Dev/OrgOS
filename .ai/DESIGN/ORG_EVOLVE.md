# org-evolve 設計書

> OrgOS 自律改善ループ — autoresearch パターンの適用

**ステータス**: 設計中
**作成日**: 2026-03-24
**関連タスク**: T-OS-026〜T-OS-029
**参考**: [autoresearch](https://github.com/uditgoenka/autoresearch)

---

## 1. 目的

OrgOS 自身のルール・スキル・エージェント定義を **定期的かつ自律的に改善** する仕組み。

autoresearch の核心コンセプト:
- **アトミック変更**: 1サイクル1変更で因果関係を明確化
- **機械的検証**: メトリクス駆動で主観排除
- **自動ロールバック**: 検証失敗 → 即 git revert
- **Git = メモリ**: 全実験（成功/失敗）を履歴として保存

---

## 2. 既存資産との関係

| 既存機能 | 役割 | org-evolve との関係 |
|----------|------|---------------------|
| **OS Evals** (`.claude/evals/`) | OIP-AUTO の安全性検証 | Verify ステップで再利用 |
| **org-os-maintainer** | 運用ログから OIP 提案 | Pick ステップで改善候補の情報源 |
| **Intelligence Pipeline** | 外部情報収集 → OIP-AUTO 生成 | Pick ステップで外部知識を活用 |
| **Kernel/Userland 境界** | 自動変更の安全制御 | 変更範囲の制約として適用 |
| **eval_policy** (CONTROL.yaml) | チェックポイント評価 | 連携（evolve 結果を eval に統合） |

### 棲み分け

| 機能 | トリガー | 変更対象 | 承認 |
|------|----------|----------|------|
| **org-os-maintainer** | 手動 (Manager 起動) | 提案のみ（実装しない） | Owner が `/org-admin` で適用 |
| **Intelligence OIP-AUTO** | 定期（cron） | Userland ファイル | Level 判定 → 自動 or Owner 承認 |
| **org-evolve** | 手動 or 定期 | Userland ファイル | Eval pass → 自動適用、fail → revert |

**org-evolve の差別化**: Intelligence は外部情報ベース、org-evolve は **内部分析ベース**（ルール整合性、重複、パターン改善など）。

---

## 3. 改善ループ（8フェーズ）

autoresearch の 8 フェーズを OrgOS に適応:

```
┌──────────────────────────────────────────────┐
│                  org-evolve                   │
│                                               │
│  1. REVIEW  ─→  2. PICK  ─→  3. MAKE        │
│      ↑                           │            │
│      │                           ↓            │
│  8. REPEAT     7. LOG  ←─  4. COMMIT         │
│                  ↑               │            │
│                  │               ↓            │
│               6. EVALUATE ←─ 5. VERIFY       │
│                                               │
│  失敗時: COMMIT → VERIFY fail → REVERT       │
└──────────────────────────────────────────────┘
```

### 3.1 REVIEW — 現状分析

OrgOS のファイル群を走査し、改善可能な項目を列挙する。

**分析対象**:
- `.claude/rules/*.md` — ルール間の整合性、重複、参照パスの有効性
- `.claude/skills/*.md` — パターンの最新性、ルールとの整合性
- `.claude/agents/*.md` — 定義の完全性、roles の最適性
- `.claude/commands/*.md` — コマンド間の重複、フロー整合性
- `.ai/CONTROL.yaml` — スキーマ妥当性（読み取りのみ、Kernel のため変更不可）
- `.ai/TASKS.yaml` — スキーマ妥当性
- git log — 最近の実験履歴（成功/失敗パターン）

**分析メトリクス**:
| メトリクス | 計測方法 | 目的 |
|-----------|---------|------|
| 壊れた参照パス数 | `check-refs.sh` (新規) | ファイル間参照の健全性 |
| ルール間重複行数 | `check-duplicates.sh` (新規) | DRY 原則 |
| エージェント定義スコア | `check-agent-defs.sh` (既存) | 定義の完全性 |
| Eval pass 率 | `run-all.sh` (既存) | 全体的な健全性 |
| ファイル間一貫性 | `check-consistency.sh` (新規) | 用語・パターンの統一 |

### 3.2 PICK — 改善候補の選定

REVIEW の結果から **1つだけ** 改善候補を選ぶ。

**選定基準**（優先度順）:
1. **壊れた参照パス** — 即座に影響がある（P0）
2. **Eval 失敗項目** — 既存チェックで検出済み（P0）
3. **ルール間矛盾** — 動作に影響しうる（P1）
4. **重複コード** — 保守性低下（P2）
5. **パターン最新化** — 改善の余地あり（P3）

**選定ルール**:
- 1サイクル1変更（autoresearch の Atomic Changes 原則）
- 前回失敗した同一カテゴリは3サイクル後まで再試行しない
- Kernel ファイルは変更対象外

**情報源**:
- REVIEW の分析結果（主）
- org-os-maintainer の OIP 提案（`.ai/OIP/`）（補助）
- Intelligence レポートの OIP-AUTO（`.ai/INTELLIGENCE/`）（補助）

### 3.3 MAKE — 変更の実装

選定した改善候補に対し、最小限の変更を実装する。

**制約**:
- Userland ファイルのみ変更可（Kernel 境界を尊重）
- 1ファイル or 関連する2-3ファイルまで
- 既存の動作を壊さない（機能追加/修正のみ）
- コメントプレフィクス: `<!-- org-evolve: ... -->` は不要（git で追跡）

### 3.4 COMMIT — 変更の記録

変更を git commit する（**検証前に**コミット）。

```
git add <changed-files>
git commit -m "experiment(evolve): <変更内容の要約>

Category: <repair|deduplicate|update|optimize>
Metric-before: <値>
Metric-target: <値>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

**重要**: 検証前にコミットすることで、失敗した実験も git 履歴に残る。
これが autoresearch の「Git = メモリ」原則。

### 3.5 VERIFY — 機械的検証

既存の Eval スイート + 追加チェックで検証する。

**実行するチェック**:
```bash
# 1. 既存 Eval（必須）
.claude/evals/run-all.sh --json

# 2. 追加チェック（Phase 2 で整備）
.claude/evals/check-refs.sh        # 参照パス検証
.claude/evals/check-duplicates.sh  # 重複検出
.claude/evals/check-consistency.sh # 一貫性チェック

# 3. 改善固有メトリクス
# PICK で選んだカテゴリに応じた検証
```

**判定基準**:
- 既存 Eval が全 pass（必須条件）
- 対象メトリクスが改善 or 維持（悪化は fail）
- 新たな Eval 警告が増えていない

### 3.6 EVALUATE — 結果判定

| VERIFY 結果 | 対応 |
|-------------|------|
| **pass + メトリクス改善** | KEEP（コミットを保持） |
| **pass + メトリクス維持** | KEEP（害がなければ保持、simpler wins 原則） |
| **pass + メトリクス悪化** | REVERT |
| **fail** | REVERT |

**REVERT の実行**:
```bash
git revert HEAD --no-edit
```

**simpler wins 原則**: 同じメトリクスなら、よりシンプルな変更を保持する。

### 3.7 LOG — 結果記録

`.ai/EVOLVE_LOG.md` に結果を記録。

```markdown
## EVOLVE-<NNN>: <変更内容> (YYYY-MM-DD)

| 項目 | 値 |
|------|-----|
| カテゴリ | repair / deduplicate / update / optimize |
| 対象ファイル | <ファイルパス> |
| メトリクス（before） | <値> |
| メトリクス（after） | <値> |
| 結果 | KEEP / REVERT |
| コミット | <hash> |

### 詳細
<何をなぜ変更したか>
```

### 3.8 REPEAT — 繰り返し

- `/org-evolve N` で N 回繰り返し（デフォルト: 1）
- 改善候補がなくなったら自動停止
- 連続 3 回 REVERT したら停止（行き詰まり検出）
- 最大 10 サイクル/実行（安全制限）

---

## 4. 改善対象カテゴリ

| カテゴリ | ID | 内容 | メトリクス |
|----------|-----|------|-----------|
| **参照修復** | `repair` | 壊れたファイル参照パスの修正 | 無効参照パス数（0が目標） |
| **重複排除** | `deduplicate` | ルール/スキル間の重複コンテンツ削減 | 重複行数 |
| **整合性修正** | `consistency` | 用語・数値・パターンの統一 | 不整合箇所数 |
| **定義補完** | `completeness` | エージェント定義の必須フィールド補完 | check-agent-defs.sh のスコア |
| **パターン更新** | `update` | 古いパターンの最新化 | 手動判定 → Phase 3 で WebSearch 連携 |
| **最適化** | `optimize` | コマンド/ルールの効率化 | ファイルサイズ、処理ステップ数 |

---

## 5. 安全策

### 5.1 Kernel 境界の厳守

[.claude/evals/KERNEL_FILES](.claude/evals/KERNEL_FILES) に定義されたファイルは **絶対に変更しない**。

現在の Kernel ファイル:
- `.claude/rules/security.md`
- `.claude/rules/review-criteria.md`
- `.claude/rules/project-flow.md`
- `.ai/CONTROL.yaml`

Kernel 変更が必要な改善は OIP として提案し、Owner 承認を経て `/org-admin` で適用する。

### 5.2 自動ロールバック

- VERIFY 失敗 → 即座に `git revert HEAD --no-edit`
- REVERT もコミット履歴に残る（実験の記録）

### 5.3 変更スコープ制限

1サイクルあたり:
- 最大 3 ファイルまで変更可
- 1ファイルあたり最大 50 行の差分まで
- 新規ファイル作成は禁止（既存ファイルの修正のみ）

### 5.4 実行制限

- 1回の `/org-evolve` 呼び出しで最大 10 サイクル
- 連続 3 回 REVERT で自動停止
- CONTROL.yaml の `allow_os_mutation: true` が必須
- `paused: true` のときは実行しない

### 5.5 Owner 通知

- 毎回の実行結果を EVOLVE_LOG.md に記録
- KEEP された変更は DASHBOARD.md に反映
- Phase 3（スケジュール実行）では Slack 通知を追加

---

## 6. メトリクスの機械的検証

autoresearch の「Mechanical Verification Only」原則に従い、全メトリクスを機械的に計測する。

### 6.1 既存チェック（再利用）

| チェック | スクリプト | 出力 |
|----------|-----------|------|
| Kernel 境界 | `check-kernel-boundary.sh` | pass/fail |
| スキーマ検証 | `check-schema.sh` | pass/fail + 詳細 |
| エージェント定義 | `check-agent-defs.sh` | pass/fail/warn |
| セキュリティルール | `check-security.sh` | pass/fail |
| OIP フォーマット | `check-oip-format.sh` | pass/fail |

### 6.2 新規チェック（Phase 2 で実装）

| チェック | スクリプト | 計測内容 |
|----------|-----------|---------|
| **参照パス検証** | `check-refs.sh` | `.claude/` 内の `[text](path)` と `参照:` の有効性 |
| **重複検出** | `check-duplicates.sh` | ルール/スキル間の3行以上の同一ブロック |
| **一貫性チェック** | `check-consistency.sh` | 数値基準（カバレッジ%等）の統一性 |

### 6.3 メトリクス集約

```json
{
  "timestamp": "2026-03-24T12:00:00Z",
  "eval_pass": true,
  "metrics": {
    "broken_refs": 0,
    "duplicate_lines": 42,
    "inconsistencies": 3,
    "agent_def_score": 95,
    "total_eval_score": 5
  }
}
```

---

## 7. コマンド仕様

### `/org-evolve`

```
/org-evolve [N]        — N サイクル実行（デフォルト: 1）
/org-evolve --dry-run  — REVIEW + PICK のみ（変更なし）
/org-evolve --status   — 直近の EVOLVE_LOG を表示
```

### 実行フロー

```python
def org_evolve(cycles=1, dry_run=False):
    # 前提条件チェック
    assert control.allow_os_mutation == True
    assert control.paused == False

    consecutive_reverts = 0

    for i in range(min(cycles, 10)):  # 最大10サイクル
        # 1. REVIEW
        metrics_before = run_all_metrics()
        candidates = analyze_improvements()

        if not candidates:
            log("改善候補なし — 停止")
            break

        # 2. PICK
        target = pick_best_candidate(candidates)

        if dry_run:
            report_candidate(target)
            continue

        # 3. MAKE
        changes = implement_change(target)

        # 4. COMMIT
        commit_hash = git_commit(changes, prefix="experiment(evolve)")

        # 5. VERIFY
        eval_result = run_all_evals()
        metrics_after = run_all_metrics()

        # 6. EVALUATE
        if eval_result.passed and metrics_improved_or_maintained(metrics_before, metrics_after):
            result = "KEEP"
            consecutive_reverts = 0
        else:
            result = "REVERT"
            git_revert(commit_hash)
            consecutive_reverts += 1

        # 7. LOG
        log_evolve_result(target, metrics_before, metrics_after, result, commit_hash)

        # 8. REPEAT 判定
        if consecutive_reverts >= 3:
            log("連続3回 REVERT — 行き詰まり検出、停止")
            break

    return summary
```

---

## 8. Phase 計画

### Phase 1: `/org-evolve` コマンド実装（T-OS-027）

- コマンドファイル: `.claude/commands/org-evolve.md`
- 手動実行のみ（`/org-evolve` or `/org-evolve N`）
- 既存 Eval スイートを Verify に使用
- EVOLVE_LOG.md に結果記録
- `--dry-run` と `--status` オプション

### Phase 2: Eval スイート拡張（T-OS-028）

新規チェッカーの追加:
- `check-refs.sh` — 参照パス検証
- `check-duplicates.sh` — 重複検出
- `check-consistency.sh` — 一貫性チェック
- `run-all.sh` への統合

### Phase 3: スケジュール実行（T-OS-029）

- Claude Code `schedule` 機能で週次実行
- 実行結果を Slack 通知（Intelligence パイプライン連携）
- Owner 承認ゲート（重要変更は自動適用しない）
- 週次サマリーレポート

---

## 9. ファイル構成

```
.claude/
  commands/
    org-evolve.md         # コマンド定義（Phase 1）
  evals/
    KERNEL_FILES           # 既存
    run-all.sh             # 既存（拡張）
    check-kernel-boundary.sh  # 既存
    check-schema.sh           # 既存
    check-agent-defs.sh       # 既存
    check-security.sh         # 既存
    check-oip-format.sh       # 既存
    check-refs.sh             # 新規（Phase 2）
    check-duplicates.sh       # 新規（Phase 2）
    check-consistency.sh      # 新規（Phase 2）
.ai/
  EVOLVE_LOG.md            # 実行履歴（Phase 1）
  DESIGN/
    ORG_EVOLVE.md          # この設計書
```

---

## 10. リスク

| リスク | 影響 | 対策 |
|--------|------|------|
| 無限ループ | リソース消費 | 最大10サイクル + 連続3回REVERT停止 |
| Kernel 破壊 | OS 動作不能 | Kernel 境界チェック（二重検証） |
| 意図しない退行 | 品質低下 | 全 Eval pass 必須 + 自動 revert |
| git 履歴汚染 | 履歴が見づらい | `experiment(evolve):` プレフィクスで識別可能 |
| メトリクス不十分 | 改善判定が甘い | Phase 2 でチェッカーを段階的に追加 |
