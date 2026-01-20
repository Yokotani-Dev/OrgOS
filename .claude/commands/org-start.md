---
description: OrgOSプロジェクト起動（初期化→キックオフ→質問提示まで自動実行）
---

# /org-start - プロジェクト起動コマンド

このコマンドは新規プロジェクト開始時に1回だけ実行する。
以下を自動で行う：
1. リポジトリ状態の確認（OrgOS-Dev接続時は警告・切断）
2. `.ai/` の初期化（既存データは退避）
3. BRIEF.md の確認
4. キックオフ質問の生成
5. DASHBOARD の更新

---

## 実行手順

### Step 1: リポジトリ状態の確認

```bash
git remote -v
```

リモート設定の状態によって処理を分岐する。

---

**パターン A: origin が存在しない場合（Publicリポジトリからクローンした通常ケース）**

origin が設定されていない場合、切断確認は不要。新しいリポジトリの設定のみ行う。

```
リポジトリ接続を設定します。
```

AskUserQuestion で確認：
```
質問: プロジェクト用のリポジトリURLを設定しますか？

選択肢:
- 今すぐ入力する（推奨）
- 後で設定する（スキップ）
```

「今すぐ入力する」→ テキスト入力で URL を受け取り：
```bash
git remote add origin <入力されたURL>
```

初期プッシュの確認：
```
質問: リポジトリに初期プッシュしますか？

選択肢:
- はい、今すぐプッシュ
- いいえ、後で手動でプッシュ
```

「はい」の場合：
```bash
git push -u origin main
```

→ Step 2 へ進む

---

**パターン B: OrgOS-Dev リポジトリに接続中の場合（origin に `OrgOS-Dev` を含む）**

⚠️ 警告を表示：
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ OrgOS-Dev リポジトリに接続されています
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

このリポジトリは OrgOS の開発用リポジトリです。

■ 新しいプロジェクトを始める場合:
  → 切断して新しいリポジトリを設定します

■ OrgOS 自体を編集する場合:
  → /org-admin を使用してください
  ⚠️ OrgOS のコア機能を変更します。不要な場合は選択しないでください。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

AskUserQuestion で確認：
```
質問: どちらを行いますか？

選択肢:
- 切断して新しいプロジェクトを始める（推奨）
- キャンセル（OrgOS開発には /org-admin を使用）
```

**「キャンセル」の場合：**
- 「キャンセルしました。OrgOS開発には /org-admin を使用してください。」と表示
- **ここで処理終了**

**「切断して新しいプロジェクトを始める」の場合：**
```bash
git remote remove origin
```

新しいリポジトリURLを聞く（AskUserQuestion）：
```
質問: 新しいプロジェクトのリポジトリURLを入力してください

選択肢:
- 今すぐ入力する
- 後で設定する（スキップ）
```

「今すぐ入力する」→ テキスト入力で URL を受け取り：
```bash
git remote add origin <入力されたURL>
```

初期プッシュの確認：
```
質問: 新しいリポジトリに初期プッシュしますか？

選択肢:
- はい、今すぐプッシュ
- いいえ、後で手動でプッシュ
```

「はい」の場合：
```bash
git push -u origin main
```

→ Step 2 へ進む

---

**パターン C: 他のリポジトリに接続中の場合（OrgOS-Dev 以外）**

- 既存の接続を維持（切断確認不要）
- Step 2 へ進む

---

### Step 2: 既存データの退避

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

### Step 3: 台帳の初期化

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

### Step 4: BRIEF.md の確認

`.ai/BRIEF.md` を読み、以下を判定：

**BRIEF が未記入の場合（テンプレのまま or 空）：**
- DASHBOARD.md に「BRIEFを書いてください」と表示
- awaiting_owner: true を設定
- **ここで停止**（キックオフに進まない）

**BRIEF が記入済みの場合：**
- Step 5 に進む

### Step 5: キックオフ質問の生成

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

### Step 6: 状態の更新

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
