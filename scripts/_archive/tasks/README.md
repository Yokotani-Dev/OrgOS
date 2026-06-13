# Task Maintenance Scripts

TASKS.yaml の肥大化を抑えるための保守スクリプト群。

## archive-done.sh

`.ai/TASKS.yaml` から `status: done`、`status: archived`、`status: superseded` のタスクを抽出し、`.ai/TASKS_ARCHIVE.yaml` に移動する。

```bash
bash scripts/tasks/archive-done.sh --dry-run
bash scripts/tasks/archive-done.sh
```

### 動作

- `--dry-run` は移動対象の task ID を標準出力に出すだけで、ファイルは変更しない。
- 通常実行では `.ai/TASKS.yaml.bak.<timestamp>` を作ってから `.ai/TASKS.yaml` と `.ai/TASKS_ARCHIVE.yaml` を更新する。
- `.ai/TASKS_ARCHIVE.yaml` に既に存在する task ID は重複 append しない。
- `.ai/TASKS.yaml` 側のセクションコメントと空行は残し、該当タスクブロックだけを削除する。
- YAML parse error や unsafe path を検出した場合は no-op で停止し、JSON log を標準エラーに出す。

### Log

標準エラーに JSON 形式で処理結果を出力する。

```json
{"event":"archive_tasks","status":"completed","moved_ids":["T-001"],"archived_ids":["T-001"],"moved_count":1,"archived_count":1,"backup":".ai/TASKS.yaml.bak.20260510120000","dry_run":false}
```

`moved_ids` は TASKS.yaml から削除された ID、`archived_ids` は今回 TASKS_ARCHIVE.yaml に append された ID。
