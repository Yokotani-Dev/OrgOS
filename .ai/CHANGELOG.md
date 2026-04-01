# OrgOS WebConsole 変更履歴

このファイルは OrgOS WebConsole の各バージョンで何が変わったかを記録します。

---

## v0.22.0 (2026-04-01)

### 追加
- **自律走行モード**: Manager が「提案→承認待ち」から「実行→報告」に変更。人間の介入を最小化
- **ビジネス文脈ヒアリング**: `/org-brief` にペルソナ・動機・参照・成功基準の必須質問を追加
- **参照・競合調査**: DESIGN フェーズで類似サービス調査を必須化（REFERENCES.md テンプレート）
- **MVP→確認→拡張サイクル**: 核となる機能を先に見せて方向確認するインクリメンタルデリバリー
- **外部AIリソーススキャン**: `org-evolve` が GitHub trending / Claude Code コミュニティから革新的パターンを自動発見・取り込み
- **Runbook 機構**: ルーティンワークの手順化・品質安定化（`.ai/RUNBOOKS/`）
- **Iron Law（ファイル衝突防止）**: `allowed_paths` が重複するタスクの並列実行を禁止

### 改善
- **セッション管理簡素化**: 95%超の強制終了のみ残し、途中終了提案を廃止
- **rules/patterns.md 圧縮**: 430行→28行の軽量インデックスに
- **次ステップ案内**: 選択肢提示から自律実行報告へ変更
- **AI ドリブン開発**: Manager の技術判断自律性を明確化

---

## v0.21.0 (2026-03-30)

### 追加
- **スキル 9ファイル新規作成**: web-design-guidelines, refactoring-patterns, requirements-specification, task-breakdown, deployment-planning, security(rules→skills移動), testing(同), review-criteria(同), literacy-reference
- **合理化防止ルール**: `rationalization-prevention.md` - Iron Law（鉄則）、言い訳テーブル、Red Flags チェックリスト（obra/superpowers ベース）
- **Eval 4スクリプト追加**: check-skill-compliance.sh, check-consistency.sh, check-duplicates.sh, check-refs.sh
- **`/org-evolve` コマンド**: OrgOS 自律改善ループ
- **`/org-dashboard` コマンド**: マルチプロジェクト Dashboard 連携（~/.orgos/projects.yaml 登録）
- **`/org-goals` コマンド**: ゴール階層の表示・編集
- **Dashboard 設計**: .ai/DESIGN/DASHBOARD_ARCHITECTURE.md

### 改善
- **二段階レビュー**: org-reviewer を Stage 1（仕様適合）→ Stage 2（設計品質）に再構築
- **サブエージェント報告検証**: agent-coordination にレポート検証プロトコル追加（DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED）
- **Iron Law 追加**: testing, security, review-criteria, requirements-specification, task-breakdown の5スキルに Iron Law セクション追加
- **CSO 原則**: CLAUDE.md にスキル description の記述ルール追加
- **スキル強化**: frontend-patterns(+Next.js最適化,React19), backend-patterns(+SQL最適化), security(+CodeQL), testing(+Playwright E2E)
- **コンテキスト最適化**: rules/ から skills/ へ3ファイル移動、CLAUDE.md圧縮、台帳統廃合（DASHBOARD/STATUS/RUN_LOG役割再定義）
- **エージェント責務明確化**: reviewer（設計専任）, planner（architect委任）, scribe（doc-updater委任トリガー）
- **ルール二重定義解消**: performance, ai-driven, next-step, plan-sync, date-awareness の重複排除
- **manifest 更新**: 新規スキル・ルール・eval を publish 対象に追加

### 内部
- **RUNTIME.yaml 新設**: CONTROL.yaml からランタイム状態を分離
- **TASKS_ARCHIVE.yaml 新設**: done タスクのアーカイブ先

---

## v0.20.0 (2026-03-23)

### 追加
- **`/issue` コマンド**: 任意のリポジトリから OrgOS 開発リポジトリに issue を起票
  - バグ報告・機能要望・質問を対話形式でヒアリング
  - OrgOS バージョン・プロジェクトステージを自動収集
  - `gh issue create --repo Yokotani-Dev/OrgOS` で直接起票
  - ラベル（bug / enhancement / question）を自動付与

---

## v0.19.0 (2026-02-13)

### 追加
- **org-tick オートコンティニュー** (T-OS-023): Tick 完了後に条件を満たせば自動的に次の Tick を連続実行
  - batch/manual モードで Owner に毎回返さず連続処理
  - 最大 10 Tick/回、コンテキスト 80% で強制停止
- **全作業 TASKS.yaml 登録必須化** (T-OS-024): ad-hoc 実行を禁止、全作業を TASKS.yaml 経由で管理
  - 割り込みタスク受付フロー追加（allowed_paths 衝突チェック）
  - org-tick Step 2.2「新規依頼のタスク化」を追加

### 改善
- **`/org-start` public OrgOS 自動切断** (T-OS-025): public OrgOS リポジトリをクローンした場合、選択肢を出さず自動で origin を切断
  - FlowA Step 1 に Pattern B（`/OrgOS` URL 判定）を追加
  - Step 3 テンプレートに `is_orgos_dev: false` を明示

### 内部
- **Intelligence パイプライン品質修正** (T-INT-007〜010): orgos-intelligence リポジトリで4件の品質改善
  - T-INT-007: Gemini スコアリング JSON 抽出強化 + OIP 生成改善
  - T-INT-008: HN フィルタリング精度改善（単語境界マッチ + ストップワード除外）
  - T-INT-009: HTML タグ残留修正（stripHtml 2パス処理）
  - T-INT-010: 重複排除強化（URL 正規化 + 単語 Jaccard 0.5）
- **Intelligence Phase 5-6** (T-INT-005〜006): ロールバック機構、Kernel 保護、ソース管理 Slack フロー

---

## v0.18.0 (2026-02-13)

### 追加
- **OS Evals 基盤**: Level 1 自動評価スクリプト群を追加（`.claude/evals/`）
  - `check-schema.sh`: YAML/manifest スキーマ検証
  - `check-kernel-boundary.sh`: Kernel 境界チェック
  - `check-agent-defs.sh`: エージェント定義整合性チェック
  - `check-oip-format.sh`: OIP フォーマット検証
  - `check-security.sh`: セキュリティスキャン
  - `run-all.sh`: 全チェック一括実行
- **Intelligence ディレクトリ**: 運用データ収集の基盤構造を追加（`.ai/INTELLIGENCE/`）

### 修正
- `/org-start` で public clone 時に OrgOS 開発検出が誤発動する問題を修正

---

## v0.17.0 (2026-02-13)

### 改善
- **Codex デフォルトモデル更新**: `gpt-5.2-codex` → `gpt-5.3-codex-spark`（Cerebras 上で 1000+ tok/s の高速推論に対応）
  - `agent-coordination.md`, `org-tick.md` のモデル参照を更新

### 内部
- **OrgOS Intelligence 設計完了**: T-INT-000〜006 タスク追加、設計書（`.ai/DESIGN/ORGOS_INTELLIGENCE.md`）作成
- **Codex Work Order/Logs**: T-OS-019〜021 の実行ログ追加

---

## v0.16.1 (2026-01-30)

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
