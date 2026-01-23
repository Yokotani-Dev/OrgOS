---
description: ゴール階層の表示・編集・見直し
---

# /org-goals - ゴール階層管理コマンド

`.ai/GOALS.yaml` のゴール階層を表示・編集・見直しするコマンド。

---

## 使い方

### 基本形

```
/org-goals          # 現在のゴール階層を表示
```

### サブコマンド

```
/org-goals add milestone      # 新しい Milestone を追加
/org-goals expand vision      # Vision を拡大（対話形式）
/org-goals review             # 全体計画の見直しを提案
/org-goals history            # ゴール変更履歴を表示
```

---

## 実行フロー

### 1. GOALS.yaml の存在確認

`.ai/GOALS.yaml` が存在しない場合：

```
⚠️ GOALS.yaml が見つかりません

/org-start を実行してプロジェクトを初期化してください。
```

→ 処理終了

---

### 2. サブコマンドによる分岐

#### サブコマンドなし（デフォルト）

ゴール階層を可視化して表示：

```markdown
📊 現在のゴール階層

Vision: <Vision Title> (V-001)
  ↓
Milestones:
  [1] ✅ M-001: <Milestone 1 Title>（<完了日> 完了）
  [2] 🔄 M-002: <Milestone 2 Title>（進行中）
      └─ Progress: 5/10 タスク完了
  [3] ⏳ M-003: <Milestone 3 Title>（未着手）
  ↓
Projects:
  - P-001: <Project 1 Title> → M-001
  - P-002: <Project 2 Title> → M-002
  ↓
Tasks: 全 <N> タスク（完了: <X>, 進行中: <Y>, 未着手: <Z>）

---

📌 次のアクション:

- ゴール階層を編集: /org-goals add milestone
- Vision を拡大: /org-goals expand vision
- 全体計画を見直す: /org-goals review
```

#### `/org-goals add milestone`

新しい Milestone を追加（対話形式）

**Step 1: タイトル入力**

```
新しい Milestone のタイトルを入力してください:

例：
- 投資家向け資料を作成し資金調達
- ブランディング戦略を策定
- β版をリリース
```

テキスト入力で Milestone タイトルを受け取る。

**Step 2: Vision との関連確認**

```
この Milestone は現在の Vision「<Vision Title>」に関連しますか？

[A] はい、関連します（推奨）
    → 現在の Vision の下に Milestone を追加

[B] いいえ、新しい Vision です
    → Vision を拡大するか、新しいプロジェクトとして独立させます
```

**[A] を選択した場合:**

- GOALS.yaml に新しい Milestone を追加
- DECISIONS.md に記録
- DASHBOARD.md を更新

```yaml
milestones:
  - id: M-00X
    title: "<入力されたタイトル>"
    status: queued
    vision_id: V-001
    created_at: "<TIMESTAMP>"
    deps: []  # 依存する Milestone があれば追加
```

**Step 3: 依存関係の確認**

```
この Milestone は他の Milestone の完了後に開始しますか？

[A] いいえ、すぐに開始できます（推奨）
    → 依存関係なし

[B] はい、他の Milestone の完了が必要です
    → 依存する Milestone を選択してください
```

**[B] を選択した場合:**

```
依存する Milestone を選択してください:

- M-001: <Milestone 1 Title>
- M-002: <Milestone 2 Title>

（複数選択可）
```

選択された Milestone を `deps` に追加。

**Step 4: 確認**

```
✅ 新しい Milestone を追加しました

M-00X: <タイトル>
  - Vision: <Vision Title>
  - 依存: <deps>
  - 状態: queued

GOALS.yaml を更新しました。

📌 次のアクション:

この Milestone のタスクを作成するには:
→ OWNER_COMMENTS.md に「<Milestone Title> のタスクを作成」と記入
→ /org-tick を実行
```

**[B] を選択した場合（新しい Vision）:**

→ `/org-goals expand vision` を実行

---

#### `/org-goals expand vision`

Vision を拡大（対話形式）

**Step 1: 現在の Vision 確認**

```
現在の Vision: <Current Vision Title>

Vision を拡大しますか？

例：
- 「ECサイトを作る」→「ジビエブランド全体を立ち上げる」
- 「勤怠管理ツール」→「社内業務全体を効率化する」
```

**Step 2: 新しい Vision 入力**

```
新しい Vision を入力してください:
```

テキスト入力で新しい Vision を受け取る。

**Step 3: 既存 Milestone の扱い確認**

```
既存の Milestone は新しい Vision の一部として扱いますか？

既存 Milestones:
- M-001: <Milestone 1>
- M-002: <Milestone 2>

[A] はい、すべて新しい Vision に含めます（推奨）
    → Vision を拡大し、既存 Milestone を維持

[B] 一部のみ含めます
    → 含める Milestone を選択してください

[C] いいえ、別プロジェクトとして分離します
    → 新しい GOALS.yaml を作成（既存は _archive に退避）
```

**[A] を選択した場合:**

- GOALS.yaml の vision.title を更新
- history に記録
- DECISIONS.md に記録

```yaml
vision:
  id: V-001
  title: "<新しい Vision>"
  status: active
  updated_at: "<TIMESTAMP>"

history:
  - date: "<TIMESTAMP>"
    type: "vision_expanded"
    old_vision: "<Current Vision>"
    new_vision: "<新しい Vision>"
    reason: "<理由>"
```

**Step 4: 確認**

```
✅ Vision を拡大しました

旧 Vision: <Current Vision>
新 Vision: <新しい Vision>

既存の Milestone はすべて新しい Vision の一部として継続します。

GOALS.yaml / DECISIONS.md を更新しました。

📌 次のアクション:

- ゴール階層を確認: /org-goals
- 新しい Milestone を追加: /org-goals add milestone
```

---

#### `/org-goals review`

全体計画の見直しを提案（対話形式）

**Step 1: 現在の状況を表示**

```
📊 全体計画の見直し

Vision: <Vision Title>

Milestones:
  [1] ✅ M-001: <Milestone 1>（完了）
  [2] 🔄 M-002: <Milestone 2>（進行中 - 5/10 タスク完了）
  [3] ⏳ M-003: <Milestone 3>（未着手）

進捗: <X>/<Total> タスク完了
```

**Step 2: 見直しが必要な項目を提案**

以下をチェックして提案：

1. **完了した Milestone**
   - 次の Milestone に進めるか確認

2. **進行中の Milestone が複数ある**
   - 優先順位を確認

3. **未着手の Milestone が多い**
   - スコープを絞るべきか確認

4. **新しい要件が追加された**
   - Milestone に反映されているか確認

**例:**

```
📌 見直し提案:

1. ✅ M-001 が完了しました
   → 次の M-002 に進めますか？それとも追加作業がありますか？

2. ⏳ M-003, M-004, M-005 が未着手です
   → すべて必要ですか？優先順位を見直しますか？

[A] 特に変更なし、このまま進める（推奨）
[B] Milestone を追加したい
[C] Milestone を削除または延期したい
[D] Vision を見直したい
```

**回答に応じて対応:**

- [A] → 見直し日時を記録して終了
- [B] → `/org-goals add milestone` を実行
- [C] → Milestone 削除・延期の対話を開始
- [D] → `/org-goals expand vision` を実行

---

#### `/org-goals history`

ゴール変更履歴を表示

```markdown
📜 ゴール変更履歴

---

2026-01-23 14:30 - Vision 拡大
- 旧: 「ECサイトを作る」
- 新: 「ジビエブランド全体を立ち上げる」
- 理由: ECサイトは手段であり、ブランド立ち上げが真のゴールと判明

---

2026-01-21 10:15 - Milestone 追加
- M-002: 投資家向け資料を作成し資金調達
- 理由: Owner の依頼: 資金調達が必要になった

---

2026-01-15 09:00 - Vision 作成
- V-001: 「ECサイトを作る」
- 理由: /org-start による初期化

---

📌 次のアクション:

- ゴール階層を確認: /org-goals
- 新しい変更を加える: /org-goals add milestone
```

---

## リテラシー適応

CONTROL.yaml の `owner_literacy_level` に応じて説明を調整：

### beginner の場合

```
📊 現在のゴール階層

**Vision**（大きなゴール）: <Vision Title>
  ↓
**Milestones**（中間ゴール）:
  [1] ✅ M-001: <Milestone 1>（完了しました）
  [2] 🔄 M-002: <Milestone 2>（今ここ - 進行中）
  [3] ⏳ M-003: <Milestone 3>（未着手）
  ↓
**Projects**（具体的な成果物）:
  - P-001: <Project 1>
  - P-002: <Project 2>
  ↓
**Tasks**（作業単位）: 全 <N> 個
```

### advanced の場合

```
📊 Goal Hierarchy

Vision (V-001): <Vision Title>
  Milestones: 3 total (1 completed, 1 active, 1 queued)
  Projects: 2 total
  Tasks: <N> total (<X> done, <Y> in progress, <Z> queued)
```

---

## 参考資料

- [CLAUDE.md](../../CLAUDE.md) - ゴール階層管理セクション
- [.ai/OIP/OIP-006-goal-hierarchy-management.md](../../.ai/OIP/OIP-006-goal-hierarchy-management.md) - 詳細仕様
