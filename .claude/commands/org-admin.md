---
description: OrgOS管理者モード（OrgOS開発者用）
---

# /org-admin - 管理者モードコマンド

OrgOS自体を編集・開発するためのコマンド。
OrgOS-Devリポジトリで作業する開発者向け。

---

## 実行条件

このコマンドは以下の場合にのみ使用：
- OrgOS自体の機能を追加・修正する
- OrgOSのドキュメントを更新する
- OrgOSのテンプレートを変更する

**通常のプロジェクト開発には使用しない** → `/org-start` を使う

---

## 実行手順

### Step 1: リポジトリ確認

```bash
git remote -v
```

OrgOS-Dev（または類似のOrgOS開発用リポジトリ）に接続されていることを確認。

### Step 2: 管理者モード有効化

`.ai/CONTROL.yaml` に以下を設定：

```yaml
is_orgos_dev: true
```

### Step 3: 完了メッセージ

「OrgOS管理者モードを有効にしました。OrgOSの編集が可能です。」と表示。

---

## 管理者モードで可能な操作

| 操作 | 説明 |
|------|------|
| `.claude/commands/` 編集 | スキル定義の追加・修正 |
| `.claude/hooks/` 編集 | フック処理の追加・修正 |
| `CLAUDE.md` 編集 | Manager の振る舞い定義 |
| `AGENTS.md` 編集 | Codex worker のルール |
| `.ai/` テンプレート編集 | 台帳テンプレートの修正 |
| `requirements.md` 編集 | OrgOS仕様書の更新 |

---

## 注意事項

- 管理者モードでは `/org-start` の台帳初期化は行わない
- OrgOS自体の変更は慎重に行う
- 変更後は必ずテストする
