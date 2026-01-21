# OrgOS アーキテクチャ概要

> OrgOS の全体像を理解するためのドキュメント

---

## OrgOS とは

OrgOS は **Claude Code 上で動作するプロジェクト管理フレームワーク** です。

大規模な開発を、透明性を保ちながら、安全に、ステップごとに進めるための仕組みを提供します。

---

## 設計思想

### 1. 透明性（Transparency）

すべての決定・進捗・リスクは `.ai/` フォルダに記録される。
口頭だけで終わらせず、必ずファイルに残す。

### 2. 段階的進行（Staged Progression）

```
KICKOFF → REQUIREMENTS → DESIGN → IMPLEMENTATION → INTEGRATION → RELEASE
```

各ステージにゲートがあり、Owner の承認がないと次に進めない。

### 3. 役割分離（Separation of Concerns）

- 実装する人とレビューする人は別
- Manager（Claude）が全体を統括
- Worker（Codex/Claude subagent）がタスクを実行

### 4. 安全第一（Safety First）

- main ブランチは保護
- 危険な操作（push, deploy）は Owner 承認必須
- 機密情報（.env）は読まない

---

## アーキテクチャ図

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Owner (人間)                              │
│                                                                     │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐           │
│   │ BRIEF.md    │    │ OWNER_      │    │ CONTROL.yaml│           │
│   │ (要望を書く) │    │ COMMENTS.md │    │ (承認する)   │           │
│   └─────────────┘    └─────────────┘    └─────────────┘           │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Manager (Claude)                             │
│                                                                     │
│   ・全体制御（/org-tick）                                            │
│   ・台帳管理（TASKS.yaml, STATUS.md, DASHBOARD.md）                  │
│   ・質問生成（OWNER_INBOX.md）                                       │
│   ・Worker への委任                                                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
                ▼               ▼               ▼
┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
│  Claude Subagent  │ │  Claude Subagent  │ │   OpenAI Codex    │
│                   │ │                   │ │                   │
│  ・Planner        │ │  ・org-reviewer   │ │  ・Implementer    │
│  ・Architect      │ │  ・org-security-  │ │  ・Reviewer       │
│  ・Integrator     │ │    reviewer       │ │    (コード品質)    │
│  ・Scribe         │ │  (設計妥当性)      │ │                   │
└───────────────────┘ └───────────────────┘ └───────────────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          .ai/ (SSOT)                                │
│                                                                     │
│   PROJECT.md    TASKS.yaml    DECISIONS.md    STATUS.md             │
│   DASHBOARD.md  RISKS.md      RUN_LOG.md      CONTROL.yaml          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## コンポーネント

### Manager（Claude）

OrgOS の中核。以下を担当：
- 全体の進行管理（Tick）
- 台帳（SSOT）の更新
- Owner への質問生成
- Worker への作業委任
- ゲート管理

### Worker

タスクを実行するエージェント。Claude と Codex を使い分け：

| 役割 | エンジン | 担当 |
|------|----------|------|
| Planner | Claude | 要件整理、タスク分解 |
| Architect | Claude | 境界定義、Contract 設計 |
| Implementer | Codex | コード実装 |
| Reviewer（コード品質） | Codex | セキュリティ、堅牢性チェック |
| Reviewer（設計妥当性） | Claude | アーキテクチャ整合性 |
| Integrator | Claude | main への統合 |
| Scribe | Claude | 台帳整理、記録 |

### SSOT（Single Source of Truth）

`.ai/` フォルダに集約される情報：

| ファイル | 内容 |
|----------|------|
| `BRIEF.md` | Owner が書くプロジェクト概要 |
| `PROJECT.md` | 正式な要件・仕様 |
| `TASKS.yaml` | タスク管理（DAG） |
| `DECISIONS.md` | 設計判断の記録 |
| `RISKS.md` | リスク管理 |
| `STATUS.md` | 現在の状態 |
| `DASHBOARD.md` | Owner 向けサマリー |
| `CONTROL.yaml` | ゲート・フラグ管理 |
| `OWNER_INBOX.md` | Manager からの質問 |
| `OWNER_COMMENTS.md` | Owner の回答 |

---

## 進行フロー（Tick）

1回の進行単位を「Tick」と呼ぶ。

```
/org-tick 実行
    │
    ├─ 1. CONTROL.yaml と台帳を読む
    │
    ├─ 2. 未決事項・ブロッカーがあれば OWNER_INBOX に質問
    │
    ├─ 3. 進められるタスクがあれば Worker に委任
    │      ├─ 並列実行可能なタスクは同時に実行
    │      └─ 結果は .ai/CODEX/RESULTS/ に出力
    │
    ├─ 4. 結果を台帳に反映
    │
    └─ 5. DASHBOARD.md を更新
```

---

## ステージとゲート

```
┌──────────┐   ┌──────────────┐   ┌────────┐   ┌────────────────┐   ┌───────────┐   ┌─────────┐
│ KICKOFF  │──▶│ REQUIREMENTS │──▶│ DESIGN │──▶│ IMPLEMENTATION │──▶│INTEGRATION│──▶│ RELEASE │
└──────────┘   └──────────────┘   └────────┘   └────────────────┘   └───────────┘   └─────────┘
      │               │                │                │                 │               │
      ▼               ▼                ▼                ▼                 ▼               ▼
   kickoff        requirements      design          (なし)          integration      release
   _complete      _approved         _approved                        _approved       _approved
```

各ゲートで Owner の承認が必要。

---

## 技術ガイダンス

### Skills（技術知識ベース）

| ファイル | 内容 |
|----------|------|
| `coding-standards.md` | コーディング規約 |
| `backend-patterns.md` | バックエンドパターン |
| `frontend-patterns.md` | フロントエンドパターン |
| `tdd-workflow.md` | TDD ワークフロー |

### Rules（品質基準）

| ファイル | 内容 |
|----------|------|
| `security.md` | セキュリティルール（OWASP Top 10） |
| `testing.md` | テストルール（80% カバレッジ） |
| `review-criteria.md` | レビュー基準 |
| `patterns.md` | 共通パターン |

---

## Claude と Codex の使い分け

### Claude を選ぶ場面
- 既存の大規模プロジェクトの構造理解
- 仕様書や複数ファイルをまたいだリファクタリング
- 設計の妥当性判断

### Codex を選ぶ場面
- 難解なロジックの実装
- 新しいライブラリを使った新規開発
- コードの堅牢性（エラーハンドリング、セキュリティ）重視

---

## ディレクトリ構造

```
.
├── .ai/                      # SSOT（台帳）
│   ├── BRIEF.md              # プロジェクト概要（Owner が書く）
│   ├── PROJECT.md            # 正式な要件・仕様
│   ├── TASKS.yaml            # タスク管理
│   ├── DECISIONS.md          # 設計判断
│   ├── RISKS.md              # リスク管理
│   ├── STATUS.md             # 現在の状態
│   ├── DASHBOARD.md          # Owner 向けサマリー
│   ├── CONTROL.yaml          # ゲート・フラグ
│   ├── OWNER_INBOX.md        # Manager からの質問
│   ├── OWNER_COMMENTS.md     # Owner の回答
│   ├── CODEX/                # Codex I/O
│   │   ├── ORDERS/           # Work Order
│   │   └── RESULTS/          # 実行結果
│   ├── REVIEW/               # レビュー関連
│   │   └── PACKETS/          # Review Packet
│   └── LEARNINGS/            # 学習記録
│
├── .claude/                  # Claude Code 設定
│   ├── commands/             # スラッシュコマンド
│   ├── agents/               # Subagent 定義
│   ├── hooks/                # フック処理
│   ├── skills/               # 技術知識ベース
│   ├── rules/                # 品質基準
│   └── scripts/              # ユーティリティ
│
├── CLAUDE.md                 # Manager の振る舞い定義
├── AGENTS.md                 # Worker のルール
├── ORGOS_QUICKSTART.md       # クイックスタート
└── requirements.md           # OrgOS 仕様書
```

---

## 参考資料

- [ORGOS_QUICKSTART.md](ORGOS_QUICKSTART.md) - 使い始めガイド
- [CLAUDE.md](CLAUDE.md) - Manager の振る舞い
- [AGENTS.md](AGENTS.md) - Worker のルール
- [requirements.md](requirements.md) - OrgOS 仕様書
