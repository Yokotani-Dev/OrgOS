# /org-import

公開リポジトリ (OrgOS) からOrgOSをダウンロードして、現在のプロジェクトにインポートする。

## 引数
- `$ARGUMENTS`: バージョン（例: `v0.1.0`）または `latest`（省略時は latest）

## 概要

```
Yokotani-Dev/OrgOS (public)  ──→  Your Project
       │                               │
       └─ core files                   └─ /org-import
          templates                       (インポート)
```

## 実行手順

### 1. バージョン解決

```bash
# 最新タグを取得
LATEST_TAG=$(git ls-remote --tags https://github.com/Yokotani-Dev/OrgOS.git \
  | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | sort -V | tail -1)

# latest の場合は最新タグを使用
# 指定バージョンの場合はそのまま使用
VERSION=${ARGUMENTS:-$LATEST_TAG}
```

### 2. 既存バージョン確認

```bash
# 既存の .ai/VERSION.yaml を確認
if [ -f ".ai/VERSION.yaml" ]; then
  CURRENT=$(grep "current:" .ai/VERSION.yaml | cut -d'"' -f2)
  echo "現在のバージョン: $CURRENT"
  echo "インポートするバージョン: $VERSION"
fi
```

### 3. 一時ディレクトリでクローン

```bash
WORK_DIR=$(mktemp -d)
cd $WORK_DIR
git clone --depth 1 --branch $VERSION https://github.com/Yokotani-Dev/OrgOS.git
```

### 4. ディレクトリ作成

```bash
# プロジェクトディレクトリに戻り、必要なディレクトリを作成
mkdir -p .ai .ai/RESOURCES .ai/RESOURCES/docs \
  .ai/RESOURCES/designs .ai/RESOURCES/references \
  .ai/RESOURCES/code-samples .claude/commands .claude/agents
```

### 5. ファイルコピー

`.orgos-manifest.yaml` の `core` セクションに定義されたファイルをコピー。

**上書きするファイル（core）:**
- `.ai/VERSION.yaml`
- `.ai/CHANGELOG.md`
- `.ai/RESOURCES/README.md`
- `.claude/commands/org-*.md`
- `.orgos-manifest.yaml`
- `CLAUDE.md`

**保持するファイル（preserve）:**
- `.ai/PROJECT.md`
- `.ai/TASKS.yaml`
- `.ai/DECISIONS.md`
- `.ai/RISKS.md`
- `.ai/DASHBOARD.md`
- `.ai/OWNER_INBOX.md`
- `.ai/OWNER_COMMENTS.md`
- `.ai/CONTROL.yaml`
- `.ai/STATUS.yaml`
- `.ai/RUN_LOG.md`

**初回のみコピー（templates）:**
存在しない場合のみ、テンプレートからコピー:
- `.ai/TEMPLATES/BRIEF.md` → `.ai/BRIEF.md`
- `.ai/TEMPLATES/CONTROL.yaml` → `.ai/CONTROL.yaml`
- `.ai/TEMPLATES/DASHBOARD.md` → `.ai/DASHBOARD.md`
- `.ai/TEMPLATES/OWNER_INBOX.md` → `.ai/OWNER_INBOX.md`
- `.ai/TEMPLATES/OWNER_COMMENTS.md` → `.ai/OWNER_COMMENTS.md`

### 6. 設定のマイグレーション（既存プロジェクト向け）

保持された `.ai/CONTROL.yaml` に、新バージョンで追加された設定項目を追加する。

#### 6.1 マイグレーション対象

| 設定項目 | 追加バージョン | デフォルト値 |
|----------|---------------|-------------|
| `owner_review_policy.mode` | v0.6.0 | 既存の `every_n_tasks` から推測 |
| `owner_review_policy.tasks_since_last_review` | v0.6.0 | `0` |
| `owner_literacy_level` | v0.5.0 | `"intermediate"` |

#### 6.2 マイグレーションロジック

```python
# 疑似コード
def migrate_control_yaml(control):
    migrated = []

    # owner_review_policy.mode のマイグレーション
    if 'owner_review_policy' in control:
        if 'mode' not in control['owner_review_policy']:
            # 既存の every_n_tasks があれば every_n_tasks モード
            if control['owner_review_policy'].get('every_n_tasks'):
                control['owner_review_policy']['mode'] = "every_n_tasks"
            else:
                control['owner_review_policy']['mode'] = "every_tick"
            migrated.append("owner_review_policy.mode")

        if 'tasks_since_last_review' not in control['owner_review_policy']:
            control['owner_review_policy']['tasks_since_last_review'] = 0
            migrated.append("owner_review_policy.tasks_since_last_review")
    else:
        # セクション全体を追加（テンプレートから）
        control['owner_review_policy'] = {
            'mode': "every_n_tasks",
            'every_n_tasks': 3,
            'on_stage_transition': True,
            'always_before_merge_to_main': True,
            'always_before_release': True,
            'tasks_since_last_review': 0
        }
        migrated.append("owner_review_policy（全体）")

    # owner_literacy_level のマイグレーション
    if 'owner_literacy_level' not in control:
        control['owner_literacy_level'] = "intermediate"
        migrated.append("owner_literacy_level")

    return migrated
```

#### 6.3 マイグレーション結果の記録

マイグレーションが発生した場合、結果報告に含める。

### 7. クリーンアップ

```bash
rm -rf $WORK_DIR
```

### 8. 結果報告

```
OrgOS $VERSION をインポートしました。

ソース: https://github.com/Yokotani-Dev/OrgOS/releases/tag/$VERSION

更新されたファイル:
- .ai/VERSION.yaml
- .ai/CHANGELOG.md
- .claude/commands/org-*.md (15ファイル)
- CLAUDE.md

保持されたファイル（既存のため上書きなし）:
- .ai/PROJECT.md
- .ai/TASKS.yaml

初期化されたファイル（新規作成）:
- .ai/BRIEF.md
- .ai/CONTROL.yaml
- .ai/DASHBOARD.md

マイグレーションした設定（既存CONTROLに追加）:
- owner_review_policy.mode: "every_n_tasks"（既存値から推測）
- owner_review_policy.tasks_since_last_review: 0
- owner_literacy_level: "intermediate"

次のステップ:
- 初めての導入の場合: `/org-start` でプロジェクト初期化
- 設定を変更したい場合: `/org-settings` で調整
- 変更内容: `.ai/CHANGELOG.md` を参照
```

## 使用例

```bash
# 最新版をインポート
/org-import latest

# 特定バージョンをインポート
/org-import v0.5.0

# バージョン省略（= latest）
/org-import
```

## 注意事項

- **CLAUDE.md は上書きされる**: プロジェクト固有の設定がある場合は事前にバックアップ推奨
- **ネットワーク必須**: GitHub にアクセスできる環境で実行
- **preserve ファイルは安全**: プロジェクト固有データは上書きされない
- **初回のみテンプレート展開**: BRIEF.md等は既存があれば上書きしない

## リリース一覧

https://github.com/Yokotani-Dev/OrgOS/releases
