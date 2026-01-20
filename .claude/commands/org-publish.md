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

### 5. コミット & タグ & プッシュ

```bash
git add -A
git commit -m "Release v${VERSION}"
git tag v${VERSION}
git push origin main --tags
```

### 6. クリーンアップ

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

## 関連コマンド

- `/org-release` - 開発リポジトリでバージョン更新・タグ作成
- `/org-export` - リリースフロー案内
- `/org-import` - 別プロジェクトでOrgOSを導入
