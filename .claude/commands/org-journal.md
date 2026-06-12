---
description: 全リポジトリ横断の実行ログ（Central Activity Ledger）の日次ダイジェスト表示
---

# /org-journal - 横断アクティビティジャーナル

全 OrgOS リポジトリの実行ログは中央ストア（`~/.orgos/activity/events-YYYYMM.jsonl`）に集約される。
このコマンドはそのダイジェストを表示し、「今日、全リポジトリで何をやったか・何を考えたか」を 1 箇所で見られるようにする。

---

## 使い方

```
/org-journal              # 今日のダイジェスト
/org-journal today        # 同上
/org-journal 2026-06-10   # 指定日のダイジェスト
/org-journal --days 7     # 直近 7 日のダイジェスト
```

---

## 動作

引数に応じて `scripts/activity/journal.sh` を実行し、結果を整形して提示する:

```bash
bash scripts/activity/journal.sh today              # 引数なし or today
bash scripts/activity/journal.sh --date 2026-06-10  # 日付指定
bash scripts/activity/journal.sh --days 7           # 期間指定
```

出力は Markdown ダイジェスト（サマリ / 💭 考えたこと / ⚙️ 実行したこと（リポジトリ別））。
Manager は出力をそのまま、または Owner のリテラシーレベルに合わせて要約して提示する。

> MCP サーバ `orgos-journal` が登録済みの環境では、`journal_get` / `activity_search`
> ツールでも同じデータを参照できる（どのリポジトリ・プロジェクトからでも利用可）。

---

## 記録規約（Manager 必須）

**どの OrgOS リポジトリで作業していても**、Manager は顕著な行動を
`scripts/activity/log-event.sh` で中央ストアへ記録する。配布クローンにも同スクリプトが含まれる。

### 記録対象と実行例

1. **タスク完了** (`task_done`):

```bash
bash scripts/activity/log-event.sh --type task_done --task-id T-OS-482 \
  --title "Activity Ledger writer/journal を実装"
```

2. **重要な判断** (`decision`):

```bash
bash scripts/activity/log-event.sh --type decision \
  --title "ストア形式は JSONL を採用" --detail "追記専用で並行書込に強いため"
```

3. **Owner のメモ・気づき** (`note`):

```bash
bash scripts/activity/log-event.sh --type note \
  --title "ダッシュボードに Journal タブを追加したい"
```

### 補足

- `--type` enum: `session_start | session_end | task_created | task_done | decision | note | thought | commit | tick | release | kernel`
- session_start / session_end は hook が自動記録するため手動記録は不要
- 記録は失敗してもセッションを止めない（エラーは `~/.orgos/activity/errors.log` へ）
- secret（APIキー等）を title / detail に書かない（自動 redact はあくまで保険）
- MCP サーバ利用時は `activity_log(type, title, detail?, task_id?)` ツールでも記録できる

設計書: [.ai/DESIGN/ACTIVITY_LEDGER.md](../../.ai/DESIGN/ACTIVITY_LEDGER.md)
