---
description: OrgOS Dashboard にこのプロジェクトを登録・更新する
---

# /org-dashboard - Dashboard プロジェクト登録

このプロジェクトを OrgOS Dashboard（マルチプロジェクト統合 UI）に登録する。
既に登録済みの場合は情報を更新する。

---

## 実行手順

### 1. CONTROL.yaml を読み取り

```
CONTROL.yaml から以下を取得:
  - project_name → 表示名
  - stage → 現在のステージ
```

project_name が未設定（`<SET_ME>` のまま）の場合:
- カレントディレクトリ名をデフォルトの表示名として使用
- Owner に確認: 「プロジェクト名を設定しますか？」

### 2. プロジェクトパスを取得

```bash
PROJECT_PATH=$(pwd)
```

### 3. ~/.orgos/ ディレクトリ確認

```bash
# 存在しなければ作成
mkdir -p ~/.orgos
```

### 4. ~/.orgos/projects.yaml の読み取りまたは初期化

ファイルが存在しない場合、以下の内容で初期化:

```yaml
version: "1"
projects: []
```

### 5. 重複チェックと登録

```python
# 疑似コード
existing = find_project_by_path(projects, PROJECT_PATH)

if existing:
    # 更新
    existing.name = project_name
    existing.last_published_at = now_iso8601()
    mode = "update"
else:
    # 新規登録
    new_entry = {
        "id": generate_id(directory_name),  # ディレクトリ名をケバブケースに
        "name": project_name,
        "path": PROJECT_PATH,
        "registered_at": now_iso8601(),
        "last_published_at": now_iso8601()
    }
    projects.append(new_entry)
    mode = "register"
```

### ID 生成規則

- カレントディレクトリ名をそのまま使用
- スペースはハイフンに置換
- 英小文字に統一
- 例: `My App` → `my-app`

### 6. projects.yaml を書き込み

更新した projects.yaml を書き戻す。

### 7. 結果表示

#### 新規登録の場合

```
OrgOS Dashboard に登録しました

  プロジェクト: My App
  ID: my-app
  パス: /Users/alice/Dev/my-app
  ステージ: IMPLEMENTATION
  登録ファイル: ~/.orgos/projects.yaml

Dashboard の起動方法:
  cd orgos-dashboard && npm run dev
```

#### 更新の場合

```
OrgOS Dashboard の登録情報を更新しました

  プロジェクト: My App
  最終更新: 2026-03-30T10:00:00Z
```

---

## ~/.orgos/projects.yaml のスキーマ

```yaml
version: "1"
projects:
  - id: "my-app"                          # プロジェクト識別子
    name: "My App"                         # 表示名（CONTROL.yaml の project_name）
    path: "/Users/alice/Dev/my-app"        # リポジトリの絶対パス
    registered_at: "2026-03-30T10:00:00Z"  # 初回登録日時
    last_published_at: "2026-03-30T10:00:00Z" # 最後に登録/更新した日時
```

---

## 引数

- `--list` : 登録済みプロジェクト一覧を表示
- `--remove` : このプロジェクトを Dashboard から登録解除

### /org-dashboard --list

```
OrgOS Dashboard 登録プロジェクト一覧

| # | ID | Name | Path | 登録日 |
|---|-----|------|------|--------|
| 1 | my-app | My App | /Users/alice/Dev/my-app | 2026-03-30 |
| 2 | api-server | API Server | /Users/alice/Dev/api-server | 2026-03-29 |

合計: 2 プロジェクト
```

### /org-dashboard --remove

```
OrgOS Dashboard から登録を解除しました

  プロジェクト: My App
  パス: /Users/alice/Dev/my-app
```

---

## 関連

- 設計書: `.ai/DESIGN/DASHBOARD_ARCHITECTURE.md`
- Dashboard リポジトリ: orgos-dashboard（独立リポジトリ）
