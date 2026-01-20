# OrgOS

Claude Code で大規模開発を安全に進めるためのフレームワーク。

## 特徴

- **透明性**: すべての決定・進捗を `.ai/` フォルダに記録
- **安全性**: 危険な操作（push, deploy等）はOwner承認が必要
- **並列開発**: タスクをDAGで管理し、依存関係を明確化
- **レビュー分離**: 実装者とレビュアーを分離

## クイックスタート

### 方法1: git clone（推奨）

```bash
# リポジトリをクローン
git clone https://github.com/Yokotani-Dev/OrgOS.git my-project
cd my-project

# OrgOS-Devからリポジトリを切断し、自分のリポジトリに接続
git remote remove origin
git remote add origin <YOUR_REPO_URL>

# Claude Code を起動
claude

# OrgOSを初期化
/org-start
```

### 方法2: 既存プロジェクトにインポート

```bash
# プロジェクトディレクトリで
claude

# OrgOSをインポート
/org-import latest
```

## 初期セットアップ

1. **BRIEF.md を記入**
   - `.ai/BRIEF.md` にプロジェクト概要を記入
   - 作りたいもの、マスト要件、NG事項を書く
   - 分からない項目は「TBD」でOK

2. **`/org-start` を実行**
   - プロジェクト初期化とキックオフ質問が生成される

3. **質問に回答**
   - `.ai/OWNER_INBOX.md` の質問を確認
   - `.ai/OWNER_COMMENTS.md` に回答を記入
   - `/org-tick` で進行

## 主なコマンド

| コマンド | 説明 |
|----------|------|
| `/org-start` | プロジェクト初期化 |
| `/org-brief` | 対話形式でBRIEF.mdを作成 |
| `/org-kickoff` | キックオフ質問を生成 |
| `/org-plan` | 要件→設計→タスクDAGを作成 |
| `/org-tick` | 1Tick進行（台帳更新→タスク分配→レビュー→次の手） |
| `/org-review` | Review Packet + diff を用いたレビュー |
| `/org-integrate` | マージ順制御してmainへ統合 |

## ファイル構成

```
.ai/
  BRIEF.md          <- プロジェクト概要（Ownerが記入）
  PROJECT.md        <- Managerが生成・更新
  OWNER_INBOX.md    <- Managerからの質問
  OWNER_COMMENTS.md <- Ownerの回答・指示
  DASHBOARD.md      <- プロジェクト状況の1枚絵
  CONTROL.yaml      <- ゲート制御
  TASKS.yaml        <- タスク管理
  RESOURCES/        <- 参照資料格納

.claude/
  commands/         <- OrgOSコマンド定義
  agents/           <- エージェント定義

CLAUDE.md           <- Claude Codeへの指示
```

## ドキュメント

- [ORGOS_QUICKSTART.md](ORGOS_QUICKSTART.md) - 詳細なクイックスタートガイド
- [CLAUDE.md](CLAUDE.md) - OrgOSの動作原則
- [AGENTS.md](AGENTS.md) - エージェント一覧

## ライセンス

MIT
