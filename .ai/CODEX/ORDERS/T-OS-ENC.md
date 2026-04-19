# Work Order: T-OS-ENC

## Task
- ID: T-OS-ENC
- Title: 全 session scripts の multibyte encoding 包括修正
- Role: implementer
- Priority: P0

## Allowed Paths
- `scripts/session/*.sh` (全編集)
- `.ai/CODEX/RESULTS/T-OS-ENC.md`

## Context

T-OS-181F / T-OS-181F2 で bind-request.sh は修正済み。
しかし suggest-next.sh / priority-ranker.sh も同じ問題を持つ (T-OS-182 成果物):

```
bash scripts/session/suggest-next.sh
# -:27: invalid multibyte char (US-ASCII) (大量)
```

Ruby 実装で日本語 (.ai/DECISIONS.md, USER_PROFILE.yaml 等) を読み込む scripts は全て対応必要。

## Acceptance Criteria

### E1: scripts/session/ 全 .sh を点検
対象:
- bootstrap.sh (既に正常動作、念のため確認)
- load-ledger.sh (確認)
- bind-request.sh (既に修正済み)
- similarity-score.sh (存在すれば)
- suggest-next.sh (**バグ確認済み**)
- priority-ranker.sh (未検証、おそらくバグあり)

### E2: 統一的 encoding 対応
以下を全 Ruby script で適用:
- 冒頭に `# encoding: utf-8` magic comment
- スクリプト冒頭で `Encoding.default_external = Encoding::UTF_8; Encoding.default_internal = Encoding::UTF_8`
- 全 `File.read` / `File.open` に `encoding: "UTF-8"` (or `"r:UTF-8"`)
- 呼び出し時 env: `LC_ALL=en_US.UTF-8` or `ja_JP.UTF-8`
- bash wrapper で `export LC_ALL=${LC_ALL:-en_US.UTF-8}` を全スクリプト先頭に追加

### E3: 検証 (全スクリプト日本語入力 OK)
```bash
bash scripts/session/bootstrap.sh
bash scripts/session/load-ledger.sh --ledger user_profile
echo "日本語依頼" | bash scripts/session/bind-request.sh
bash scripts/session/suggest-next.sh
bash scripts/session/priority-ranker.sh < /tmp/dummy-tasks.json  # 存在すれば
```

全て成功 (日本語含む出力) すること。

### E4: Python3 書き換え判断
Ruby での対応が複雑になる場合、Python3 に書き換える (UTF-8 default で堅牢)。
ただし既存 script の外部インターフェース (stdin/stdout/arg) は変えない。

### E5: 共通基盤
`scripts/session/common.sh` を新規作成 (既存あれば編集):
- LC_ALL 設定
- Ruby encoding 設定
- 共通 parse helper

各スクリプト冒頭で `source` する。

## Instructions

1. scripts/session/ 全 .sh を ls する
2. 各スクリプトを試験実行、エラー確認
3. 包括修正
4. 4-5 ケース日本語入力テスト
5. **重要**: 他ディレクトリ編集禁止

## Report

`.ai/CODEX/RESULTS/T-OS-ENC.md`:
1. 修正 script 一覧
2. 実行テスト結果 (5 ケース全成功確認)
3. Python3 書き換えの有無
4. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED
