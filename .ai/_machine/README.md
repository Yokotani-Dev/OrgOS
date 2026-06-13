# .ai/_machine/ — 機械の実行時データ

**ここは機械（kernel / hooks / org-tools / スクリプト）が読み書きする実行時データ置き場です。人間は通常開きません。**
人間（Owner / Manager）が読む台帳・文書は `.ai/` 直下にあります（案内板: [.ai/README.md](../README.md)）。

- 配下は小文字スネークケースに統一する（ORGOS_TOBE_V3.md §4.1 原則 4）
- 新しい実行時データ置き場が必要になったら、`.ai/` 直下ではなく必ずここに作る
- 移行マップの SSOT: `.ai/DESIGN/ORGOS_TOBE_V3.md` §4.3

## サブディレクトリ一覧

| ディレクトリ | 内容 | 書き込み元 | 移行元（旧パス） |
|---|---|---|---|
| `approvals/` | Owner 承認リクエストの記録 (yaml) | `scripts/authority/request-approval.sh` / `check-approval.sh` | `.ai/APPROVALS/`（Stage 1, 2026-06-13） |
| `backups/` | ランタイムバックアップ（OS ファイル .bak、`TASKS.yaml.bak.*` 等） | `scripts/authority/backup.sh`, `scripts/tasks/archive-done.sh` | `.ai/BACKUPS/` + `.ai/TASKS.yaml.bak.*`（Stage 1, 2026-06-13） |
| `integrity/` | 整合性スキャンレポート | `scripts/integrity/scan-stale.sh` | `.ai/INTEGRITY/`（Stage 1, 2026-06-13） |
| `learnings/` | セッション学習の抽出パターン | session hooks / `/org-learn` | `.ai/LEARNED/` + `.ai/LEARNINGS/` を統合（Stage 1, 2026-06-13） |
| `os/` | OS 改善台帳（VERSION / CHANGELOG / BACKLOG / PROPOSALS=OIP） | org-os-maintainer | `.ai/OS/`（Stage 1, 2026-06-13） |
| `supervisor-review/` | 重要判断時の自動レビュードキュメント | supervisor review flow | `.ai/SUPERVISOR_REVIEW/`（Stage 1, 2026-06-13） |

## 今後ここに移動予定（Stage 2 / Stage 3 — ORGOS_TOBE_V3.md §4.4）

- Stage 2: `scheduler/` `sessions/` `events/` `metrics/` `leases/` `review/` `plans/`
- Stage 3: `artifacts/` `queue/` `intelligence/` `evolution/` `codex/` ＋ `archive/`（superseded 旧台帳の退避先）
