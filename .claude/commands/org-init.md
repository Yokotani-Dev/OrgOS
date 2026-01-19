# /org-init

OrgOSをクローンした後の初期セットアップ。元リポジトリから切断し、新しいプロジェクト用リポジトリに接続する。

## 引数
- なし

## 実行手順

1. **現在のリモート確認**
   ```bash
   git remote -v
   ```

2. **OrgOS-Dev リポジトリかどうか確認**
   - origin が `OrgOS-Dev` を含む場合 → 次のステップへ
   - それ以外 → 既に切断済み、`/org-start` へ進む

3. **AskUserQuestion で選択肢を提示**
   ```
   質問: OrgOS-Dev リポジトリに接続されています。どうしますか？

   選択肢:
   - 切断して新しいプロジェクトを始める
   - 管理者コードを入力（OrgOS開発者用）
   ```

4. **「管理者コードを入力」の場合**
   - ユーザーにコード入力を求める
   - `0417` が入力されたら:
     - `.ai/CONTROL.yaml` に `is_orgos_dev: true` を設定
     - 「OrgOS開発モードを有効にしました」と表示
     - 処理終了（`/org-start` は呼ばない）
   - 不正なコードの場合:
     - 「管理者コードが正しくありません」と表示
     - 選択肢に戻る

5. **「切断して新しいプロジェクト」の場合 → 切断**
   ```bash
   git remote remove origin
   ```

6. **新しいリポジトリURLを聞く（AskUserQuestion）**
   ```
   質問: 新しいプロジェクトのリポジトリURLを入力してください

   選択肢:
   - 今すぐ入力する
   - 後で設定する（スキップ）
   ```

7. **「今すぐ入力する」の場合**
   - テキスト入力で URL を受け取る
   - 例: `https://github.com/you/my-project.git`
   ```bash
   git remote add origin <入力されたURL>
   ```

8. **初期プッシュの確認**
   ```
   質問: 新しいリポジトリに初期プッシュしますか？

   選択肢:
   - はい、今すぐプッシュ
   - いいえ、後で手動でプッシュ
   ```

9. **「はい」の場合**
   ```bash
   git push -u origin main
   ```

10. **`/org-start` を自動実行**
    - リポジトリ設定完了後、そのまま `/org-start` を呼び出す
    - プロジェクト固有の `.ai/` ファイルを初期化
    - BRIEF.md のヒアリングへ進む

## 使用例

```bash
# 1. OrgOSをクローン
git clone https://github.com/Yokotani-Dev/OrgOS-Dev.git my-new-project
cd my-new-project

# 2. Claude Codeを開いて実行
/org-init

# 3. 対話形式で設定 → 自動で /org-start へ
#    - 切断して新しいプロジェクト → 選択
#    - 新リポURL → https://github.com/me/my-new-project.git
#    - 初期プッシュ → はい
#    - → /org-start が自動実行される
```

## OrgOS開発者の場合

```bash
/org-init
# → 「管理者コードを入力」を選択
# → 0417 を入力
# → OrgOS開発モードが有効になり、以降警告が出なくなる
```

## 注意事項
- 管理者コード `0417` はOrgOS開発者専用
- リポジトリURLは後から `git remote add origin <URL>` で設定可能
- GitHub でリポジトリを事前に作成しておく必要がある
