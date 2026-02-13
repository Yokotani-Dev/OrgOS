# STATUS

> プロジェクト状態の要約。Manager が更新する。

---

## Summary

| 項目 | 値 |
|------|-----|
| Stage | KICKOFF |
| Completed tasks | 36 |
| In progress | 0 |
| Review | 0 |
| Blocked | 0 |
| Queued | 2 |

---

## Task Overview

| ID | Title | Status | Owner |
|----|-------|--------|-------|
| T-001 | Kickoff: collect requirements | queued | org-planner |
| T-002 | Design: define contracts | queued | org-architect |
| T-OS-004 | 上司レビューモード | **done** | codex-implementer |
| T-OS-005 | 引き継ぎ機能 | **done** | codex-implementer |
| T-OS-006 | ゴール階層管理 | **done** | codex-implementer |
| T-OS-007 | 成果物管理機能 | **done** | codex-implementer |
| T-OS-008〜013 | 上司FB対応6件 | **done** | codex-implementer |
| T-OS-014 | Codex CLI 統合 Phase 1 | **done** | org-architect |
| T-OS-015 | Codex CLI 統合 Phase 2 | **done** | codex-implementer |
| T-INT-000 | Intelligence Phase 0: 手動レポート検証 | **done** | org-architect |
| T-INT-001 | Intelligence Phase 1: リポジトリ構築 | **done** | codex-implementer |
| T-INT-002 | Intelligence Phase 2: Slack Bot | **done** | codex-implementer |
| T-INT-003 | Intelligence Phase 3: OIP-AUTO + PR | **done** | codex-implementer |
| T-INT-004 | Intelligence Phase 4: Evals + 自動承認 | **done** | org-architect |
| T-OS-023 | org-tick オートコンティニュー + レビュー設定修正 | **done** | org-implementer |
| T-OS-024 | 全作業 TASKS.yaml 登録必須化 + 割り込みフロー | **done** | codex-implementer |
| T-INT-005 | Intelligence Phase 5: ロールバック + Kernel保護 | **done** | codex-implementer |
| T-INT-006 | Intelligence Phase 6: ソース管理Slackフロー | **done** | codex-implementer |
| T-INT-007 | Intelligence 品質: Gemini スコアリング復旧 | **done** | codex-implementer |
| T-INT-008 | Intelligence 品質: HN フィルタリング精度 | **done** | codex-implementer |
| T-INT-009 | Intelligence 品質: HTML タグ残留修正 | **done** | codex-implementer |
| T-INT-010 | Intelligence 品質: 重複排除強化 | **done** | codex-implementer |
| T-OS-025 | /org-start public OrgOS 自動切断 | **done** | org-implementer |

---

## Blockers

(なし)

---

## Recent Activity

- T-INT-007〜010: ✅ Intelligence パイプライン品質修正4件完了（2026-02-13）
  - T-INT-007: Gemini スコアリング JSON 抽出強化 + OIP 生成改善
  - T-INT-008: HN フィルタリング精度改善（単語境界マッチ + ストップワード除外 + MIN_HN_SCORE=30）
  - T-INT-009: HTML タグ残留修正（stripHtml 2パス処理）
  - T-INT-010: 重複排除強化（URL 正規化 + 単語 Jaccard 類似度 0.5）
  - TypeScript ビルド通過、main マージ + push 完了 (a6c2a87)
- T-OS-025: ✅ /org-start public OrgOS リポジトリ自動切断修正（2026-02-13）
  - FlowA Step 1 パターン B: origin に `/OrgOS` を含む場合に自動切断
  - Step 3: CONTROL.yaml テンプレートに `is_orgos_dev: false` を明示
- T-INT-006: ✅ Intelligence Phase 6 完了 + レビュー修正（2026-02-13）
  - Slack ソース管理フロー実装: ソース追加/削除/一覧コマンド
  - Tier 選択ボタン（Block Kit）、URL バリデーション、削除確認ステップ
  - KV バックエンド永続化（addSource/removeSource ヘルパー）
  - TypeScript ビルド通過、コミット済み (3ad2b4b)
  - レビュー: CRITICAL 1 + HIGH 3 + MEDIUM 2（REVIEW-003）
  - 修正: 正規表現バグ、SSRF 保護、制御文字除去、mrkdwn エスケープ等
  - 修正コミット: 0157e5a
- T-INT-005: ✅ Intelligence Phase 5 完了（2026-02-13）
  - ロールバック機構: Slack 「ロールバック」コマンド → revert PR 自動作成・マージ
  - Kernel 保護: OIP 生成時の impactScope 強制設定 + KERNEL-APPROVE 承認要求
  - レビュー: CRITICAL 2 + HIGH 3 → 全件修正済み（入力バリデーション、エラーサニタイズ、revert PR 安全チェック）
  - TypeScript ビルド通過、コミット済み (ffc43ea)
- T-INT-003: ✅ Phase 3 未コミット変更をコミット + push (618ebde)
- T-OS-024: ✅ 全作業 TASKS.yaml 登録必須化 + 割り込みタスク受付フロー整備（2026-02-13）
  - project-flow.md: 小タスク即実行を廃止、全作業 TASKS.yaml 登録必須に変更
  - project-flow.md: 割り込みタスク受付フロー（allowed_paths 衝突チェック）を追加
  - org-tick.md: Step 2.2「新規依頼のタスク化」を追加
  - manager.md:「全作業 TASKS.yaml 登録必須」「割り込みタスクの並列管理」セクション追加
- T-OS-023: ✅ org-tick オートコンティニュー追加（2026-02-13）
  - CONTROL.yaml: mode を "every_n_tasks" → "batch" に修正
  - org-tick.md: Step 13 オートコンティニュー判定を追加
  - ⚠️ 当初 ad-hoc で実行、Owner 指摘により遡及タスク化
- T-INT-004: ✅ Intelligence Phase 4 完了（2026-02-13）
  - OS Evals テストスイート構築（.claude/evals/ に5スクリプト + ランナー）
  - Kernel/Userland 境界定義（KERNEL_FILES: 4ファイル保護）
  - org-tick Step 9A: OIP PR 検出 + Level 判定 + Eval ベース自動承認
  - レビュー: CRITICAL 1 + HIGH 4 → 全件修正済み
  - 設計書: .ai/DESIGN/ORGOS_EVALS.md
- T-INT-003: ✅ Intelligence Phase 3 完了（2026-02-13）
  - 実装 + レビュー（CRITICAL 1, HIGH 6 → 全件修正）+ TypeScript ビルド通過
  - Owner 作業: wrangler secret put GITHUB_INSTALLATION_ID + wrangler deploy
- T-INT-002: ✅ Intelligence Phase 2 完了（2026-02-13）
  - Slack Bot 実装: Block Kit レポート投稿、OIP 承認ボタン、スレッド対話
  - Events API + Interactive Components エンドポイント追加
  - Phase 1 改善: HTML エンティティ変換強化、タイトル類似度重複排除
  - Slack App 設定: Bot Token Scopes (chat:write, channels:read, channels:join)
  - テスト投稿成功確認済み
- T-INT-001: ✅ Intelligence Phase 1 完了（2026-02-13）
  - orgos-intelligence リポジトリ構築・全モジュール実装・デプロイ
  - Worker URL: https://orgos-intelligence.dev-2b7.workers.dev
  - 初回パイプライン実行: 23トピック収集成功
  - Cron: 毎朝 9:00 JST 自動実行
  - 改善点は T-INT-002 に引き継ぎ
- ad-hoc: ✅ Codex CLI 0.98.0→0.101.0 アップデート + デフォルトモデル gpt-5.3-codex-spark に更新（2026-02-13）
- T-INT-000: ✅ Intelligence Phase 0 完了（2026-01-30）Owner承認済み
  - 10トピック形式のレポート品質検証完了
  - 設計書に要件#23-31を追加（トピック選定基準、OIP-AUTO粒度等）
  - 成果物: outputs/2026-01-30/intelligence-report-2026-01-30.md
- ad-hoc: ✅ BUG-FIX-001 Codex worktree パスバグ修正（2026-01-30）
- T-OS-020: ✅ rules/ 間の重複排除（2026-01-30）
- T-OS-021: ✅ エージェント定義補完・整理（2026-01-30）
- T-OS-022: ✅ commands/ 重複集約 + 台帳整理（2026-01-30）
- T-OS-019: ✅ P0修正完了（2026-01-30）壊れた参照パス + 関数サイズ基準統一
- T-OS-018: ✅ 全体コードレビュー完了（2026-01-30）
  - 64件検出: CRITICAL 1, HIGH 11, MEDIUM 25, LOW 27
  - 修正タスク T-OS-019〜022 を追加（PLAN-UPDATE-007）
- T-OS-016: ✅ OrgOS 構成リファクタリング完了（2026-01-28）
  - CLAUDE.md: 390行→96行（-294行）
  - patterns.md: 429行→34行（-395行、目次化）
  - ai-driven-development.md: 選択肢提示ルールを next-step-guidance.md に一元化（-45行）
  - performance.md / manager.md: コンテキスト使用率テーブルを session-management.md に一元化（-60行）
  - requirements.md: 歴史的文書宣言を追加
- T-OS-017: ✅ Codex Worker ルール参照強化（2026-01-28）
  - AGENTS.md に「参照すべきルール・スキル」セクション追加
- T-OS-014: ✅ Codex CLI 統合 Phase 1 完了（2026-01-28）
  - read-only / workspace-write 両モード正常動作確認
  - ChatGPT アカウントでは o3 モデル使用不可（デフォルトモデルは OK）
  - Bash 経由パイプライン動作確認済み
  - OIP-008 / TECH-DECISION-002 に記録
- T-OS-008〜013: ✅ 上司FB対応6件完了（2026-01-28）
- T-OS-005: ✅ プロジェクト引き継ぎ機能を実装完了
  - CONTROL.yaml に handoff セクション追加
  - .ai/HANDOFF.md テンプレート作成
  - .claude/hooks/SessionStart.sh に引き継ぎ検知機能を追加
  - CLAUDE.md にプロジェクト引き継ぎのセクション追加
  - 3つの引き継ぎパターン: 上司→部下 / 部下→上司（レビュー） / チームメンバー間
- T-OS-004: ✅ 上司レビューモード機能を実装完了
  - CONTROL.yaml に supervisor_review セクション追加
  - .ai/SUPERVISOR_REVIEW/ フォルダ作成 + README.md
  - CLAUDE.md にスーパーバイザーレビューのセクション追加
  - /org-start に作業者・レビュー要否の質問追加（Step 4-10）
  - 3つのモード: self_only / self_with_reminder / subordinate_with_supervisor
- T-OS-006: ✅ ゴール階層管理機能を実装完了
  - .ai/GOALS.yaml.template を作成（Vision/Milestone/Project 階層管理）
  - /org-start に GOALS.yaml 初期化ロジック追加（Step 4-9）
  - /org-tick に Milestone 達成確認・見直し提案追加（Step 6A）
  - /org-goals コマンド作成（表示・追加・拡大・見直し・履歴）
  - CLAUDE.md にゴール階層管理セクション追加
  - DASHBOARD.md / PROJECT.md に Vision/Milestone セクション追加
- T-OS-007: ✅ 成果物管理機能を実装完了
  - outputs/ フォルダ構造を作成（日付別 + タスクID別）
  - outputs/README.md を作成
  - CLAUDE.md に成果物管理ルールを追加
  - .claude/agents/AGENTS.md を新規作成（Codex worker ガイドライン + 資料複製フロー）
  - outputs/ をリポジトリに含める（git 管理）
- T-OS-005: プロジェクト引き継ぎ機能を計画に追加（T-OS-004 の後に実装）
- T-OS-004: 上司レビューモード機能を計画に追加（タスク追加のみ、実装未着手）
- T-OS-001: セッション間メモリ永続化を実装（Stop フック + sessions フォルダ）
- T-OS-002: `/org-learn` コマンドを追加（継続学習スキル）
- T-OS-003: 評価ループを追加（CONTROL.yaml の eval_policy セクション）
- ad-hoc: `/org-import` にユーザー影響変更の明示機能を追加
- ad-hoc: `/org-publish` の SSH URL を HTTPS URL に変更（サンドボックス制限の恒久的対応）
