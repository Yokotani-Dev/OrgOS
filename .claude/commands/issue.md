# /issue

OrgOS の開発リポジトリに issue を起票する。
どのリポジトリで作業中であっても、OrgOS に対するバグ報告・機能要望・質問を送信できる。

---

## 概要

```
任意のリポジトリ  ──→  Yokotani-Dev/OrgOS (GitHub Issues)
```

作業者が OrgOS を使っている中で気づいた問題や要望を、OrgOS 開発チームに直接フィードバックするためのコマンド。

## 引数

- `[タイトルやメッセージ]` - issue の概要（省略時は対話形式でヒアリング）

## 実行手順

### Step 1: gh CLI の確認

```bash
gh auth status
```

gh CLI が未認証の場合は `gh auth login` を案内して中止する。

### Step 2: issue 情報の収集

引数があればそれをベースにする。なければ対話形式で以下をヒアリングする:

```
OrgOS に issue を起票します。

どんな内容ですか？

[A] バグ報告 - 期待通り動かない、エラーが出る
[B] 機能要望 - こうなったら便利、こんな機能がほしい
[C] 質問     - 使い方がわからない、挙動が不明

選択、または自由に内容を教えてください:
```

回答に応じて詳細をヒアリング:

**バグ報告の場合:**
- 何をしたか（再現手順）
- 期待した結果
- 実際の結果
- OrgOS のバージョン（`.ai/VERSION.yaml` から自動取得を試みる）

**機能要望の場合:**
- どんな機能がほしいか
- なぜ必要か（どんな場面で困っているか）

**質問の場合:**
- 何について知りたいか
- 試したこと

### Step 3: コンテキストの自動収集

以下の情報を自動で収集し、issue 本文に含める:

```bash
# OrgOS バージョン
cat .ai/VERSION.yaml 2>/dev/null || echo "VERSION.yaml not found"

# 現在のプロジェクトのステージ（あれば）
grep -E "^stage:" .ai/CONTROL.yaml 2>/dev/null || echo "CONTROL.yaml not found"
```

### Step 4: issue の作成確認

収集した情報をもとに issue のプレビューを表示する:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 OrgOS Issue プレビュー
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

リポジトリ: Yokotani-Dev/OrgOS
タイプ: [bug / enhancement / question]
タイトル: [タイトル]

本文:
---
[本文プレビュー]
---

ラベル: [自動選択されたラベル]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
この内容で起票しますか？ [y/N]
```

**AskUserQuestion** で確認を取る。

### Step 5: issue の起票

```bash
gh issue create \
  --repo Yokotani-Dev/OrgOS \
  --title "[タイトル]" \
  --body "[本文]" \
  --label "[ラベル]"
```

### Step 6: 完了報告

```
✅ Issue を起票しました

📎 [issue URL]

OrgOS 開発チームが確認します。ありがとうございます。

📌 次はこちら: 作業を続ける or /org-tick
```

---

## issue 本文テンプレート

### バグ報告

```markdown
## バグ報告

### 環境
- OrgOS バージョン: {VERSION}
- プロジェクトステージ: {STAGE}

### 再現手順
{ユーザーの説明}

### 期待した結果
{ユーザーの説明}

### 実際の結果
{ユーザーの説明}

### 補足
{あれば}

---
_Reported via `/issue` from project: {プロジェクト名 or "unknown"}_
```

### 機能要望

```markdown
## 機能要望

### 環境
- OrgOS バージョン: {VERSION}

### ほしい機能
{ユーザーの説明}

### 背景・動機
{ユーザーの説明}

### 補足
{あれば}

---
_Reported via `/issue` from project: {プロジェクト名 or "unknown"}_
```

### 質問

```markdown
## 質問

### 環境
- OrgOS バージョン: {VERSION}

### 知りたいこと
{ユーザーの説明}

### 試したこと
{ユーザーの説明}

---
_Reported via `/issue` from project: {プロジェクト名 or "unknown"}_
```

---

## ラベルの自動選択

| タイプ | ラベル |
|--------|--------|
| バグ報告 | `bug` |
| 機能要望 | `enhancement` |
| 質問 | `question` |

---

## 注意事項

- 機密情報（API キー、パスワード等）が含まれていないか確認してから起票する
- プロジェクト固有のコードは含めない（OrgOS 自体の問題のみ）
- `gh` CLI が必要（未インストールの場合はインストールを案内）
