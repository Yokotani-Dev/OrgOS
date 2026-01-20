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
| git push | ❌ 禁止 | CONTROL.yaml で allow_push: true |
| push to main | ❌ 禁止 | CONTROL.yaml で allow_push_main: true |
| deploy | ❌ 禁止 | CONTROL.yaml で allow_deploy: true |
| OS変更 | ❌ 禁止 | CONTROL.yaml で allow_os_mutation: true |

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

- (初期状態)

---

## ⚠️ Blockers

- (なし)
