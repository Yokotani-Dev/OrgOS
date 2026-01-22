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

### Step 1: 確認プロンプト

ユーザーに以下を確認：

```
⚠️ 管理者モードに入ろうとしています

管理者モードでは OrgOS 自体のファイルを編集できます。
通常のプロジェクト開発では使用しません。

本当に管理者モードに入りますか？ [y/N]
```

- `y` または `yes` → Step 2 へ
- それ以外 → 中止

### Step 2: 管理者モード有効化

`.ai/CONTROL.yaml` の以下を変更：

```yaml
# 変更前
allow_os_mutation: false

# 変更後
allow_os_mutation: true
```

### Step 3: 完了メッセージ

```
✅ 管理者モードを有効にしました

OrgOS ファイルの編集が可能です：
- CLAUDE.md
- AGENTS.md
- .claude/**
- requirements.md

📌 管理者モードを終了する: /org-admin exit
   または CONTROL.yaml の allow_os_mutation を false に戻す
```

---

## 管理者モード終了

`/org-admin exit` または以下の操作で終了：

```yaml
# CONTROL.yaml
allow_os_mutation: false
```

終了メッセージ：

```
✅ 管理者モードを終了しました

OrgOS ファイルは保護されています。
```

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
