# /org-release

OrgOSの新バージョンをリリースする。変更を自動検出し、VERSION/CHANGELOG更新 → コミット → タグ → プッシュを一括実行。

## 引数
- なし（全自動）

## 実行手順

1. **前回リリースからの変更を検出**
   ```bash
   # 最新タグを取得
   LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

   # 変更されたファイル一覧
   git diff --name-only $LAST_TAG HEAD

   # コミット履歴
   git log --oneline $LAST_TAG..HEAD
   ```

2. **変更内容を分析**
   - 新規追加されたファイル
   - 変更されたコマンド（.claude/commands/org-*.md）
   - その他の変更
   - コミットメッセージから変更の意図を把握

3. **CHANGELOG用の説明を自動生成**
   - 日本語で分かりやすく記述
   - 「追加」「改善」「修正」などカテゴリ分け

4. **バージョン番号を決定**
   - 現在のバージョンを `.ai/VERSION.yaml` から取得
   - AskUserQuestion で選択肢を提示：
     - **patch** (0.1.0 → 0.1.1): バグ修正、小さな改善
     - **minor** (0.1.0 → 0.2.0): 新機能追加
     - **major** (0.1.0 → 1.0.0): 破壊的変更

5. **確認を表示**
   ```
   以下の内容でリリースします：

   バージョン: v0.2.0

   変更内容:
   ## v0.2.0 (2025-01-19)
   ### 追加
   - `/org-release`: ワンコマンドでリリースを実行

   よろしいですか？
   ```

6. **VERSION.yaml 更新**
   ```yaml
   current: "0.2.0"
   released_at: "2025-01-19"
   history:
     - version: "0.2.0"
       date: "2025-01-19"
     # ... 既存履歴
   ```

7. **CHANGELOG.md 更新**
   - 新バージョンのセクションを先頭に追加

8. **コミット & タグ & プッシュ**
   ```bash
   git add -A
   git commit -m "Release v0.2.0"
   git tag v0.2.0
   git push origin main --tags
   ```

9. **結果報告**
   ```
   OrgOS v0.2.0 をリリースしました！

   - コミット: abc1234
   - タグ: v0.2.0
   - GitHub Actions が自動でリリースを作成中...

   確認: https://github.com/Yokotani-Dev/OrgOS-Dev/releases
   ```

## 使用例

```
/org-release
```

これだけ。引数不要。

## 前提条件
- `allow_push_main: true` が設定されていること
- mainブランチにいること

## 注意事項
- リリース後の取り消しは手動で行う必要がある
- GitHub Actionsが失敗した場合は手動で確認
- 変更がない場合はリリースしない
