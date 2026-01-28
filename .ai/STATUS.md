# STATUS

> プロジェクト状態の要約。Manager が更新する。

---

## Summary

| 項目 | 値 |
|------|-----|
| Stage | KICKOFF |
| Completed tasks | 15 |
| In progress | 0 |
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

---

## Blockers

(なし)

---

## Recent Activity

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
