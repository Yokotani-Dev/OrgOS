# scripts/org/ — kernel-v2 org-tools（正規書込パスの道具箱）

> **台帳を触る時はここだけ。** これらは kernel write path（`.claude/rules/kernel-write-path.md`）の正規ツールであり、保護状態ファイル（`.ai/TASKS.yaml` `.ai/DECISIONS.md` `.ai/DASHBOARD.md` ほか）への直接 Edit/Write は kernel が deny する。変更は必ずこの道具を経由する。

`org/` という名は汎用的に見えるが、実体は「OrgOS 台帳 mutation の唯一の正規経路」である（`REPO_LAYOUT_V1.md` §3.1: 258 参照 / 41 ファイル横断のため改名せず KEEP）。

## 主なツール

| やりたいこと | ツール |
|---|---|
| タスク作成・更新・note 追記 | `update-task.py`（`--create` / `--set` / `--add-note`） |
| 決定記録（DECISIONS.md）追記 | `append-decision.py` |
| プログラムイベント追記（hash-chained） | `append-event.py` |
| ダッシュボード再生成 | `generate-dashboard.py` |
| 完了タスクのアーカイブ | `archive-tasks.py`（旧 `scripts/tasks/archive-done.sh` の後継） |
| 書込権（lease）取得/解放 | `acquire-lease.sh` / `release-lease.sh` / `list-leases.sh` |
| commit / 統合 | `request-integration.sh` → `integrator-commit.sh` |
| artifact 収集・検証 | `collect-artifacts.sh` / `verify-artifact-manifest.py` |

## 関連

- 正規書込パスの全体: `.claude/rules/kernel-write-path.md`
- 検出実体: `.claude/hooks/policy_core.py` / モード: `.claude/state/kernel-mode.json`
- 実運用ログ: `docs/kernel-v2/dogfood.md`
