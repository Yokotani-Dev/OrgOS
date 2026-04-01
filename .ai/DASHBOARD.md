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

## 📝 Recent Changes

→ 詳細は [RUN_LOG.md](.ai/RUN_LOG.md) を参照

直近:
- 2026-03-30: Tick 42 - 全タスク完了確認。T-001/T-002 テンプレートを archived。重複 RemoteTrigger を整理。
- 2026-03-30: v0.21.0 リリース（superpowers 改善、Iron Law、CSO 原則）
- 2026-03-30: T-OS-060〜062 OrgOS Dashboard（マルチプロジェクト統合 UI）
- 2026-03-30: T-OS-052〜053 superpowers リポジトリ調査 + 改善実装
- 2026-03-29: T-OS-050〜051 skills.sh 調査 + スキル強化

---

## ⚠️ Blockers

(なし)
