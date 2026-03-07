# OrgOS WebConsole 変更履歴

このファイルは OrgOS WebConsole の各バージョンで何が変わったかを記録します。

---

## OrgOS v0.19.1 (2026-03-06)

### 修正

- **Manager 委任ルール強化**: 小タスクでも必ず TASKS.yaml に記録し、Codex CLI に委任するよう変更
- **Codex CLI パス明記**: `/opt/homebrew/bin/codex` のフルパスを CLAUDE.md に記載し、「見つからない」誤認を防止
- **Manager 実装禁止**: `.ai/` 以外のソースコードを Manager が直接 Edit/Write することを例外なく禁止

---

## v0.1.0 (2026-01-23)

### 初回リリース - MVP

複数の OrgOS プロジェクトを Web ブラウザから一元管理するコンソールの初回リリースです。

### 機能

- **認証**
  - GitHub OAuth ログイン（NextAuth.js v5）
  - JWT セッション管理

- **リポジトリ管理**
  - GitHub リポジトリの登録・削除
  - `.ai/` ディレクトリの自動検出
  - OrgOS プロジェクトの検証

- **ダッシュボード**
  - 登録プロジェクトの一覧表示
  - プロジェクトステータス（Stage, Awaiting Owner）
  - 未読質問数バッジ
  - DASHBOARD.md の内容表示

- **質問・回答**
  - OWNER_INBOX.md の質問一覧
  - 選択肢 / カスタム回答対応フォーム
  - OWNER_COMMENTS.md への書き込み

- **タスク管理**
  - タスク一覧表示
  - 承認・却下ボタン
  - プロジェクト横断タスク優先度ビュー

- **通知**
  - Slack Incoming Webhook 連携
  - Web Push 通知
  - 30秒間隔の自動ポーリング

- **セキュリティ**
  - CSP ヘッダー（環境別設定）
  - レート制限（100 req/min）
  - XSS / CSRF 対策

- **UI**
  - レスポンシブデザイン（モバイル対応）
  - ダークモード対応（Tailwind CSS 4）

### 技術スタック

- Next.js 16.1.4（App Router）
- Tailwind CSS 4
- Prisma 7.2.0 + SQLite（better-sqlite3）
- NextAuth.js v5 beta
- Octokit（GitHub API）

### 使用している OrgOS

- OrgOS v0.11.0

---

## 今後の予定

### Phase 2
- Claude Code SDK 連携による `/org-tick` リモート実行
- リアルタイム WebSocket 更新（ポーリングからの移行）

### その他
- PostgreSQL / MySQL 対応（本番デプロイ用）
- 複数ユーザーでの共同管理
- 権限管理（Admin / Editor / Viewer）
