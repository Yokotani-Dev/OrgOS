# OrgOS クイックスタート

> 新規プロジェクトを開始するための3ステップガイド

---

## Step 1: /org-start を実行

Claude Code で以下を実行：

```
/org-start
```

これにより自動で：
1. **リポジトリ確認**（OrgOS-Dev接続時は警告→切断確認）
2. 既存の台帳データを退避（`.ai/_archive/` へ）
3. 台帳を初期化
4. BRIEF.md を確認（未記入なら記入を促して停止）
5. キックオフ質問を生成
6. `.ai/OWNER_INBOX.md` に質問を記載
7. `.ai/DASHBOARD.md` を更新

> **Note**: OrgOS自体を開発する場合は `/org-admin` を使用してください。

---

## Step 2: BRIEF を書く（未記入の場合）

`.ai/BRIEF.md` を開いて、以下を記入してください：

| セクション | 書くこと |
|-----------|---------|
| 作りたいもの | 1-3文で概要 |
| マスト要件 | なければリリースできない機能 |
| 望ましい要件 | あると嬉しい機能 |
| 既存資産 | 流用できるコード、デザイン等 |
| NG事項 | やらないこと、禁止事項 |
| 期限/予算 | 分からなければ TBD |

**ポイント**: 完璧でなくてOK。分からない項目は「TBD」と書いてください。

記入後、再度 `/org-start` を実行するとキックオフ質問が生成されます。

---

## Step 3: 質問に答える

1. `.ai/OWNER_INBOX.md` の質問を確認
2. `.ai/OWNER_COMMENTS.md` に回答を記入
3. 次のメッセージを送信（または `/org-tick` を実行）

**例**:
```markdown
### 2026-01-18: Q-001 への回答

認証方式は Option 1 (JWT + Cookie) でお願いします。
```

---

## 以後の運用

| やること | 方法 |
|---------|------|
| 状況確認 | `.ai/DASHBOARD.md` を見る |
| 質問に答える | `.ai/OWNER_COMMENTS.md` に記入 |
| 進行を進める | `/org-tick` を実行 |
| 一時停止 | `.ai/CONTROL.yaml` で `paused: true` |
| push許可 | `.ai/CONTROL.yaml` で `allow_push: true` |

---

## 並列開発について

OrgOSは `/org-tick` 実行時に自動的に並列実行を判断します。

### 仕組み

1. `/org-tick` が依存解消済みのタスクを検出
2. Codexタスクは **自動的に並列実行** を準備
3. 各タスクは独立した **git worktree** で実行
4. 結果は次の `/org-tick` で自動回収

### Codex実行（auto_exec: false の場合）

`/org-tick` が以下のようなコマンドを提示します：

```bash
# 並列実行
./.claude/scripts/run-parallel.sh T-003 T-004

# 状態確認
./.claude/scripts/run-parallel.sh --status
```

実行後、再度 `/org-tick` で結果を回収します。

### 設定

`.ai/CONTROL.yaml` で並列実行を制御：

```yaml
runtime:
  max_parallel_tasks: 6  # 同時実行数の上限

codex:
  auto_exec: false       # true にすると自動実行
```

---

## ファイル構成（参考）

```
.ai/
  BRIEF.md          ← あなたが書く
  PROJECT.md        ← Manager が生成
  DASHBOARD.md      ← 状況確認用
  OWNER_INBOX.md    ← Manager からの質問
  OWNER_COMMENTS.md ← あなたの回答
  CONTROL.yaml      ← ゲート制御
  TASKS.yaml        ← タスク管理
  CODEX/            ← Codex worker I/O
  REVIEW/           ← レビュー関連
```

---

## トラブルシューティング

**Q: BRIEF を書き忘れて /org-start した**
A: DASHBOARD に「BRIEF を書いてください」と表示されます。書いてから再度 /org-start を実行してください。

**Q: 前のプロジェクトのデータはどこ？**
A: `.ai/_archive/<timestamp>/` に退避されています。

**Q: Codex を使いたい**
A: TASKS.yaml で `owner_role: codex-implementer` を指定し、Work Order が生成されたら `codex exec` を実行してください。

**Q: push したい**
A: `.ai/CONTROL.yaml` で `allow_push: true` に変更してください（Owner 承認が必要）。

---

## 詳細ドキュメント

- [CLAUDE.md](CLAUDE.md) - OrgOS Manager の振る舞い定義
- [AGENTS.md](AGENTS.md) - Codex worker のルール
- [.ai/GIT_WORKFLOW.md](.ai/GIT_WORKFLOW.md) - Git 運用ルール
- [requirements.md](requirements.md) - OrgOS 仕様書
