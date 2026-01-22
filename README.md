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
# リポジトリをクローン（最後の引数でフォルダ名を指定）
git clone https://github.com/Yokotani-Dev/OrgOS.git my-project
cd my-project

# Claude Code を起動
claude

# OrgOSを初期化（対話形式でプロジェクト概要をヒアリング）
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

1. **`/org-start` を実行**
   - 対話形式でプロジェクト概要をヒアリング
   - `.ai/BRIEF.md` が自動生成される
   - キックオフ質問が生成される

2. **質問に回答**
   - `.ai/OWNER_INBOX.md` の質問を確認
   - `.ai/OWNER_COMMENTS.md` に回答を記入
   - `/org-tick` で進行

## コマンド一覧

```
基本フロー
  /org-start     プロジェクト起動（初期化 or 再開）
  /org-brief     BRIEF.md を対話形式で整形
  /org-kickoff   キックオフ質問を生成
  /org-tick      進行を1Tick進める（最もよく使う）

計画・設計
  /org-plan      要件/設計/Contract/タスクDAG を作成

実装・レビュー
  /org-codex     Codex タスクを実行
  /org-review    Review Packet + diff でレビュー

統合・リリース
  /org-integrate main へ統合
  /org-release   リリース実行

学習・振り返り
  /org-learn     セッションから学習を抽出
  /org-os-retro  OrgOS 自体の振り返り・改善提案

管理（開発者向け）
  /org-admin     管理者モード有効化
  /org-export    リリースフロー案内
  /org-import    OrgOS をインポート
  /org-publish   公開リポジトリへ同期
```

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
