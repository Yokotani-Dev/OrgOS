# T-OS-ENC

## 修正 script 一覧
- `scripts/session/common.sh` を新規追加
- `scripts/session/bootstrap.sh`
- `scripts/session/load-ledger.sh`
- `scripts/session/bind-request.sh`
- `scripts/session/suggest-next.sh`
- `scripts/session/priority-ranker.sh`

## 実施内容
- 全 wrapper 冒頭で `common.sh` を `source` し、`LC_ALL=${LC_ALL:-en_US.UTF-8}` と `LANG` を共通設定
- 共通 helper として `ruby_utf8` / `trim_whitespace` を追加
- 全 Ruby heredoc に `# encoding: utf-8` と `Encoding.default_external/internal = Encoding::UTF_8` を追加
- YAML / file 読み込みを `File.read(..., encoding: "UTF-8")` ベースに統一
- `YAML.load_file` を UTF-8 明示の `YAML.safe_load(File.read(...))` に置換

## 実行テスト結果
- `bash scripts/session/bootstrap.sh` : 成功
- `bash scripts/session/load-ledger.sh --ledger user_profile` : 成功
- `echo "日本語依頼" | bash scripts/session/bind-request.sh` : 成功
- `bash scripts/session/suggest-next.sh` : 成功
- `bash scripts/session/priority-ranker.sh < /tmp/dummy-tasks.json` : 成功
- 追加確認 `printf 'T-OS-181 日本語依頼\n' | bash scripts/session/bind-request.sh` : 成功
- 追加確認 `bash scripts/session/suggest-next.sh --context morning --top 2` : 成功

## Python3 書き換え
- 実施せず
- Ruby 側の UTF-8 初期化と file read 明示で包括対応可能だったため

## ステータス
- DONE
