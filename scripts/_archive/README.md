# scripts/_archive/ — 退役スクリプト台帳

> `.claude/rules/_archive/` と同じ可逆退避パターン。削除ではなく `_archive/` 移動（`git mv`）で履歴を保つ。
> **この `_archive/` は `.orgos-manifest.yaml` に含めない**（配布対象外）。

退避日: 2026-06-13（`REPO_LAYOUT_V1.md` §3.3 の実行）
退避時の状態: 全 dir とも inbound 参照 0 を grep 実測で確認済み（自己参照を除く）。

## 退役台帳

| dir | files | 退役理由 | 後継 | 復活条件 | 削除判断日 (+90d) |
|---|---|---|---|---|---|
| `dashboard/` | 2 | 旧 Phase 2 世代の DASHBOARD 生成系 | `scripts/org/generate-dashboard.py`（`test-dashboard-generator.sh` でテスト済み） | kernel-v2 の dashboard 生成系を置換する必要が生じた場合 | 2026-09-11 |
| `tasks/` | 2 | 旧 Ruby 製タスクアーカイブ系 | `scripts/org/archive-tasks.py`（`test-archive-tasks.sh` でテスト済み） | python 後継が要件を満たせなくなった場合 | 2026-09-11 |
| `dna/` | 3 | `.ai/ORG_DNA.yaml` 登録簿の維持系。commands/rules/skills から未配線の MVP | なし（未配線） | ORG_DNA パイプラインを本配線する場合 | 2026-09-11 |
| `intel/` | 4 | 週次 Intelligence MVP。データ側 `.ai/INTELLIGENCE` 参照はあるがパイプライン本体への参照 0 | なし（未配線） | Intelligence パイプラインを本配線する場合 | 2026-09-11 |
| `journeys/` | 3 | `JOURNEYS.yaml` init/validate。journey gate は commands 側に実装済みで本系統は未配線 | commands 側 journey gate 実装 | 本系統を gate に再接続する必要が生じた場合 | 2026-09-11 |
| `integrity/` | 2 | `scan-stale.sh` 単発レポータ。参照 0 | なし | stale 検出を再導入する場合 | 2026-09-11 |

## 復活手順

```bash
git mv scripts/_archive/<dir> scripts/<dir>
# 参照を再配線し、必要なら manifest に再登録、kernel suite を green に保つ
```

## 削除レビュー

退役から 90 日（**2026-09-11**）後に復活実績がなければ、ディスクからの削除タスクを切る。
削除前に `git log --follow scripts/_archive/<dir>/` で履歴の到達性を確認する。
