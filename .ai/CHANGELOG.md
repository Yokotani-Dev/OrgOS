# OrgOS 変更履歴

このファイルはOrgOSの各バージョンで何が変わったかを日本語で記録します。

---

## v0.5.0 (2026-01-20)

### 追加
- **`/org-publish`**: 開発リポジトリ（OrgOS-Dev）から公開リポジトリ（OrgOS）への同期機能
- **CI自動テスト**: `.github/workflows/test.yaml`（push/PR時にmanifest・ファイル整合性を自動検証）
- **公開リポジトリ**: `Yokotani-Dev/OrgOS`（public）を新設

### 改善
- **`/org-release`**: リリース前バリデーション追加（manifest構造、ファイル存在、VERSION形式のチェック）
- **`/org-publish`**: 公開前レビュー（差分表示、削除ファイル検出、機密情報スキャン）
- **`/org-publish`**: ロールバック手順をドキュメント化（3パターン）
- **`.orgos-manifest.yaml`**: `publish`セクション追加（公開対象ファイルを明示的に定義）

### リポジトリ運用
- **開発用（private）**: `Yokotani-Dev/OrgOS-Dev`
- **公開用（public）**: `Yokotani-Dev/OrgOS`
- リリースフロー: `/org-release` → `/org-publish`

---

## v0.4.0 (2026-01-20)

### 追加
- **`/org-codex`**: OpenAI Codex CLIを使ったタスク実行コマンド
- **`/org-admin`**: OrgOS開発者用の管理モード（`/org-init`から分離）
- **`.ai/ARTIFACTS/`**: 成果物格納ディレクトリ（入力と出力を明確に分離）
- **`.claude/scripts/run-parallel.sh`**: Codex並列実行スクリプト

### 改善
- **`/org-start`**: `/org-init`の機能を統合（リポジトリ切断→新リポ接続を一元化）
- **`/org-tick`**: 自動並列実行判断とworktree管理を追加
- **`/org-integrate`**: 統合手順の詳細化（worktreeクリーンアップ手順追加）
- **`CLAUDE.md`**: 日本語を読みやすく改善、「次に何が起きるか」を具体的に明示するルール追加

### 削除
- **`/org-init`**: 機能は`/org-start`と`/org-admin`に移行

---

## v0.3.0 (2025-01-19)

### 追加
- **`/org-init`**: クローン後の初期セットアップ（リポジトリ切断→新リポ接続→`/org-start`へ自動遷移）
- **OrgOS-Dev接続警告**: セッション開始時にOrgOS-Devリポジトリ接続を検知して警告
- **管理者コード認証**: OrgOS開発者は`0417`を入力して開発モードを有効化

---

## v0.2.0 (2025-01-19)

### 追加
- **`/org-release`**: ワンコマンドでOrgOSをリリース（変更自動検出、VERSION/CHANGELOG自動更新、バージョン選択）

---

## v0.1.0 (2025-01-19)

### 追加
- **`/org-export`**: OrgOSのコア部分を他プロジェクトにエクスポートするコマンド
- **`/org-import`**: エクスポートしたOrgOSを別プロジェクトにインポートするコマンド
- **バージョン管理**: `VERSION.yaml`で内部管理、`CHANGELOG.md`で変更履歴を追跡

### 含まれる機能
- `/org-start`: OrgOSプロジェクトの初期化
- `/org-brief`: 対話形式でBRIEF.mdを整形
- `/org-kickoff`: プロジェクト開始時のヒアリング
- `/org-plan`: 要件→設計→タスクDAG作成
- `/org-tick`: 1Tick進行（台帳更新→タスク分配→レビュー→次の手）
- `/org-review`: Review Packet + diff を用いたレビュー
- `/org-integrate`: マージ順制御してmainへ統合
- `/org-os-retro`: OrgOSの運用を振り返り、改善提案（OIP）を作る

---

## 今後の予定
- プロジェクト固有設定とOrgOSコアの分離改善
- インポート時の差分マージ機能
