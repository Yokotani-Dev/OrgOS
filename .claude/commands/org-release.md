# /org-release

OrgOSの新バージョンをリリースする。変更を自動検出し、VERSION/CHANGELOG更新 → コミット → タグ → プッシュを一括実行。

## 引数
- なし（全自動）

## 実行手順

### 0. **リリース前バリデーション（デグレ防止）**

以下のチェックを実行し、すべてパスしないとリリースを中止する。

```python
import yaml
import os
import sys
import re

def validate_release():
    errors = []
    warnings = []

    # 1. manifest構造チェック
    with open('.orgos-manifest.yaml', 'r') as f:
        manifest = yaml.safe_load(f)

    required_sections = ['version_file', 'publish', 'core']
    for section in required_sections:
        if section not in manifest:
            errors.append(f"manifest missing: {section}")

    # 2. publishファイル存在チェック
    for file_path in manifest.get('publish', []):
        if not os.path.exists(file_path):
            errors.append(f"publish file missing: {file_path}")

    # 3. coreファイル存在チェック
    for file_path in manifest.get('core', []):
        if not os.path.exists(file_path):
            errors.append(f"core file missing: {file_path}")

    # 4. VERSION.yaml形式チェック
    with open('.ai/VERSION.yaml', 'r') as f:
        version = yaml.safe_load(f)

    if not re.match(r'^\d+\.\d+\.\d+$', version.get('current', '')):
        errors.append(f"invalid version format: {version.get('current')}")

    # 5. 前バージョンから削除されたファイルの検出
    # git diff で削除ファイルを検出
    # 警告として表示

    return errors, warnings
```

**チェック項目:**
| チェック | 失敗時 |
|----------|--------|
| manifest構造 | ❌ リリース中止 |
| publishファイル存在 | ❌ リリース中止 |
| coreファイル存在 | ❌ リリース中止 |
| VERSION.yaml形式 | ❌ リリース中止 |
| 削除ファイル検出 | ⚠️ 警告表示 |

すべてのチェックがパスした場合のみ、以下に進む。

---

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
