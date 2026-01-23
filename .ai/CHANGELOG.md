# OrgOS 変更履歴

このファイルはOrgOSの各バージョンで何が変わったかを日本語で記録します。

---

## v0.11.0 (2026-01-23)

### 追加
- **AIドリブン開発ルール**: Managerが技術判断を主導し、Ownerにはビジネス判断のみを依頼する原則を明文化
  - `ai-driven-development.md` - 判断前の自己チェックフロー、選択肢提示のルール、技術判断の自動実行フロー
  - Owner に聞いてよいこと/聞いてはいけないことを明確化
  - 推奨を必ず明示するルール

### 設計方針
- **Manager主導の開発**: 技術的判断はManagerが行い、Ownerは結果を見るだけ
- **ITリテラシーを問わない**: 技術知識がなくても開発を進められる

---

## v0.10.0 (2026-01-22)

### 追加
- **`/org-settings`**: レビュー頻度やリテラシーレベルの設定変更コマンド
- **リテラシー適応ルール**: Ownerの ITリテラシーレベル（beginner/intermediate/advanced）に応じた説明スタイル調整
  - `literacy-adaptation.md` - 用語説明ガイド、レベル別表記ルール
- **Ownerタスク最小化ルール**: ユーザーに作業を依頼する前にCLI/APIで代行できないか確認
  - `owner-task-minimization.md` - CLI対応表、依頼前チェックフロー

### 改善
- **`/org-start`**: 対話形式ヒアリングでBRIEF.md自動生成（4ステップで開始可能）
- **`CLAUDE.md`**: リテラシー適応・Ownerタスク最小化ルールを統合
- **`README.md`**: セットアップ手順を3ステップに簡略化
- **次ステップ案内ルール強化**: 応答の終わり方チェックリスト、具体的なアクション提示

### 設計方針
- **Ownerの負担軽減**: 可能な限りManagerがCLI/APIで代行し、ユーザーにはビジネス判断のみ依頼

---

## v0.9.1 (2026-01-21)

### 追加
- **Rules（品質基準）追加（2ファイル）**: ECD統合の仕上げ
  - `agent-coordination.md` - エージェント協調パターン（並列実行、マルチパースペクティブ分析、コンテキスト管理）
  - `performance.md` - パフォーマンスルール（モデル選択ガイダンス: Haiku/Sonnet/Opus使い分け、コスト最適化）

### 設計方針
- **Hooks/MCPは個別設定**: 環境依存のため、OrgOSがサジェストしてユーザーが必要に応じて設定

---

## v0.9.0 (2026-01-21)

### 追加
- **新規エージェント（5つ）**: ECD (everything-claude-code) からインスパイアされた専門エージェント
  - `org-build-fixer` - TypeScript/ビルドエラーを最小diffで修正
  - `org-refactor-cleaner` - 死コード削除、重複排除、依存整理
  - `org-tdd-coach` - TDDワークフローガイド、カバレッジ監視
  - `org-e2e-runner` - Playwright E2Eテスト実行
  - `org-doc-updater` - コードマップ生成、ドキュメント自動更新
- **エージェント自動選択機構**: `/org-tick` が状況を診断し、必要なエージェントを自動選択・実行

### 改善
- **既存エージェント強化（4つ）**:
  - `org-planner` - 計画テンプレート、レッドフラグ検出、不確実性分類（B1/B2）を追加
  - `org-architect` - 5設計原則、パターン集、アンチパターン警告、Contract定義を追加
  - `org-reviewer` - 詳細なレビュー手順、判定基準を追加
  - `org-scribe` - 台帳管理ルール、ブラックボックス検出、乖離検出を追加

### 削除
- **コマンド簡素化（15→7コマンド）**: `/org-tick` に統合
  - 削除: `/org-plan`, `/org-review`, `/org-integrate`, `/org-codex`, `/org-learn`, `/org-export`, `/org-kickoff`, `/org-os-retro`
  - 残存（通常利用）: `/org-start`, `/org-tick`, `/org-brief`, `/org-import`
  - 残存（Dev環境）: `/org-release`, `/org-publish`, `/org-admin`

### 設計変更
- **ユーザーは基本的に `/org-tick` だけ実行すればOK** - エージェント選択・並列実行はOrgOSが自動判断
- 状況診断ベースのエージェント起動（P0緊急対応→P1計画→P2実装→P3メンテナンス→P4統合）

---

## v0.8.0 (2026-01-21)

### 追加
- **Skills（技術知識ベース）**: 実装品質の基準となる4ファイル
  - `coding-standards.md` - コーディング規約（TypeScript/React/API設計）
  - `backend-patterns.md` - バックエンドパターン（リポジトリ、サービス層）
  - `frontend-patterns.md` - フロントエンドパターン（カスタムフック、状態管理）
  - `tdd-workflow.md` - TDDワークフロー（Red-Green-Refactor）
- **Rules（品質基準）**: レビュー・実装時の判断基準4ファイル
  - `security.md` - セキュリティルール（OWASP Top 10）
  - `testing.md` - テストルール（80%カバレッジ目標）
  - `review-criteria.md` - レビュー基準（CRITICAL/HIGH/MEDIUM）
  - `patterns.md` - 共通パターン（API応答形式など）
- **`/org-learn`**: セッションから学習を抽出し `.ai/LEARNINGS/` に保存
- **`org-security-reviewer`**: セキュリティ専門レビューエージェント（OWASP、脆弱性検出）
- **`org-reviewer`**: 設計妥当性レビューエージェント（復活・役割変更）

### 改善
- **AGENTS.md**: Claude/Codex使い分けを明確化
  - Claude: 全体制御、設計整理、設計妥当性レビュー
  - Codex: 実装（堅牢性重視）、コード品質レビュー
- **README.md**: コマンド一覧（15コマンド）をコードブロックで追加
- **サンドボックス**: デフォルトで無効化（npm/GitHub等のエラー解消）
- **ORGOS_ARCHITECTURE.md**: 内部ドキュメント化（`.ai/RESOURCES/`に移動）

---

## v0.7.0 (2026-01-21)

### 追加
- **`/org-start` 既存プロジェクト再開機能**: リポジトリクローン後に作業を再開可能
  - 自動判定ロジック（新規/再開/OrgOS開発用の3パターン）
  - 台帳を読み込んで状況サマリを表示
  - OrgOS開発用台帳（`is_orgos_dev: true`）検出時は初期化を推奨

### 改善
- **`/org-brief`**: 完了時にBRIEF.mdの確認を必須化（確認前に次ステップに進めない）
- **`ORGOS_QUICKSTART.md`**: 既存プロジェクト再開のドキュメントを追加

---

## v0.6.1 (2026-01-21)

### 改善
- **`/org-start`**: origin未設定時は切断確認をスキップ（Publicからクローンした場合の体験向上）
- **`/org-start`**: OrgOS-Dev接続時の警告にAdmin使用時の注意文言を追加
- **`/org-publish`**: 公開リポジトリからorigin削除処理を追加（ユーザーが即座に使える状態に）
- **`.claude/settings.json`**: .git/への書き込み許可を追加（サンドボックス制限の警告を解消）

---

## v0.6.0 (2026-01-21)

### 追加
- **README.md**: 公開リポジトリ用のREADME（インストール手順含む）
- **`.ai/TEMPLATES/`**: 初期セットアップ用テンプレートファイル（BRIEF.md, CONTROL.yaml, DASHBOARD.md, OWNER_INBOX.md, OWNER_COMMENTS.md）

### 改善
- **`/org-import`**: tarballからPublicリポジトリ直接クローンに変更
- **`/org-import`**: テンプレート自動展開機能追加（初回のみ）
- **`.orgos-manifest.yaml`**: `templates`セクション追加（source→destマッピング）

### 修正
- Publicリポジトリに初期ファイルがなく、ユーザーがそのまま使えない問題を修正

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
