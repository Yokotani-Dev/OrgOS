# /org-evolve

OrgOS 自律改善ループ。autoresearch パターンで OrgOS 自身を継続的に改善する。

**設計書**: [.ai/DESIGN/ORG_EVOLVE.md](../../.ai/DESIGN/ORG_EVOLVE.md)

---

## 引数

```
/org-evolve          — 1サイクル実行（デフォルト）
/org-evolve N        — Nサイクル実行（最大10）
/org-evolve dry-run  — REVIEW + PICK のみ（変更なし）
/org-evolve status   — 直近の EVOLVE_LOG を表示
/org-evolve summary  — 週次サマリーレポート生成
/org-evolve schedule — スケジュール設定の確認・更新
```

引数は `$ARGUMENTS` で受け取る。

---

## 前提条件チェック

実行前に以下を確認。1つでも満たさなければ中止:

```python
assert CONTROL.yaml.allow_os_mutation == True   # OS変更許可
assert CONTROL.yaml.paused == False              # 一時停止中でない
```

---

## status サブコマンド

`$ARGUMENTS` が `status` の場合:
1. `.ai/EVOLVE_LOG.md` を読む
2. 直近5件のエントリを表示
3. 統計（KEEP/REVERT 比率、改善カテゴリ分布）を表示
4. 終了

---

## メインループ

`$ARGUMENTS` から繰り返し回数 N を取得（デフォルト: 1、最大: 10）。
`dry-run` の場合は N=1 で変更なし。

```
consecutive_reverts = 0

for cycle in 1..N:
    実行: Step 1〜8
    if consecutive_reverts >= 3: break（行き詰まり）
```

---

### Step 1: REVIEW — 現状分析

OrgOS のファイル群を走査し、改善可能な項目を列挙する。

#### 1.1 既存 Eval の実行

```bash
.claude/evals/run-all.sh --json 2>/dev/null || echo '{"overall":"skip"}'
```

結果を `eval_baseline` として保持。

#### 1.2 参照パス検証

`.claude/` 配下の markdown ファイルで、`[text](path)` 形式のリンクと `参照:` 行のパスを抽出し、実在するか確認する。

```python
# Grep で参照パスを抽出
# Glob で対象ファイル一覧を取得
# 各パスの実在を確認
broken_refs = []  # 壊れた参照のリスト
```

#### 1.3 重複検出

`.claude/rules/` と `.claude/skills/` の間で、3行以上の同一ブロックを検出する。

```python
# 各ファイルを読み、3行連続で一致するブロックを探す
duplicates = []  # {file_a, file_b, lines, content}
```

#### 1.4 エージェント定義チェック

```bash
.claude/evals/check-agent-defs.sh 2>/dev/null
```

warn/fail があれば改善候補に追加。

#### 1.5 一貫性チェック

数値基準（カバレッジ%、関数行数等）が複数ファイルで異なる値になっていないか確認。

```python
# "80%" "90%" などの数値パターンを文脈付きで抽出
# 同じ概念に対する異なる数値を検出
inconsistencies = []
```

#### 1.6 改善候補リスト作成

検出した問題を優先度順にリスト化:

| 優先度 | カテゴリ | 対象 |
|--------|----------|------|
| P0 | repair | 壊れた参照パス |
| P0 | repair | Eval 失敗項目 |
| P1 | consistency | 数値基準の不整合 |
| P2 | deduplicate | 重複コンテンツ |
| P2 | completeness | エージェント定義の warn |
| P3 | optimize | その他の改善 |

---

### Step 2: PICK — 改善候補の選定

改善候補リストから **1つだけ** 選ぶ。

#### 選定ルール

1. 優先度が最も高いものを選ぶ
2. 同一優先度なら、影響範囲が小さいものを優先（安全側）
3. **Kernel ファイルは対象外**（`.claude/evals/KERNEL_FILES` を参照）
4. git log で `experiment(evolve):` プレフィクスを検索し、直近3サイクル以内に同一ファイル・同一カテゴリで REVERT されたものはスキップ

```bash
# 直近の evolve 実験履歴を確認
git log --oneline --grep="experiment(evolve)" -20 2>/dev/null || true
```

#### 候補なしの場合

改善候補がなければ:
```
改善候補なし。OrgOS は現在良好な状態です。
```
→ ループを終了。

#### dry-run の場合

候補を表示して終了:
```markdown
## org-evolve dry-run 結果

検出した改善候補: N 件

| # | 優先度 | カテゴリ | 対象 | 内容 |
|---|--------|----------|------|------|
| 1 | P0 | repair | .claude/rules/testing.md | 壊れた参照パス: ../skills/xxx.md |
| 2 | P1 | consistency | .claude/rules/*.md | カバレッジ基準 80% vs 85% |
| ... | | | | |

次回 `/org-evolve` で #1 から実行します。
```

---

### Step 3: MAKE — 変更の実装

選定した候補に対し、最小限の変更を実装する。

#### 制約

- **Userland ファイルのみ**（Kernel 境界を尊重）
- **最大 3 ファイル**まで変更可
- **1ファイルあたり最大 50 行**の差分まで
- **新規ファイル作成禁止**（既存ファイルの修正のみ）
- Edit ツールで変更を適用

#### カテゴリ別の実装パターン

| カテゴリ | 実装方法 |
|----------|---------|
| `repair` | 壊れたパスを正しいパスに修正（Glob で実在パスを検索） |
| `deduplicate` | 重複箇所の一方を「参照: <file>#<section>」に置換 |
| `consistency` | 数値基準を CLAUDE.md / rules の正とする方に統一 |
| `completeness` | エージェント定義の欠落フィールドを追加 |
| `optimize` | 冗長な記述を簡潔化（意味を変えない） |

---

### Step 4: COMMIT — 変更の記録

変更を git commit する。**検証前にコミット**（Git = メモリ原則）。

```bash
git add <changed-files>
git commit -m "$(cat <<'EOF'
experiment(evolve): <変更内容の要約>

Category: <repair|deduplicate|consistency|completeness|optimize>
Cycle: <N>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

コミットハッシュを `commit_hash` として保持。

---

### Step 5: VERIFY — 機械的検証

#### 5.1 既存 Eval の再実行

```bash
.claude/evals/run-all.sh --json 2>/dev/null || echo '{"overall":"skip"}'
```

結果を `eval_after` として保持。

#### 5.2 判定

```python
# 必須条件: 既存 Eval が全 pass
if eval_after.overall == "fail":
    verdict = "REVERT"  # Eval 失敗

# Eval が pass なら改善を確認
elif eval_after.overall in ["pass", "skip"]:
    # Step 1 と同じ分析を再実行し、対象メトリクスが改善したか確認
    # 例: broken_refs が減った、duplicates が減った、etc.
    if metric_improved_or_maintained:
        verdict = "KEEP"
    else:
        verdict = "REVERT"  # メトリクス悪化
```

---

### Step 6: EVALUATE — 結果の適用

#### KEEP の場合

```
変更を保持。consecutive_reverts = 0 にリセット。
```

#### REVERT の場合

```bash
git revert HEAD --no-edit
```

```
consecutive_reverts += 1
```

---

### Step 7: LOG — 結果記録

`.ai/EVOLVE_LOG.md` に追記。

ファイルが存在しない場合はヘッダー付きで作成:

```markdown
# EVOLVE LOG

> org-evolve の実行履歴。自動生成。

---
```

エントリを追記:

```markdown
## EVOLVE-<NNN>: <変更内容> (YYYY-MM-DD)

| 項目 | 値 |
|------|-----|
| カテゴリ | <category> |
| 対象ファイル | <file_paths> |
| メトリクス（before） | <value> |
| メトリクス（after） | <value> |
| 結果 | KEEP / REVERT |
| コミット | <hash> |
| Eval | pass / fail / skip |

### 詳細
<何をなぜ変更したか、1-3行で>
```

EVOLVE_LOG のエントリ番号は、既存エントリ数 + 1 で採番。

---

### Step 8: REPEAT 判定

```python
if consecutive_reverts >= 3:
    print("連続3回 REVERT — 行き詰まり検出。停止します。")
    break
# else: 次のサイクルへ
```

---

## 完了報告

全サイクル完了後、結果をサマリー表示:

```markdown
## org-evolve 完了

| サイクル | カテゴリ | 対象 | 結果 |
|----------|----------|------|------|
| 1 | repair | .claude/rules/testing.md | KEEP |
| 2 | deduplicate | .claude/rules/performance.md | REVERT |
| ... | | | |

**結果**: N サイクル実行、K 件 KEEP、R 件 REVERT

📌 次はこちら: /org-tick
   改善結果を台帳に反映します
```

---

## 安全策まとめ

| 制約 | 値 |
|------|-----|
| 最大サイクル数 | 10 |
| 連続 REVERT 上限 | 3（超えたら停止） |
| 変更ファイル上限 | 3ファイル/サイクル |
| 差分上限 | 50行/ファイル |
| Kernel ファイル | 変更禁止 |
| 新規ファイル作成 | 禁止 |
| `allow_os_mutation` | true 必須 |
| `paused` | false 必須 |

---

## 参考

- 設計書: [.ai/DESIGN/ORG_EVOLVE.md](../../.ai/DESIGN/ORG_EVOLVE.md)
- Eval スイート: [.claude/evals/](../evals/)
- Kernel 境界: [.claude/evals/KERNEL_FILES](../evals/KERNEL_FILES)
- autoresearch: https://github.com/uditgoenka/autoresearch

---

## summary サブコマンド

`$ARGUMENTS` が `summary` の場合:

1. `.ai/EVOLVE_LOG.md` を読む
2. 直近7日間のエントリを集計
3. 週次サマリーレポートを生成:

```markdown
## org-evolve 週次サマリー (YYYY-MM-DD ~ YYYY-MM-DD)

### 実行統計
| 項目 | 値 |
|------|-----|
| 実行サイクル数 | N |
| KEEP | K |
| REVERT | R |
| 成功率 | X% |

### KEEP された改善
| # | カテゴリ | 対象 | 内容 |
|---|----------|------|------|
| 1 | repair | file.md | 壊れた参照パスを修正 |

### 現在の OrgOS 健全性
| メトリクス | 値 |
|-----------|-----|
| Eval pass | N/M |
| 壊れた参照 | 0 |
| 重複ブロック | N |
| 不整合 | N |
```

4. DASHBOARD.md の Recent Changes に追記
5. 終了

---

## schedule サブコマンド

`$ARGUMENTS` が `schedule` の場合:

1. `CONTROL.yaml` の `evolve` セクションを読む
2. 現在のスケジュール設定を表示
3. RemoteTrigger の一覧を取得して既存トリガーを表示
4. 設定変更のオプションを提示:

```markdown
## org-evolve スケジュール設定

| 項目 | 現在値 |
|------|--------|
| 有効 | true |
| 頻度 | weekly（毎週月曜 9:17 JST） |
| サイクル数/回 | 3 |
| 自動 push | true |

RemoteTrigger ID: <trigger_id or "未設定">

[A] スケジュールを作成/更新
[B] スケジュールを削除
[C] 今すぐ手動実行（テスト）
```

5. 選択に応じて RemoteTrigger を操作

---

## 通知（スケジュール実行時）

スケジュール実行（RemoteTrigger 経由）の場合、完了後に以下を自動実行:

1. **EVOLVE_LOG.md に結果を記録**（Step 7 で実施済み）
2. **DASHBOARD.md の Recent Changes を更新**
3. **変更を git commit + push**（`evolve.auto_push: true` の場合）
4. **KEEP された変更がある場合、OWNER_INBOX.md に通知を追加**:

```markdown
## org-evolve 週次レポート (YYYY-MM-DD)

自動改善を N サイクル実行し、K 件の改善を適用しました。

| # | カテゴリ | 対象 | 内容 |
|---|----------|------|------|
| 1 | repair | file.md | 壊れた参照パスを修正 |

詳細: .ai/EVOLVE_LOG.md

確認不要であれば次の `/org-tick` で自動処理されます。
```

---

## スケジュール実行

### 設定

`CONTROL.yaml` の `evolve` セクション:

```yaml
evolve:
  enabled: true           # スケジュール有効
  schedule: "weekly"      # weekly / daily / disabled
  cycles_per_run: 3       # 1回あたりの実行サイクル数
  auto_push: true         # 完了後に自動 push
  slack_webhook: ""       # Slack Incoming Webhook URL（オプション）
```

### RemoteTrigger

Claude Code の RemoteTrigger API で週次スケジュールを設定:

```
cron: "17 9 * * 1"  # 毎週月曜 9:17 JST
prompt: "/org-evolve 3"
```

RemoteTrigger はセッション単位ではなく永続的に動作する。
`/org-evolve schedule` で確認・更新が可能。

### Slack 通知（オプション）

`evolve.slack_webhook` に Incoming Webhook URL を設定すると、
実行結果を Slack に通知する。未設定の場合は OWNER_INBOX.md への記録のみ。
