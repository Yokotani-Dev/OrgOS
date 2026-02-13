# DASHBOARD

> OrgOS プロジェクト状況の1枚絵。Owner はこのファイルを見て状況を把握する。

---

## 🚦 Now

| 項目 | 状態 |
|------|------|
| Stage | **KICKOFF** |
| Awaiting Owner | NO |
| Paused | NO |

---

## 🎯 Goal Hierarchy

**Vision**: (未設定 - /org-start で初期化されます)

**Milestones**: (未設定)

**Current Project**: (未設定)

---

## 📋 Next Action (Owner)

### まだ `/org-start` を実行していない場合：

1. **`.ai/BRIEF.md` を記入してください**
   - 作りたいもの、マスト要件、NG事項を記入
   - 分からない項目は「TBD」でOK

2. **`/org-start` を実行**
   - リポジトリ確認 → 初期化 → キックオフ質問生成 まで自動で進みます
   - OrgOS-Dev接続時は警告→切断確認されます
   - OrgOS開発には `/org-admin` を使用

### `/org-start` 実行後：

1. **`.ai/OWNER_INBOX.md` の質問に回答**
   - 回答は `.ai/OWNER_COMMENTS.md` に記入

2. **次のメッセージを送信（または `/org-tick` を実行）**
   - Manager が回答を読み取り、PROJECT.md を更新します

---

## 📊 Progress

- [ ] BRIEF.md 記入
- [ ] /org-start 実行
- [ ] キックオフ質問に回答
- [ ] 要件確定 (REQUIREMENTS gate)
- [ ] 設計確定 (DESIGN gate)
- [ ] 実装開始
- [ ] 統合 (INTEGRATION gate)
- [ ] リリース (RELEASE gate)

---

## 🔒 ゲート制御（現在の状態）

| 操作 | 状態 | 変更方法 |
|------|------|----------|
| git push | ✅ 許可 | CONTROL.yaml: allow_push: true |
| push to main | ✅ 許可 | CONTROL.yaml: allow_push_main: true |
| main mutation | ✅ 許可 | CONTROL.yaml: allow_main_mutation: true |
| deploy | ❌ 禁止 | CONTROL.yaml で allow_deploy: true |
| destructive ops | ❌ 禁止 | CONTROL.yaml で allow_destructive_ops: true |
| OS変更 | ✅ 許可 | CONTROL.yaml: allow_os_mutation: true |

> これらの変更には **Owner 承認** が必要です。

---

## 💬 Owner の介入方法

1. **質問に答える**: `.ai/OWNER_INBOX.md` を見て、`.ai/OWNER_COMMENTS.md` に回答
2. **方針を変える**: `.ai/OWNER_COMMENTS.md` に指示を書く
3. **停止する**: `.ai/CONTROL.yaml` で `paused: true` に設定
4. **ゲートを開ける**: `.ai/CONTROL.yaml` の `allow_*` を `true` に変更

---

## 📁 ファイル構成（参考）

```
.ai/
  BRIEF.md          ← Owner が最初に書く（/org-brief で対話作成可）
  PROJECT.md        ← Manager が生成・更新
  OWNER_INBOX.md    ← Manager からの質問
  OWNER_COMMENTS.md ← Owner の回答・指示
  DASHBOARD.md      ← この文書
  CONTROL.yaml      ← ゲート制御
  TASKS.yaml        ← タスク管理
  RESOURCES/        ← 参照資料格納（docs/designs/references/code-samples）
  CODEX/            ← Codex worker I/O
  REVIEW/           ← レビュー関連
```

---

## 📝 Recent Changes (last tick)

- Tick #29（2026-02-13）: T-INT-007〜010 統合 + T-OS-025 完了
  - T-INT-007: Gemini スコアリング JSON 抽出強化 + OIP 生成改善
  - T-INT-008: HN フィルタリング精度改善（単語境界マッチ + ストップワード除外）
  - T-INT-009: HTML タグ残留修正（stripHtml 2パス処理）
  - T-INT-010: 重複排除強化（URL 正規化 + 単語 Jaccard 0.5）
  - 全4件 TypeScript ビルド通過、main マージ + push (a6c2a87)
  - T-OS-025: /org-start FlowA で public OrgOS リポジトリの origin を自動切断
  - Owner 作業: orgos-intelligence で `wrangler deploy` が必要（品質改善の反映）
- Tick #26-28（2026-02-13）: T-INT-005 + T-INT-006 完了（Intelligence Phase 5-6）
  - OrgOS Intelligence Phase 0-6 全完了
- Tick #25（2026-02-13）: T-OS-024 全作業 TASKS.yaml 登録必須化
- Tick #24（2026-02-13）: T-INT-004 OS Evals 実装完了
- ✅ T-OS-005 完了: プロジェクト引き継ぎ機能を実装
  - [CONTROL.yaml](.ai/CONTROL.yaml) に handoff セクション追加
  - [.ai/HANDOFF.md](.ai/HANDOFF.md) テンプレート作成
  - [.claude/hooks/SessionStart.sh](.claude/hooks/SessionStart.sh) に引き継ぎ検知機能を追加
  - [CLAUDE.md](../CLAUDE.md) にプロジェクト引き継ぎのセクション追加
  - 3つの引き継ぎパターン: 上司→部下 / 部下→上司（レビュー） / チームメンバー間
- ✅ T-OS-004 完了: 上司レビューモード機能を実装
  - [CONTROL.yaml](.ai/CONTROL.yaml) に supervisor_review セクション追加
  - [.ai/SUPERVISOR_REVIEW/](.ai/SUPERVISOR_REVIEW/) フォルダ作成
  - [CLAUDE.md](../CLAUDE.md) にスーパーバイザーレビューのセクション追加
  - [/org-start](.claude/commands/org-start.md) に作業者・レビュー要否の質問追加
  - 3つのモード: self_only（デフォルト） / self_with_reminder / subordinate_with_supervisor
  - 計画乖離検知機能（30%以上乖離で警告）
- ✅ T-OS-006 完了: ゴール階層管理機能を実装
  - [.ai/GOALS.yaml.template](.ai/GOALS.yaml.template) を作成（Vision/Milestone/Project 階層管理）
  - [/org-start](.claude/commands/org-start.md) に GOALS.yaml 初期化ロジック追加（Step 4-9）
  - [/org-tick](.claude/commands/org-tick.md) に Milestone 達成確認・見直し提案追加（Step 6A）
  - [/org-goals](.claude/commands/org-goals.md) コマンド作成（表示・追加・拡大・見直し・履歴）
  - [CLAUDE.md](../CLAUDE.md) にゴール階層管理セクション追加
  - DASHBOARD.md / PROJECT.md に Vision/Milestone セクション追加
- ✅ T-OS-007 完了: 成果物管理機能を実装
  - [outputs/](../outputs/) フォルダを作成（日付別・タスクID別）
  - [outputs/README.md](../outputs/README.md) で使い方を説明
  - [CLAUDE.md](../CLAUDE.md) に成果物管理ルールを追加
  - [.claude/agents/AGENTS.md](.claude/agents/AGENTS.md) を新規作成（Codex worker ガイドライン）
  - 資料（resources/）は直接編集せず、outputs/ にコピーしてから編集するフローを確立

---

## ⚠️ Blockers

(なし)
