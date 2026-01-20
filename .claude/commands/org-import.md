# /org-import

GitHub ReleasesからOrgOSをダウンロードして、現在のプロジェクトにインポートする。

## 引数
- `$ARGUMENTS`: バージョン（例: `v0.1.0`）または `latest`

## 実行手順

1. **バージョン解決**
   - `latest` の場合: 最新リリースを取得
   - `v0.x.x` の場合: 指定バージョンを使用

2. **ダウンロード**
   ```bash
   # 最新版の場合
   curl -sL https://api.github.com/repos/Yokotani-Dev/OrgOS-Dev/releases/latest \
     | grep "browser_download_url.*tar.gz" \
     | cut -d'"' -f4 \
     | xargs curl -sL -o orgos-latest.tar.gz

   # 特定バージョンの場合
   curl -sL -o orgos-v0.1.0.tar.gz \
     https://github.com/Yokotani-Dev/OrgOS-Dev/releases/download/v0.1.0/orgos-v0.1.0.tar.gz
   ```

3. **既存バージョン確認**
   - `.ai/VERSION.yaml` が存在するかチェック
   - 存在する場合、現在のバージョンと比較して表示

4. **ディレクトリ作成**
   ```bash
   mkdir -p .ai .ai/RESOURCES .ai/RESOURCES/docs \
     .ai/RESOURCES/designs .ai/RESOURCES/references \
     .ai/RESOURCES/code-samples .claude/commands
   ```

5. **展開**
   ```bash
   tar -xzf orgos-v0.1.0.tar.gz
   rm orgos-v0.1.0.tar.gz
   ```

6. **preserveファイルの確認**
   - 以下のファイルは既存なら上書きしない:
     - `.ai/PROJECT.md`
     - `.ai/TASKS.yaml`
     - `.ai/DECISIONS.md`
     - `.ai/DASHBOARD.md`
     - その他プロジェクト固有データ
   - 存在しない場合は `/org-start` で初期化を案内

7. **結果報告**
   ```
   OrgOS v0.1.0 をインポートしました。

   ソース: https://github.com/Yokotani-Dev/OrgOS-Dev/releases/tag/v0.1.0

   更新されたファイル:
   - .ai/VERSION.yaml
   - .ai/CHANGELOG.md
   - .claude/commands/org-*.md (10ファイル)
   - CLAUDE.md

   保持されたファイル（既存のため上書きなし）:
   - .ai/PROJECT.md
   - .ai/TASKS.yaml

   次のステップ:
   - 初めての導入の場合: `/org-start` でプロジェクト初期化
   - 変更内容: `.ai/CHANGELOG.md` を参照
   ```

## 使用例

```bash
# 最新版をインポート
/org-import latest

# 特定バージョンをインポート
/org-import v0.1.0
```

## 注意事項
- **CLAUDE.md は上書きされる**: プロジェクト固有の設定がある場合は事前にバックアップ推奨
- **ネットワーク必須**: GitHub にアクセスできる環境で実行
- **preserve ファイルは安全**: プロジェクト固有データは上書きされない

## リリース一覧
https://github.com/Yokotani-Dev/OrgOS-Dev/releases
