# OIP-006: ゴール階層管理・動的計画再構築機能

> Owner の依頼に応じてゴールを再構造化し、全体整合のある計画を維持する

---

## ステータス

- **提案日**: 2026-01-23
- **ステータス**: 提案中
- **提案者**: Owner
- **実装担当**: codex-implementer
- **関連タスク**: T-OS-006

---

## 背景・動機

### 現状の課題

現在の OrgOS は：
- **初期ゴールを固定的に扱う** - `BRIEF.md` / `PROJECT.md` で設定したゴールが最後まで変わらない前提
- **部分的な調整のみ** - タスクの追加/削除はできるが、ゴール自体の再構造化はできない
- **依頼の位置づけが不明確** - 新しい依頼が「既存ゴールの一部」なのか「新しいゴール」なのか判断しない

### 実際の使用例

```
ユーザーの最初の依頼: 「ジビエの販売をするECサイトを作りたい」
→ PROJECT.md に記録、タスクを分解して実装開始

作業を進めるうちに:
- 「投資家向けの資料も作りたい」← 新しいゴール？
- 「ブランドロゴも作りたい」← Vision が拡大？

真のゴール: 「ジビエブランドを立ち上げて世の中に発信する」
→ EC サイトは手段の1つにすぎなかった
→ しかし OrgOS は最初の「ECサイトを作る」に固執してしまう
```

**課題**: 新しい依頼を既存計画に無理やり押し込むのではなく、ゴールを再構造化して全体整合を保ちたい。

---

## 提案内容

### 1. **ゴール階層の導入**

```
Vision（大きなゴール）
  ↓ 何を達成したいか？
Milestone（中間ゴール）
  ↓ どういう段階で進めるか？
Project（プロジェクト）
  ↓ 具体的に何を作るか？
Task（タスク）
  ↓ 作業単位
```

### 2. **新しいファイル: `.ai/GOALS.yaml`**

```yaml
vision:
  id: V-001
  title: "ジビエブランドを立ち上げて世の中に発信する"
  status: active
  created_at: "2026-01-23"
  updated_at: "2026-01-23"

milestones:
  - id: M-001
    title: "ECサイトでジビエを販売開始"
    status: completed
    vision_id: V-001
    created_at: "2026-01-15"
    completed_at: "2026-01-20"

  - id: M-002
    title: "投資家向け資料を作成し資金調達"
    status: active
    vision_id: V-001
    created_at: "2026-01-21"
    deps: [M-001]

  - id: M-003
    title: "ブランディング戦略を策定"
    status: queued
    vision_id: V-001
    created_at: "2026-01-23"
    deps: [M-002]

projects:
  - id: P-001
    title: "ジビエECサイト構築"
    milestone_id: M-001
    status: completed

  - id: P-002
    title: "投資家向けピッチデッキ作成"
    milestone_id: M-002
    status: active

history:
  - date: "2026-01-21"
    type: "milestone_added"
    description: "M-002: 投資家向け資料を追加"
    reason: "Owner の依頼: 資金調達が必要になった"

  - date: "2026-01-23"
    type: "vision_expanded"
    old_vision: "ジビエECサイトを作る"
    new_vision: "ジビエブランドを立ち上げて世の中に発信する"
    reason: "ECサイトは手段であり、ブランド立ち上げが真のゴールと判明"
```

### 3. **依頼の位置づけ判断ロジック**

新しい依頼を受けたとき、Manager が以下を自動判断：

```
1. 既存 Vision に関連するか？
   → YES: Milestone または Project に追加
   → NO: 新しい Vision の可能性 → Owner に確認

2. 既存 Milestone に関連するか？
   → YES: Project または Task に追加
   → NO: 新しい Milestone の可能性 → Owner に確認

3. 既存 Project に関連するか？
   → YES: Task に追加
   → NO: 新しい Project として作成
```

**Owner に確認が必要な場合の提示例:**

```markdown
📌 新しい依頼の位置づけを確認させてください

依頼内容: 「投資家向け資料を作りたい」

判断:
- 既存の Vision「ジビエブランドを立ち上げる」に関連しますが、
  既存の Milestone「ECサイトで販売開始」とは異なる方向性です。

提案:
[A] 新しい Milestone として追加（推奨）
    → M-002「投資家向け資料を作成し資金調達」
    → Vision は変更なし

[B] Vision を拡大する
    → 「ECサイトを作る」→「ジビエブランド全体を立ち上げる」
    → M-001（EC）と M-002（資金調達）を並列に配置

[C] 別プロジェクトとして独立させる
    → 現在の Vision とは別のプロジェクトとして管理

どれにしますか？
```

### 4. **Milestone 達成時の確認**

Milestone が完了したとき、Owner に次のアクションを確認：

```markdown
✅ マイルストーン達成: ECサイトで販売開始

📊 全体の進捗:
   Vision: ジビエブランドを立ち上げて世の中に発信する
   [1] ✅ ECサイトで販売開始 → 達成（2026-01-20）
   [2] 🔄 投資家向け資料作成 → 進行中
   [3] ⏳ ブランディング戦略策定 → 未着手

📌 次のステップ:

[A] このまま次のマイルストーン「投資家向け資料作成」に進む（推奨）
    → すでにタスクがあるので続行

[B] 全体計画を見直す
    → Vision や Milestone を再設定します

どちらにしますか？
```

### 5. **定期的な見直し提案**

以下のタイミングで「ゴール見直し」を提案：

| タイミング | 提案内容 |
|------------|----------|
| **Milestone 達成時** | 次に進むか、計画を見直すか |
| **新規依頼が乖離** | 既存ゴールとの関連を確認 |
| **20タスク完了ごと** | 「全体計画は今のままでいいですか？」 |
| **Owner の明示的依頼** | いつでも見直し可能 |

### 6. **計画の再構築**

ゴールが変わったら：

1. **既存の作業を新しいゴール構造に位置づけ直す**
   - 完了した Project → 達成済み Milestone として記録
   - 進行中の Task → 新しい Milestone/Project に再配置

2. **新しいゴール構造で計画を立て直す**
   - `GOALS.yaml` を更新
   - `PROJECT.md` を更新（Vision/Milestone を反映）
   - `TASKS.yaml` に新規タスクを追加

3. **変更を記録**
   - `DECISIONS.md` に「ゴール変更の理由」を記録
   - `GOALS.yaml` の history に追加

---

## 実装詳細

### 変更ファイル一覧

| ファイル | 変更内容 |
|----------|----------|
| `.ai/GOALS.yaml` | **新規作成** - ゴール階層を管理 |
| `CLAUDE.md` | **追加** - ゴール管理フローのルールを追加 |
| `.claude/commands/org-start.md` | **変更** - GOALS.yaml 初期化ロジックを追加 |
| `.claude/commands/org-tick.md` | **変更** - ゴール達成確認・見直し提案ロジックを追加 |
| `.claude/commands/org-goals.md` | **新規作成** - ゴール可視化・編集コマンド |
| `.claude/commands/org-brief.md` | **変更** - Vision 抽出ロジックを追加 |
| `.ai/DASHBOARD.md` | **変更** - Vision/Milestone 表示を追加 |
| `.ai/PROJECT.md.template` | **変更** - Vision/Milestone セクションを追加 |

### 新規コマンド: `/org-goals`

```markdown
# /org-goals

ゴール階層を可視化・編集するコマンド

## 使い方

- `/org-goals` - 現在のゴール階層を表示
- `/org-goals add milestone` - 新しい Milestone を追加
- `/org-goals expand vision` - Vision を拡大（対話形式）
- `/org-goals review` - 全体計画の見直しを提案

## 出力例

```
📊 現在のゴール階層

Vision: ジビエブランドを立ち上げて世の中に発信する
  ↓
Milestone:
  [1] ✅ M-001: ECサイトで販売開始（2026-01-20 完了）
  [2] 🔄 M-002: 投資家向け資料作成（進行中）
  [3] ⏳ M-003: ブランディング戦略策定（未着手）
  ↓
Project:
  - P-001: ジビエECサイト構築 → M-001
  - P-002: 投資家向けピッチデッキ作成 → M-002
  ↓
Task: 全15タスク（完了: 10, 進行中: 3, 未着手: 2）
```
```

### GOALS.yaml と PROJECT.md の関係

- **GOALS.yaml**: 構造化されたデータ（Vision/Milestone/Project の関係）
- **PROJECT.md**: 人間が読む詳細ドキュメント（Vision を冒頭に追記）

```markdown
# PROJECT.md（拡張後）

## Vision

ジビエブランドを立ち上げて世の中に発信する

## Milestones

1. ✅ ECサイトで販売開始（2026-01-20 完了）
2. 🔄 投資家向け資料作成（進行中）
3. ⏳ ブランディング戦略策定（未着手）

## Project: 投資家向けピッチデッキ作成

（以下、従来の PROJECT.md の内容）
```

---

## メリット

### 1. **ゴールの柔軟な変更が可能**
- 最初の小さなゴールから大きなゴールへの拡大
- 新しい依頼を既存計画に統合
- 完了したゴールを明確に記録

### 2. **全体整合性の維持**
- Vision → Milestone → Project → Task の一貫性
- 依頼ごとに計画がバラバラにならない
- 「何のためにやっているか」が常に明確

### 3. **進捗の可視化**
- どの Milestone まで完了しているか
- 次に何をすべきか
- 全体の中での位置づけ

### 4. **Owner の判断を最小化**
- Manager が自動で位置づけを判断
- 本当に必要な時だけ Owner に確認
- AI ドリブン開発ルールに準拠

---

## デメリット・リスク

### 1. **複雑性の増加**
- ファイルが増える（GOALS.yaml 追加）
- Manager の判断ロジックが増える

**対策**:
- Owner は GOALS.yaml を直接編集する必要なし
- `/org-goals` で可視化・編集をサポート

### 2. **既存プロジェクトの移行**
- 既に進行中のプロジェクトをどう扱うか？

**対策**:
- `/org-start` 実行時に GOALS.yaml を自動生成
- BRIEF.md から Vision を抽出
- PROJECT.md から Milestone/Project を抽出

### 3. **学習コスト**
- Owner が新しい概念（Vision/Milestone）を理解する必要

**対策**:
- リテラシー適応ルールで説明を調整
- DASHBOARD.md で可視化してわかりやすく

---

## 実装優先度

**P1（高優先度）**

理由:
- Owner の実際のニーズから生まれた機能
- 計画の全体整合性を保つために重要
- 他の機能（スーパーバイザーレビュー、引き継ぎ）の基盤になる

---

## 実装スケジュール

| フェーズ | 内容 | 期間目安 |
|----------|------|----------|
| **Phase 1** | GOALS.yaml 設計・テンプレート作成 | 1日 |
| **Phase 2** | `/org-start` に統合（初期化ロジック） | 1日 |
| **Phase 3** | `/org-tick` に統合（達成確認・見直し提案） | 1日 |
| **Phase 4** | `/org-goals` コマンド作成 | 1日 |
| **Phase 5** | DASHBOARD.md / PROJECT.md 連携 | 1日 |
| **Phase 6** | テスト・ドキュメント整備 | 1日 |

**合計**: 約6日

---

## テスト計画

### テストケース

1. **新規プロジェクト作成**
   - `/org-start` で GOALS.yaml が自動生成される
   - BRIEF.md から Vision が抽出される

2. **Milestone 達成**
   - Milestone の全タスクが完了したら確認メッセージが出る
   - 次に進むか、見直すかを選べる

3. **新規依頼の位置づけ判断**
   - 既存ゴールに関連 → 自動でタスク追加
   - 乖離している → Owner に確認

4. **ゴール変更の記録**
   - GOALS.yaml の history に記録される
   - DECISIONS.md にも記録される

---

## 関連資料

- [CLAUDE.md](../../CLAUDE.md) - 全体計画の継続的更新（Plan Sync）
- [.claude/rules/ai-driven-development.md](../../.claude/rules/ai-driven-development.md) - AI ドリブン開発ルール
- [.claude/commands/org-tick.md](../../.claude/commands/org-tick.md) - Tick 処理

---

## 承認

- [ ] Owner 承認
- [ ] 実装完了
- [ ] テスト完了
- [ ] ドキュメント更新完了
