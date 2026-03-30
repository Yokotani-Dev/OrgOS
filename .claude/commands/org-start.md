---
description: OrgOSプロジェクト起動（初期化→キックオフ→質問提示まで自動実行）
---

# /org-start - プロジェクト起動コマンド

このコマンドは **新規プロジェクト開始** または **既存プロジェクトの再開** に使用する。
実行時に `.ai/` フォルダの状態を自動判定し、適切なフローを実行する。

---

## フロー判定ロジック（Step 0）

`/org-start` 実行時、最初に以下を確認する：

### 判定基準

```
.ai/ フォルダが存在しない
  → 新規プロジェクト（フローA）

.ai/CONTROL.yaml が存在しない
  → 新規プロジェクト（フローA）

.ai/CONTROL.yaml に is_orgos_dev: true がある
  → OrgOS開発用台帳（フローC: 特別処理）

.ai/CONTROL.yaml の stage が "KICKOFF" 以外（REQUIREMENTS, DESIGN, IMPLEMENTATION, INTEGRATION, RELEASE）
  → 既存プロジェクト再開（フローB）

.ai/TASKS.yaml に status: in_progress または status: done のタスクがある
  → 既存プロジェクト再開（フローB）

.ai/PROJECT.md が記入済み（テンプレートではない）
  → 既存プロジェクト再開（フローB）

上記いずれにも該当しない
  → 新規プロジェクト（フローA）
```

### 判定結果の通知

**フローB（再開）と判定された場合:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 既存の OrgOS プロジェクトを検出しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Stage: <現在のステージ>
タスク: <完了数>/<総数> 完了
最終更新: <RUN_LOG の最新日時>
```

AskUserQuestion で確認：
```
質問: どちらを行いますか？

選択肢:
- 作業を再開する（推奨）
- 新規プロジェクトとして初期化する（既存データは退避）
```

**「作業を再開する」の場合 → フローB へ**
**「新規プロジェクトとして初期化する」の場合 → フローA へ**

---

**フローC（OrgOS開発用台帳）と判定された場合:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ OrgOS 開発用の台帳が検出されました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

この .ai/ フォルダは OrgOS 自体の開発用です。
新しいプロジェクトを始める場合は初期化が必要です。
```

AskUserQuestion で確認：
```
質問: どちらを行いますか？

選択肢:
- 新規プロジェクトとして初期化する（推奨）
- OrgOS開発を続ける（/org-admin を使用してください）
```

**「新規プロジェクトとして初期化する」の場合:**
- `.ai/TEMPLATES/` からテンプレートを展開して初期化
- 既存の開発用台帳は `.ai/_archive/` に退避
- → フローA へ

**「OrgOS開発を続ける」の場合:**
- 「OrgOS開発には `/org-admin` を使用してください」と表示
- **ここで処理終了**

---

## フローB: 既存プロジェクトの再開

既存プロジェクトを再開する場合、以下を実行する：

### Step B-1: 台帳の読み込み

以下のファイルを読み込んで状況を把握：

```
.ai/CONTROL.yaml     # 現在のステージ、ゲート状態
.ai/TASKS.yaml       # タスク状況
.ai/STATUS.md        # 進捗サマリ
.ai/RUN_LOG.md       # 最近の活動
.ai/OWNER_INBOX.md   # 未回答の質問
.ai/OWNER_COMMENTS.md # Owner の最新コメント
.ai/DECISIONS.md     # 決定事項
.ai/RISKS.md         # リスク
```

### Step B-2: 状況サマリの生成

DASHBOARD.md を以下のフォーマットで更新：

```markdown
# DASHBOARD

## 🚦 Now

| 項目 | 状態 |
|------|------|
| Stage | **<現在のステージ>** |
| Awaiting Owner | <YES/NO> |
| Paused | <YES/NO> |

## 📍 再開ポイント

**前回の状態:**
<RUN_LOG から最新 3-5 件の活動を表示>

**未完了タスク:**
<in_progress または queued のタスク一覧>

**未回答の質問:**
<OWNER_INBOX に回答待ちの質問があれば表示>

## 📋 Next Action (Owner)

<ステージに応じた次のアクションを案内>
```

### Step B-3: 次のアクションの案内

ステージに応じて適切な案内を表示：

| ステージ | 次のアクション |
|---------|---------------|
| KICKOFF | `/org-tick` または OWNER_INBOX への回答 |
| REQUIREMENTS | `/org-tick` で要件確定へ |
| DESIGN | `/org-tick` で設計レビュー |
| IMPLEMENTATION | `/org-tick` でタスク進行 |
| INTEGRATION | `/org-tick` で統合作業 |
| RELEASE | `/org-release` でリリース |

### Step B-4: 完了メッセージ

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ プロジェクトを再開しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 次はこちら: /org-tick
   <状況に応じた具体的な説明>
```

---

## フローA: 新規プロジェクトの開始

新規プロジェクトを開始する場合、以下を自動で行う：
1. リポジトリ状態の確認（OrgOS-Dev接続時は警告・切断）
2. `.ai/` の初期化（既存データは退避）
3. **対話形式でBRIEF.mdを作成**（ヒアリング）
4. キックオフ質問の生成
5. DASHBOARD の更新

---

## 実行手順

### Step 1: リポジトリ状態の確認

```bash
git remote -v
```

リモート設定の状態によって処理を分岐する。

| パターン | 条件 | 処理 |
|----------|------|------|
| A | origin が存在しない | 新しいリポジトリ設定を案内 |
| B | origin が OrgOS リポジトリ（`/OrgOS` を含む） | **自動切断** + 新しいリポジトリ設定 |
| C | origin が OrgOS 以外のリポジトリ | 維持して続行 |

---

**パターン A: origin が存在しない場合**

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

**パターン B: OrgOS リポジトリに接続中の場合（公開版 or 開発版）**

origin に OrgOS 関連の URL が含まれる場合（`/OrgOS` を含む）、自動で切断する。

```bash
# OrgOS リポジトリ判定
origin_url=$(git remote get-url origin 2>/dev/null)
is_orgos_repo=$(echo "$origin_url" | grep -i '/OrgOS')

if [ -n "$is_orgos_repo" ]; then
  # OrgOS リポジトリ → 自動切断
fi
```

**自動切断を実行：**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OrgOS リポジトリとの接続を解除しました
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OrgOS のテンプレートリポジトリから clone されたため、
元のリポジトリとの接続を自動で解除しました。

新しいプロジェクト用のリポジトリを設定してください。
```

```bash
git remote remove origin
```

新しいリポジトリURLを聞く（AskUserQuestion）：
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

**パターン C: 他のリポジトリに接続中の場合（OrgOS 以外）**

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
  CONTROL.yaml      # stage: KICKOFF, is_orgos_dev: false, allow_*: false, awaiting_owner: false
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

### Step 4: 対話形式でBRIEF.mdを作成（ヒアリング）

`.ai/BRIEF.md` を確認し、対話形式でプロジェクト概要を収集する。

---

#### Step 4-0: ITリテラシーレベルの確認（OrgOS開発以外の場合）

**OrgOS開発（is_orgos_dev: true）の場合はスキップ。**

プロジェクト開始時に、Owner の IT リテラシーレベルを確認し、以後の説明スタイルを調整する。

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👋 ようこそ！まず1つだけ教えてください
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

この後の説明をあなたに合わせて調整したいので、
普段のITとの関わり方を教えてください。
```

AskUserQuestion で確認：
```
質問: 普段のITとの関わり方を教えてください

選択肢:
- やさしく説明してほしい（専門用語は苦手）
  → ITツールは使うけど、仕組みには詳しくない
- ふつうでOK
  → 基本的なIT用語は分かる、たまにググる程度
- 専門用語でOK（エンジニア・開発者向け）
  → プログラミングやシステム開発の経験がある
```

**回答に応じて CONTROL.yaml の `owner_literacy_level` を設定：**
- 「やさしく説明してほしい」→ `beginner`
- 「ふつうでOK」→ `intermediate`
- 「専門用語でOK」→ `advanced`

設定後、以下の確認メッセージを表示：

**beginner の場合：**
```
了解しました！
専門用語はできるだけ使わず、分かりやすく説明しますね。
分からないことがあったら、いつでも聞いてください。
```

**intermediate の場合：**
```
了解しました！
基本的なIT用語を使いつつ、必要に応じて補足を入れますね。
```

**advanced の場合：**
```
了解。技術的な説明もそのまま使います。
```

---

#### Step 4-0b: レビュー頻度の選択

**OrgOS開発（is_orgos_dev: true）の場合はスキップ。**

タスク完了時のレビュー頻度を選択してもらう。

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 レビュー頻度の設定
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

タスクが完了したとき、どのくらいの頻度で確認しますか？
後から /org-settings で変更できます。
```

AskUserQuestion で確認：
```
質問: レビューの頻度を選んでください

選択肢:
- タスクごとに確認（初心者におすすめ）
  → 各タスク完了時に結果を確認します
- 数タスクごとに確認（推奨）
  → 3タスクごとにまとめて確認（後で調整可能）
- 最後にまとめて確認（一括）
  → 全タスク完了後に一度だけ確認します
- 自分から依頼するまで確認しない（手動）
  → 最大限の自動進行、必要なときだけ確認依頼
```

**回答に応じて CONTROL.yaml の `owner_review_policy` を設定：**
- 「タスクごとに確認」→ `mode: "every_tick"`
- 「数タスクごとに確認」→ `mode: "every_n_tasks"`, `every_n_tasks: 3`
- 「最後にまとめて確認」→ `mode: "batch"`
- 「自分から依頼するまで確認しない」→ `mode: "manual"`

設定後、以下の確認メッセージを表示：

**every_tick の場合：**
```
了解しました！
タスクが完了するたびに確認をお願いします。
```

**every_n_tasks の場合：**
```
了解しました！
3タスクごとにまとめて確認します。
頻度は /org-settings で変更できます。
```

**batch の場合：**
```
了解しました！
全タスクが完了したら、まとめて確認をお願いします。
途中で確認したい場合は「レビューして」と伝えてください。
```

**manual の場合：**
```
了解しました！
確認が必要なときは「レビューして」と伝えてください。
それ以外は自動で進めます。
```

---

#### Step 4-1〜4-6: BRIEF.md の作成（/org-brief に委任）

**ヒアリングロジックは `/org-brief` に一元化されている。**

ここでは `/org-brief` の全フロー（Step 1〜6）を内部実行する：
1. オープンクエスチョン（何を作りたいか）
2. 入力内容の分析
3. コンテキストに応じた質問生成
4. 追加ヒアリング（必要に応じて）
5. BRIEF.md の生成
6. 確認と修正受付

詳細は [/org-brief](.claude/commands/org-brief.md) を参照。

**「このまま進める」が選択されたら Step 4-9 に進む。**

---

#### Step 4-9: GOALS.yaml の初期化

BRIEF.md の内容から Vision を抽出し、`.ai/GOALS.yaml` を初期化する。

**Vision の抽出ロジック:**
1. BRIEF.md の「作りたいもの」セクションを読む
2. 最も大きなゴール（何を達成したいか）を Vision として抽出
3. 具体的な成果物（ECサイト、APIなど）は Project として記録

**例:**
- BRIEF.md: 「ジビエのECサイトを作る」
  - Vision: 「ジビエをオンラインで販売できるようにする」
  - Project: 「ジビエECサイト構築」

- BRIEF.md: 「社内の勤怠管理ツールを作る」
  - Vision: 「勤怠管理を効率化する」
  - Project: 「社内勤怠管理ツール開発」

**GOALS.yaml の初期内容:**
```yaml
vision:
  id: V-001
  title: "<抽出した Vision>"
  status: active
  created_at: "<TIMESTAMP>"
  updated_at: "<TIMESTAMP>"

milestones:
  - id: M-001
    title: "<BRIEF.md のタイトルまたは抽出した中間ゴール>"
    status: active
    vision_id: V-001
    created_at: "<TIMESTAMP>"
    deps: []

projects:
  - id: P-001
    title: "<BRIEF.md のタイトル>"
    milestone_id: M-001
    status: active
    created_at: "<TIMESTAMP>"

history:
  - date: "<TIMESTAMP>"
    type: "vision_created"
    description: "初期ビジョン設定"
    reason: "/org-start による初期化"
```

---

#### Step 4-10: スーパーバイザーレビュー設定

**作業者と上司レビュー要否を質問します。**

質問内容:

```
📋 作業者とレビュー設定

このプロジェクトを進めるのは誰ですか？

[A] 自分（デフォルト）
    → 自分で判断し、進めます

[B] 部下
    → 部下が作業し、上司（あなた）がレビューします

どちらですか？
```

**[A] 自分 を選択した場合:**

続けて質問:

```
上司レビューが必要ですか？

[A] 必要なし（デフォルト）
    → 自分で全て判断します

[B] 重要な判断時のみリマインド
    → 重要な判断時に「上司に確認してください」と通知
    → ただし、上司の承認なしでも進められます

どちらですか？
```

- [A] → `supervisor_review.enabled: false`, `mode: "self_only"`
- [B] → `supervisor_review.enabled: true`, `mode: "self_with_reminder"`, `worker: "self"`

**[B] 部下 を選択した場合:**

上司（スーパーバイザー）情報を質問:

```
上司の情報を入力してください（任意）:

- 名前:
- 役職:
- 連絡先（メール/Slackなど）:
```

設定:
- `supervisor_review.enabled: true`
- `mode: "subordinate_with_supervisor"`
- `worker: "subordinate"`
- `supervisor.name/role/contact` を設定

**CONTROL.yaml への反映:**

```yaml
supervisor_review:
  enabled: true | false
  mode: "self_only" | "self_with_reminder" | "subordinate_with_supervisor"
  worker: "self" | "subordinate"
  supervisor:
    name: "<入力された名前>"
    role: "<入力された役職>"
    contact: "<入力された連絡先>"
```

---

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
