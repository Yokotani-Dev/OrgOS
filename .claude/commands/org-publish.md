# /org-publish

開発リポジトリ (OrgOS-Dev) から公開リポジトリ (OrgOS) へリリースを同期する。

## 概要

```
OrgOS-Dev (private)  ──→  OrgOS (public)
     │                       │
     └─ /org-release         └─ /org-publish
        (タグ作成)               (公開同期)
```

## 引数

- `[version]` - 同期するバージョン（省略時は最新タグ）

## 前提条件

1. 公開リポジトリ `Yokotani-Dev/OrgOS` が存在すること
2. remote `public` が設定されていること
   ```bash
   git remote add public git@github.com:Yokotani-Dev/OrgOS.git
   ```
3. `/org-release` でタグが作成済みであること
4. `allow_push: true` が設定されていること

## 実行手順

### 0. 公開前バリデーション（デグレ防止）

公開前に以下のチェックを実行する。

#### a. 前回公開バージョンとの差分を取得

```bash
# 公開リポジトリの最新タグを取得
PUBLIC_TAG=$(git ls-remote --tags public 2>/dev/null | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | sort -V | tail -1)

# ローカルの最新タグ
LOCAL_TAG=$(git describe --tags --abbrev=0)

echo "公開リポジトリ: $PUBLIC_TAG"
echo "ローカル: $LOCAL_TAG"
```

#### b. 公開予定ファイルの差分レビュー

以下の情報を表示して確認を求める:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 OrgOS 公開前レビュー
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

バージョン: v0.4.0 → v0.5.0

📝 変更ファイル:
  M .ai/CHANGELOG.md
  M .ai/VERSION.yaml
  A .claude/commands/org-publish.md
  M .orgos-manifest.yaml

🗑️ 削除ファイル:
  (なし)

⚠️ 注意が必要な変更:
  - 新しいコマンド org-publish が追加されます
  - manifest構造が変更されています

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
この内容で公開しますか？ [y/N]
```

#### c. チェック項目

| チェック | 説明 | 失敗時 |
|----------|------|--------|
| タグ存在確認 | ローカルにタグが存在するか | ❌ 中止 |
| ファイル整合性 | manifestのpublishファイルがすべて存在するか | ❌ 中止 |
| 削除ファイル検出 | 前バージョンにあって今回ないファイル | ⚠️ 警告 |
| 機密情報スキャン | .env, secrets, API keyなどの混入 | ❌ 中止 |

**AskUserQuestion** で確認:
- 差分を確認しましたか？
- 削除ファイルは意図的ですか？（該当時）
- 公開してよいですか？

すべてOKの場合のみ、以下に進む。

---

### 1. 環境確認

```bash
# public remote の確認
git remote -v | grep public

# 最新タグの取得
git describe --tags --abbrev=0
```

### 2. 公開対象ファイルの取得

`.orgos-manifest.yaml` の `publish` セクションに定義されたファイルを対象とする。

### 3. 公開リポジトリの準備

```bash
# 一時ディレクトリで公開リポジトリをクローン
WORK_DIR=$(mktemp -d)
cd $WORK_DIR
git clone git@github.com:Yokotani-Dev/OrgOS.git
cd OrgOS
```

### 4. ファイル同期

```bash
# 開発リポジトリから公開対象ファイルをコピー
# .orgos-manifest.yaml の publish セクションを参照
```

対象ファイル:
- `.ai/VERSION.yaml`
- `.ai/CHANGELOG.md`
- `.ai/RESOURCES/README.md`
- `.ai/RESOURCES/BRIEF_TEMPLATE.md`
- `.claude/commands/org-*.md`
- `.claude/agents/org-*.md`
- `.claude/settings.json`
- `.githooks/pre-push`
- `.github/workflows/release.yml`
- `.orgos-manifest.yaml`
- `CLAUDE.md`
- `AGENTS.md`
- `ORGOS_QUICKSTART.md`

### 5. origin を削除（ユーザーが即座に使える状態にする）

公開リポジトリでは origin を削除し、ユーザーが `/org-start` 時に切断確認を聞かれないようにする。

```bash
git remote remove origin
```

**理由:**
- ユーザーがクローンした時点で OrgOS-Dev への接続がない状態にする
- `/org-start` 実行時に「切断しますか？」と聞かれるのを防ぐ
- ユーザーは自分のリポジトリを追加するだけでOK

### 6. コミット & タグ & プッシュ

```bash
# origin を戻す（プッシュ用）
git remote add origin https://github.com/Yokotani-Dev/OrgOS.git

git add -A
git commit -m "Release v${VERSION}"
git tag v${VERSION}
git push origin main --tags

# プッシュ後に再度 origin を削除してコミット
git remote remove origin
git add -A
git commit --amend -m "Release v${VERSION}"
git remote add origin https://github.com/Yokotani-Dev/OrgOS.git
git push origin main --force --tags
```

**注意:** 最終的な公開リポジトリの状態では `.git/config` に origin が存在しない。

### 7. クリーンアップ

```bash
rm -rf $WORK_DIR
```

## 使用例

```bash
# 最新バージョンを公開
/org-publish

# 特定バージョンを公開
/org-publish v0.4.0
```

## 初回セットアップ

公開リポジトリが空の場合、初回は以下を実行：

1. GitHubで `Yokotani-Dev/OrgOS` (public) を作成
2. remote追加
   ```bash
   git remote add public git@github.com:Yokotani-Dev/OrgOS.git
   ```
3. `/org-publish` を実行

## 注意事項

- **開発履歴は公開されない**: 公開リポジトリにはリリースごとに1コミット
- **機密情報の確認**: 公開対象ファイルに機密情報がないか確認
- **タグの一貫性**: 開発リポジトリと公開リポジトリで同じタグを使用

## リポジトリ構成

```
Yokotani-Dev/OrgOS-Dev  (private)  ← 開発用
Yokotani-Dev/OrgOS      (public)   ← 公開用
```

## ロールバック手順

公開後に問題が見つかった場合のロールバック方法。

### 方法1: 前バージョンに戻す（推奨）

```bash
# 公開リポジトリをクローン
git clone https://github.com/Yokotani-Dev/OrgOS.git
cd OrgOS

# 前バージョンのタグに戻す
git checkout v0.4.0  # 戻したいバージョン

# main を強制更新
git branch -D main
git checkout -b main
git push origin main --force

# 問題のタグを削除
git push origin :refs/tags/v0.5.0
```

### 方法2: revert コミット

```bash
# 公開リポジトリをクローン
git clone https://github.com/Yokotani-Dev/OrgOS.git
cd OrgOS

# 最新コミットをrevert
git revert HEAD --no-edit
git push origin main

# タグは残したまま（履歴を残す）
```

### 方法3: 修正版をすぐにリリース

1. 開発リポジトリで問題を修正
2. `/org-release` で patch バージョンをリリース（例: v0.5.1）
3. `/org-publish` で公開

**注意:**
- force push は利用者に影響を与える可能性がある
- 可能であれば方法3（修正版リリース）を推奨
- ロールバック後は `.ai/CHANGELOG.md` に記録を残す

## 関連コマンド

- `/org-release` - 開発リポジトリでバージョン更新・タグ作成
- `/org-export` - リリースフロー案内
- `/org-import` - 別プロジェクトでOrgOSを導入
