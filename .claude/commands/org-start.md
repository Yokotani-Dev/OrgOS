---
description: OrgOSプロジェクト起動（初期化→キックオフ→質問提示まで自動実行）
---

# /org-start - プロジェクト起動コマンド

このコマンドは新規プロジェクト開始時に1回だけ実行する。
以下を自動で行う：
1. `.ai/` の初期化（既存データは退避）
2. BRIEF.md の確認
3. キックオフ質問の生成
4. DASHBOARD の更新

---

## 実行手順

### Step 1: 既存データの退避

`.ai/` に既存ファイルがある場合、以下を `.ai/_archive/<YYYYMMDD-HHMMSS>/` に退避する：

**退避対象ファイル：**
- DASHBOARD.md
- OWNER_INBOX.md
- OWNER_COMMENTS.md
- STATUS.md
- RUN_LOG.md
- DECISIONS.md
- RISKS.md
- TASKS.yaml
- CODEX/RESULTS/* （存在する場合）
- CODEX/LOGS/* （存在する場合）
- REVIEW/PACKETS/* （存在する場合）

**退避しないファイル（維持）：**
- CONTROL.yaml（リセットするが退避もする）
- PROJECT.md（テンプレ上書き）
- BRIEF.md（ユーザー入力なので維持）
- GIT_WORKFLOW.md（OS設定）
- OS/*（OS履歴）
- CODEX/README.md（OS設定）
- CODEX/ORDERS/*（退避する）

退避完了後、退避したファイル数を記録する。

### Step 2: 台帳の初期化

以下のファイルを初期テンプレートで再作成する：

```
.ai/
  CONTROL.yaml      # stage: KICKOFF, allow_*: false, awaiting_owner: false
  DASHBOARD.md      # 起動直後テンプレ
  TASKS.yaml        # 空（T-001 kickoffのみ）
  STATUS.md         # 空テンプレ
  RUN_LOG.md        # 空テンプレ
  DECISIONS.md      # 空テンプレ
  RISKS.md          # 空テンプレ
  OWNER_INBOX.md    # 空テンプレ
  OWNER_COMMENTS.md # 空テンプレ
  PROJECT.md        # 空テンプレ
  CODEX/
    ORDERS/         # 空
    RESULTS/        # 空
    LOGS/           # 空
  REVIEW/
    REVIEW_QUEUE.md # 空
    PACKETS/        # 空
```

### Step 3: BRIEF.md の確認

`.ai/BRIEF.md` を読み、以下を判定：

**BRIEF が未記入の場合（テンプレのまま or 空）：**
- DASHBOARD.md に「BRIEFを書いてください」と表示
- awaiting_owner: true を設定
- **ここで停止**（キックオフに進まない）

**BRIEF が記入済みの場合：**
- Step 4 に進む

### Step 4: キックオフ質問の生成

BRIEF.md の内容を読み、以下の質問を OWNER_INBOX.md に生成する：

1. **目的/成功指標の確認**
   - BRIEFの「作りたいもの」から目的を抽出
   - KPI/受入基準を明確化する質問

2. **スコープの確認**
   - マスト要件の優先順位
   - 望ましい要件の取捨選択

3. **技術制約の確認**
   - 既存資産との整合性
   - 言語/フレームワーク/インフラの選択

4. **リスク/未決事項の確認**
   - NG事項の詳細化
   - 期限/予算の現実性

質問は具体的に、選択肢を提示する形式で書く。

### Step 5: 状態の更新

- CONTROL.yaml:
  - stage: KICKOFF
  - awaiting_owner: true
  - gates.kickoff_complete: false
- DASHBOARD.md:
  - 「OWNER_INBOX に回答してください」と表示
  - 次のステップを明記
- TASKS.yaml:
  - T-001 (Kickoff) を queued に設定

---

## 出力例（DASHBOARD.md）

```markdown
# DASHBOARD

## Now
- Stage: KICKOFF
- Awaiting Owner: **YES** ← 回答待ち

## Next Action (Owner)
1. `.ai/OWNER_INBOX.md` の質問に回答してください
2. 回答は `.ai/OWNER_COMMENTS.md` に記入
3. 記入後、`/org-tick` を実行（または次のメッセージを送信）

## Progress
- [x] BRIEF.md 確認済み
- [ ] キックオフ質問に回答
- [ ] 要件確定
- [ ] 設計開始

## 禁止事項（ゲート制御中）
- git push: ❌ (allow_push=false)
- deploy: ❌ (allow_deploy=false)
- OS変更: ❌ (allow_os_mutation=false)
```

---

## エラーハンドリング

- `.ai/` ディレクトリが存在しない場合 → 作成する
- BRIEF.md が存在しない場合 → テンプレートを作成し、記入を促して停止
- 退避先が既に存在する場合 → タイムスタンプを1秒ずらして再試行

---

## 注意事項

- このコマンドは **プロジェクト開始時に1回だけ** 実行する
- 2回目以降の実行は既存データを退避するため、意図しない実行に注意
- 退避されたデータは `.ai/_archive/` から復元可能
