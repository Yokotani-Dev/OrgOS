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
| `codex.auto_exec` | v0.14.0 | `true` |
| `codex.sandbox` | v0.14.0 | `"workspace-write"` |
| `codex.approval` | v0.14.0 | `"on-request"` |

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

### 8. ユーザー影響の変更を抽出

CHANGELOG.md を解析し、**ユーザー体験に影響する変更**を抽出する。

#### 8.1 抽出対象

| カテゴリ | 例 |
|----------|-----|
| **新コマンド** | `/org-settings` が追加 |
| **コマンド削除** | `/org-plan` が `/org-tick` に統合 |
| **操作方法の変更** | 「基本的に `/org-tick` だけ実行すればOK」 |
| **設定項目の追加** | `owner_literacy_level` が追加 |
| **重要な改善** | 「対話形式でBRIEF.md自動生成」 |

#### 8.2 抽出ロジック

```python
# 疑似コード
def extract_user_facing_changes(changelog, from_version, to_version):
    changes = []
    keywords = [
        "新コマンド", "コマンド追加", "追加",
        "削除", "廃止", "統合",
        "操作方法", "使い方",
        "設定", "CONTROL.yaml",
    ]

    for version in get_versions_between(from_version, to_version):
        section = changelog.get_section(version)

        # 「追加」セクションから新コマンドを抽出
        if has_new_commands(section):
            changes.append(extract_commands(section))

        # 「削除」セクションから廃止コマンドを抽出
        if has_deleted_commands(section):
            changes.append(extract_deletions(section))

        # 「設計変更」から操作方法の変更を抽出
        if has_design_changes(section):
            changes.append(extract_design_changes(section))

    return changes
```

### 9. 結果報告

**アップグレードの場合（既存バージョンから更新）:**

```
✅ OrgOS $CURRENT → $VERSION にアップグレードしました。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🆕 ユーザー体験に影響する変更
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

【新しいコマンド】
• `/org-settings` - レビュー頻度やリテラシーレベルの設定変更

【操作方法の変更】
• 基本的に `/org-tick` だけ実行すればOK（エージェント自動選択）
• 以下のコマンドは `/org-tick` に統合されました:
  - /org-plan, /org-review, /org-integrate, /org-codex 等

【新しい設定項目】
• `owner_literacy_level` - ITリテラシーレベル（beginner/intermediate/advanced）
• `owner_review_policy.mode` - レビュー頻度モード

【改善点】
• `/org-start` が対話形式に改善（4ステップで開始可能）
• 専門用語に説明が付くようになりました（リテラシー適応）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

更新されたファイル:
- .ai/VERSION.yaml
- .ai/CHANGELOG.md
- .claude/commands/org-*.md
- CLAUDE.md

マイグレーションした設定:
- owner_literacy_level: "intermediate"（新規追加）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Codex CLI セットアップ（v0.14.0〜）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

コーディング・レビューに Codex CLI を使用するようになりました。
未セットアップの場合は以下を実行してください:

  npm install -g @openai/codex
  codex --login

※ ChatGPT Plus/Pro/Team アカウントが必要です

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Claude Code の再起動が必要です
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

新しいスラッシュコマンドを反映するため、Claude Code を再起動してください。

[A] 今すぐ再起動する（推奨）
    → VS Code: Cmd+Shift+P → "Developer: Reload Window"
    → CLI: このセッションを終了して新しいセッションを開始

[B] あとで再起動する
    → 再起動するまで、古いコマンドがサジェストに残ります
    → 再起動手順: 上記 [A] と同じ

📌 次はこちら:
   再起動後 → /org-settings で新しい設定項目を確認
   └─ 変更不要なら: /org-tick で通常作業を再開
```

**新規インストールの場合:**

```
✅ OrgOS $VERSION をインストールしました。

ソース: https://github.com/Yokotani-Dev/OrgOS/releases/tag/$VERSION

初期化されたファイル:
- .ai/BRIEF.md
- .ai/CONTROL.yaml
- .ai/DASHBOARD.md
- .ai/OWNER_INBOX.md
- .ai/OWNER_COMMENTS.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Codex CLI セットアップ（コーディング・レビュー用）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OrgOS はコーディングとレビューに OpenAI Codex CLI を使用します。
以下の手順でセットアップしてください:

1. Codex CLI をインストール
   npm install -g @openai/codex

2. ChatGPT にログイン
   codex --login

   ※ ChatGPT Plus/Pro/Team アカウントが必要です
   ※ ブラウザが開くので、ChatGPT アカウントでログインしてください

3. 動作確認
   codex exec "echo hello"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Claude Code の再起動が必要です
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

新しいスラッシュコマンドを反映するため、Claude Code を再起動してください。

[A] 今すぐ再起動する（推奨）
    → VS Code: Cmd+Shift+P → "Developer: Reload Window"
    → CLI: このセッションを終了して新しいセッションを開始

[B] あとで再起動する
    → 再起動するまで、古いコマンドがサジェストに残ります
    → 再起動手順: 上記 [A] と同じ

📌 次はこちら:
   再起動後 → /org-start で対話形式のプロジェクト初期化（約4ステップ）
```

**同一バージョンの場合:**

```
ℹ️ 現在のバージョン ($VERSION) が最新です。

変更はありません。

📌 次はこちら: /org-tick
   通常作業を継続します
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
