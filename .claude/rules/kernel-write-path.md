# 正規書込パス（Kernel Write Path）— Iron Law

> kernel v2 は保護状態ファイルへの直接 Edit/Write と raw `git commit` を deny する（`StateMutationViaOrgTool=enforce` / `IntegratorOnlyCommit=enforce`）。
> 本ファイルが「保護された状態をどう変更するか」の唯一の正規リファレンスである。deny されたら回避ではなく、ここに書かれた正規パスに切り替える。

## Iron Law

1. 保護状態ファイル（`.ai/TASKS.yaml` `.ai/DECISIONS.md` `.ai/DASHBOARD.md` `.ai/STATUS.md` `.ai/CONTROL.yaml` `.ai/OWNER_INBOX.md` `.ai/OWNER_COMMENTS.md` `.ai/RISKS.md` `.ai/RUN_LOG.md` `.ai/EVENTS.jsonl`）への Edit/Write は禁止。下表の org-tool 経由のみ。
2. `git commit` / `git push` / `merge` / `rebase` / `pull` は禁止。commit は integrator フロー（`request-integration.sh` → `integrator-commit.sh`）のみ。
3. **Bash 経由の書込（heredoc / `cat >>` / `echo >` / `sed -i` / `tee`）で保護ファイルを変更することは、hook が現状検出しなくても Iron Law 違反である。**「Bash なら通る」は合理化（`.claude/rules/rationalization-prevention.md`）。
4. `*.generated.*` ファイルは手動編集禁止。生成スクリプトの再実行のみ。
5. 例外なし。

## 状態変更 → 正規ツール対応表

| 変更したい状態 | 正規ツール |
|---|---|
| タスク作成 | `scripts/org/update-task.py --create` |
| タスク status / フィールド更新 | `scripts/org/update-task.py --set FIELD=VALUE` |
| タスク notes 追記 | `scripts/org/update-task.py --add-note` |
| 決定記録（DECISIONS.md）追記 | `scripts/org/append-decision.py` |
| プログラムイベント追記 | `scripts/org/append-event.py`（hash-chained `.ai/_machine/events/`） |
| ダッシュボード更新 | `scripts/org/generate-dashboard.py`（再生成のみ） |
| commit / 統合 | `scripts/org/request-integration.sh` → `scripts/org/integrator-commit.sh` |
| 書込権（lease）取得/解放 | `scripts/org/acquire-lease.sh` / `release-lease.sh` / `list-leases.sh` |

## コマンド例（コピペ用）

### タスク（.ai/TASKS.yaml）

```bash
python3 scripts/org/update-task.py --list-ids                      # ID 一覧
python3 scripts/org/update-task.py T-OS-XXX --create \
  --title "タイトル" --status queued --priority P1                 # 作成
python3 scripts/org/update-task.py T-OS-XXX --set status=running   # status 変更
python3 scripts/org/update-task.py T-OS-XXX --set status=done \
  --add-note "2026-06-11 完了: 検証コマンドと結果"                  # 完了 + note
```

### 決定記録（.ai/DECISIONS.md）

```bash
python3 scripts/org/append-decision.py --id PLAN-UPDATE-025 \
  --title "タスク追加" --body $'### 変更内容\n- 追加: T-OS-XXX\n\n### 理由\n- ...'
# 長文は --body-file PATH または --body-file -（stdin）
```

### プログラムイベント（.ai/_machine/events/ 月次 JSONL）

```bash
python3 scripts/org/append-event.py --event-type TaskUpdated \
  --task-id T-OS-XXX --actor-role manager --actor-id claude-manager \
  --payload-json '{"status":"done"}'
# event-type: TaskCreated/TaskUpdated/WorkerStarted/WorkerFinished/
#   VerificationPassed/VerificationFailed/CommitIntegrated 等（--help 参照）
```

### ダッシュボード

```bash
python3 scripts/org/generate-dashboard.py           # 再生成
python3 scripts/org/generate-dashboard.py --check   # 差分検証のみ（書込なし）
```

### commit（integrator フロー）

raw `git commit` の唯一の代替。worktree 内の編集を main 系に反映する手順:

```bash
# 1. lease 取得（Edit/Write の前。allowed_paths が integration 時の差分検査に使われる）
LEASE_ID=$(bash scripts/org/acquire-lease.sh --task-id T-OS-XXX \
  --actor-role manager --actor-id claude-manager \
  --allowed-paths "docs/,scripts/org/")

# 2. lease の allowed_paths 内で編集作業を行う

# 3. artifact 収集 + manifest 検証
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-T-OS-XXX"
bash scripts/org/collect-artifacts.sh --task-id T-OS-XXX --run-id "$RUN_ID" \
  --worktree-path "$(pwd)" --artifact-dir ".ai/_machine/artifacts/T-OS-XXX/$RUN_ID" \
  --actor-role manager --actor-id claude-manager
python3 scripts/org/verify-artifact-manifest.py ".ai/_machine/artifacts/T-OS-XXX/$RUN_ID/artifact_manifest.json"

# 4. integration request（queue 投入）
bash scripts/org/request-integration.sh --task-id T-OS-XXX \
  --worktree-path "$(pwd)" --branch task/T-OS-XXX-slug --base-branch main \
  --artifact-manifest ".ai/_machine/artifacts/T-OS-XXX/$RUN_ID/artifact_manifest.json" \
  --commit-message "feat: ..."

# 5. integrator が commit（author: OrgOS Integrator）
bash scripts/org/integrator-commit.sh --task-id T-OS-XXX

# 6. lease 解放
bash scripts/org/release-lease.sh "$LEASE_ID" --reason done
```

lease が必要になるのは: (a) 非保護ファイルへの Edit/Write（`LeaseBeforeWrite`、現在 warn）、(b) integrator の allowed_paths 差分検査（lease 外の変更は integration 失敗）。実行例の全文は `docs/kernel-v2/dogfood-checklist.md` を参照。

## 禁止される直接編集とその代替

| ❌ 禁止される操作 | ✅ 正規の代替 |
|---|---|
| Edit/Write `.ai/TASKS.yaml` | `python3 scripts/org/update-task.py` |
| Edit/Write `.ai/DECISIONS.md` / `cat >> .ai/DECISIONS.md` | `python3 scripts/org/append-decision.py` |
| Edit/Write `.ai/DASHBOARD.md` `.ai/STATUS.md` `.ai/RUN_LOG.md` | `generate-dashboard.py` 再生成 + イベントは `append-event.py` |
| `echo ... >> .ai/EVENTS.jsonl` / events 直書き | `python3 scripts/org/append-event.py` |
| `git commit` / `git push` | `request-integration.sh` → `integrator-commit.sh` |
| `git merge` / `rebase` / `pull` / `checkout main` | integrator フロー（protected branch は no-touch） |
| heredoc / `sed -i` / `tee` で保護ファイル書込 | 該当する org-tool（hook 未検出でも違反） |
| `*.generated.*` の手動編集 | 生成スクリプトの再実行 |

## 関連

- 検出実体: `.claude/hooks/policy_core.py` / モード: `.claude/state/kernel-mode.json`
- bootstrap 期の逸脱記録（enforce 後は禁止）: `.ai/BOOTSTRAP-OVERRIDES.md`
- 実運用ログ: `docs/kernel-v2/dogfood.md`
