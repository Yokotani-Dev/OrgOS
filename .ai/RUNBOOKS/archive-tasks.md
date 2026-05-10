# Runbook: TASKS.yaml Archive

## 概要
`.ai/TASKS.yaml` から完了済みタスクを `.ai/TASKS_ARCHIVE.yaml` に移し、Manager が毎 Tick 読むタスク台帳を軽量化する。

対象は `status: done`、`status: archived`、`status: superseded` のみ。`queued`、`running`、`blocked`、`review` は移動しない。

## 前提条件
- [ ] 作業ツリーに重要な未保存変更がない、または差分を把握している
- [ ] Ruby が利用可能
- [ ] `.ai/TASKS.yaml` と `.ai/TASKS_ARCHIVE.yaml` が YAML として parse できる

## いつ実行するか
- 毎週末の台帳整理時
- 大きなフェーズ完了後
- done 化したタスクがまとまって増え、TASKS.yaml が読みづらくなった時

## 手順

### 1. Dry Run
```bash
bash scripts/tasks/archive-done.sh --dry-run
```
期待結果: 移動予定の task ID が標準出力に表示される。ファイルは変更されない。

### 2. Archive 実行
```bash
bash scripts/tasks/archive-done.sh
```
期待結果:
- `.ai/TASKS.yaml.bak.<timestamp>` が作成される
- 対象タスクが `.ai/TASKS.yaml` から削除される
- 未登録の対象タスクが `.ai/TASKS_ARCHIVE.yaml` に append される
- 標準エラーに `moved_ids` と `archived_ids` を含む JSON log が出る

### 3. 冪等性確認
```bash
bash scripts/tasks/archive-done.sh --dry-run
```
期待結果: 何も出力されない。2 回目の通常実行も no-op になる。

## 検証
- [ ] `.ai/TASKS.yaml` に `status: done`、`status: archived`、`status: superseded` が残っていない
- [ ] `.ai/TASKS_ARCHIVE.yaml` に移動済み ID が 1 回だけ存在する
- [ ] `# === ... ===` のセクションヘッダが `.ai/TASKS.yaml` に残っている
- [ ] `ruby -e 'require "yaml"; require "date"; require "time"; YAML.safe_load(File.read(".ai/TASKS.yaml"), permitted_classes: [Date, Time], aliases: true); YAML.safe_load(File.read(".ai/TASKS_ARCHIVE.yaml"), permitted_classes: [Date, Time], aliases: true)'` が成功する

## ロールバック

問題が発生した場合は、実行ログに出た backup ファイルを使う。

### 1. TASKS.yaml を復元
```bash
cp .ai/TASKS.yaml.bak.<timestamp> .ai/TASKS.yaml
```

### 2. TASKS_ARCHIVE.yaml を差分で戻す
```bash
git diff -- .ai/TASKS_ARCHIVE.yaml
```
期待結果: 今回 append された末尾ブロックを確認する。

必要なら通常のエディタで今回 append 分だけ削除する。判断に迷う場合は Manager に escalate する。

## 注意事項
- active/queued/running/review/blocked のタスクは移動対象外。
- schema 変換やタスク内容の正規化は行わない。
- cron や scheduler には登録しない。実行タイミングは Manager / Owner が判断する。
- parse error 時は no-op。ログの `error_class` と `message` を確認し、YAML を直してから再実行する。

## 履歴
| 日付 | 変更内容 | 理由 |
|------|----------|------|
| 2026-05-10 | 初版作成 | T-OS-330: TASKS.yaml アーカイブ分離自動化 |
