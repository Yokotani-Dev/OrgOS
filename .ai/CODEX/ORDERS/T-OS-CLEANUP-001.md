# Work Order: T-OS-CLEANUP-001 — TASKS.yaml queued 棚卸し

## Task
- ID: T-OS-CLEANUP-001
- Title: 古い queued task のうち実態として完了済みのものを done 化
- Role: implementer (Codex)
- Priority: P1

## Allowed Paths (write)
- `.ai/TASKS.yaml` (status / notes フィールドのみ更新)
- `.ai/CODEX/RESULTS/T-OS-CLEANUP-001.md` (報告書)

その他のすべてのパスは **read-only**。OS 中核ファイル絶対編集禁止。

## Context

`.ai/TASKS.yaml` には status: queued が大量に残存しているが、その多くは過去に Codex / Manager が完了済 (DASHBOARD.md / CHANGELOG.md / .ai/CODEX/RESULTS/ に証拠がある)。Manager は `仕掛かり中タスクは?` の問いに正確に答えられない状況。

本タスクで queued の棚卸しを行い、**完了証拠が明確なもの** を done 化する。

## Acceptance Criteria

### A1: 全 queued task の証拠確認

`.ai/TASKS.yaml` の `status: queued` task 全件 (推定 30-50 件) について、以下の **完了証拠** を grep:

- `.ai/CODEX/RESULTS/<task_id>.md` または `.ai/CODEX/RESULTS/<task_id>.txt` が存在し、内容に "Status: DONE" または "DONE_WITH_CONCERNS" を含む
- `.ai/DASHBOARD.md` に該当 task_id が「完了」「DONE」「✅」と紐付いて記載
- `.ai/CHANGELOG.md` に該当 task_id を含む release entry が存在
- `git log --grep=<task_id>` で commit があり、かつその commit が main にマージ済

### A2: 判定ルール

| 証拠 | 判定 |
|---|---|
| RESULTS DONE + DASHBOARD mention + commit | `done` (確実) |
| RESULTS DONE + commit (DASHBOARD なし) | `done` (確実) |
| DASHBOARD のみ完了記述 | `done` (DASHBOARD 信頼) |
| commit のみ (RESULTS なし、DASHBOARD なし) | `queued` のまま (要 Manager 判断) |
| 証拠なし | `queued` のまま |

ただし以下の例外:
- `T-OS-100〜103` (aitmpl 連携): 部分実装のはず。本タスクで判定せず、Manager 判断として `notes` に追記
- `T-OS-160〜170` (SELFREVIEW gap): DASHBOARD で「DONE」と明記されている → done 化対象
- `T-OS-110〜144` (SELFREVIEW タスク群): Phase 1-5 完了とともに done のはず → DASHBOARD/CHANGELOG で確認後 done 化

### A3: TASKS.yaml の更新ルール

- `status: queued` → `status: done` に変更 (確実な場合のみ)
- 既存 `notes:` の末尾に以下を append:
  ```
  [2026-05-10 cleanup] queued → done. 証拠: <証拠の一行説明>
  ```
- それ以外のフィールド (id, title, deps, priority, owner_role, allowed_paths, autonomy_level 等) は **絶対に変更しない**

### A4: 不確実な task の報告

判定不能な task は `queued` のまま残し、`.ai/CODEX/RESULTS/T-OS-CLEANUP-001.md` の「Manager 判断必要」セクションに列挙:
- task_id / title / 探した証拠 / なぜ判定できないか

### A5: 検証

- TASKS.yaml が valid YAML を保つ (parse pass)
- queued → done に変えた task の差分は status と notes のみ
- 副作用なし (他 task / sections に影響なし)
- `bash scripts/authority/check-autonomy-coverage.sh` が引き続き PASS (autonomy fields は触らない)

## Instructions

1. まず `.ai/TASKS.yaml` 全体を read し、queued task の id 一覧を抽出
2. `.ai/DASHBOARD.md`、`.ai/CHANGELOG.md` を読んで完了済 task ID をマッピング
3. `.ai/CODEX/RESULTS/` を ls して各 task の RESULTS ファイル存在を確認
4. `git log --oneline --all | grep -i T-OS-` で commit log もチェック (option)
5. A2 の判定ルールに従い batch 更新
6. **OS 中核ファイル (CLAUDE.md, AGENTS.md, manager.md, .claude/rules/, .claude/schemas/) は read のみ**
7. **タスク本体の logic / acceptance / autonomy は touch しない**

## Report

`.ai/CODEX/RESULTS/T-OS-CLEANUP-001.md` に:
1. 棚卸し対象 task 数 (queued 全件)
2. done 化した task 数 + ID リスト
3. queued のまま残した task 数 + Manager 判断必要リスト (id / title / 理由)
4. validation 結果 (YAML parse / autonomy coverage)
5. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED

## Handoff Packet (必須)
