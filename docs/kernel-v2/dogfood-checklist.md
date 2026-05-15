# T-OS-418 Manager Dogfood Checklist

> Manager (Claude) が新フローで実 commit を 1 件成功させるための実施チェックリスト。
> 5th-round GPT-5.5 Q25 dry-run の要件を満たす。enforce flip 前の最終 gate。

## 目的

「Integrator Gate / Lease Registry が動くこと」は KRT で証明済み。本 task は
**OrgOS が実運用できること**を Manager 自身の commit で証明する。

## 前提条件

- [ ] T-OS-416 (bypass fix) committed
- [ ] T-OS-417 (TASKS.yaml validator + update-task.py) committed
- [ ] T-OS-419 (Codex handoff sandbox) committed
- [ ] T-OS-420 (per-invariant mode) committed (推奨、必須ではない)
- [ ] T-OS-421 (policy_core split) committed (推奨、必須ではない)

## Dogfood task の content

Commit する内容: 本 file (`docs/kernel-v2/dogfood-checklist.md`) を含む dogfood ドキュメント。

つまり「このチェックリスト自体を新フローで commit する」のが dogfood の content。

## Manager 実行手順 (新フロー)

### Step 1: Lease 取得

```bash
LEASE_ID=$(bash scripts/org/acquire-lease.sh \
  --task-id T-OS-418 \
  --actor-role manager \
  --actor-id "claude-opus-4.7" \
  --allowed-paths "docs/kernel-v2/")
echo "Lease: $LEASE_ID"
```

期待: `LS-<ts>-T-OS-418-<8hex>` が stdout、`.ai/leases/$LEASE_ID.json` 生成。

### Step 2: Edit (lease 内 path)

`docs/kernel-v2/dogfood.md` を作成 (本 checklist の実行ログ)。

```bash
cat > docs/kernel-v2/dogfood.md <<EOF
# T-OS-418 Dogfood Execution Log

Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Actor: Manager (Claude Opus 4.7)
Lease: $LEASE_ID

## Step results
(filled in as we go)
EOF
```

期待: file 作成成功 (lease 内なので pretool 通過)。

### Step 3: Artifact collection

```bash
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-T-OS-418-$(uuidgen | tr 'A-F' 'a-f' | cut -c1-8)"
bash scripts/org/collect-artifacts.sh \
  --task-id T-OS-418 \
  --run-id "$RUN_ID" \
  --worktree-path "$(pwd)" \
  --artifact-dir ".ai/artifacts/T-OS-418/$RUN_ID" \
  --actor-role manager \
  --actor-id "claude-opus-4.7"
```

期待: `.ai/artifacts/T-OS-418/$RUN_ID/artifact_manifest.json` 生成、sha256 等で validate 可能。

### Step 4: Manifest verification

```bash
python3 scripts/org/verify-artifact-manifest.py ".ai/artifacts/T-OS-418/$RUN_ID/artifact_manifest.json"
```

期待: exit 0。

### Step 5: Request integration

```bash
QUEUE_PATH=$(bash scripts/org/request-integration.sh \
  --task-id T-OS-418 \
  --worktree-path "$(pwd)" \
  --branch main \
  --base-branch main \
  --artifact-manifest ".ai/artifacts/T-OS-418/$RUN_ID/artifact_manifest.json" \
  --commit-message "docs(kernel-v2): T-OS-418 Manager dogfood execution log")
echo "Queue: $QUEUE_PATH"
```

⚠️ **branch=main で request できるか確認**。本 task の content が main branch 上で実行されるため。**もし request-integration.sh が protected branch を拒否するなら**:
- (a) 別 branch を切ってから本 dogfood をやり直す
- (b) request-integration.sh の protected branch check を一時 disable
- (c) 本 commit は手動で example として extract、別途 task branch で commit

推奨は (a) — 新フローの本来の使い方。

### Step 5b: branch を切ってから retry (5 で blocked された場合)

```bash
git checkout -b task/T-OS-418-dogfood
# 既存の edit + lease + artifact は再利用、queue item 再作成のみ
QUEUE_PATH=$(bash scripts/org/request-integration.sh \
  --task-id T-OS-418 \
  --branch task/T-OS-418-dogfood \
  ...)
```

⚠️ pretool が `git checkout` を deny する可能性。warn mode なら通る。

### Step 6: Integrator commit

```bash
COMMIT_SHA=$(bash scripts/org/integrator-commit.sh --task-id T-OS-418)
echo "Commit: $COMMIT_SHA"
```

期待: queue item が processing → done に移動、commit が新 branch (or main) に作成、`CommitIntegrated` event が `.ai/EVENTS.jsonl` に append。

### Step 7: Release lease

```bash
bash scripts/org/release-lease.sh "$LEASE_ID" --reason done
```

期待: lease が `.ai/leases/.released/` に move、`.ai/leases/$LEASE_ID.json` は消える。

### Step 8: Verification

- [ ] `git log` で integrator commit が見える
- [ ] commit author: `OrgOS Integrator`
- [ ] commit message: `docs(kernel-v2): T-OS-418 Manager dogfood execution log`
- [ ] commit trailers: `OrgOS-Task: T-OS-418`
- [ ] `.ai/queue/integration/done/.../T-OS-418.<ts>.json` が存在
- [ ] `.ai/artifacts/T-OS-418/$RUN_ID/` が存在 + manifest
- [ ] `.ai/leases/` から $LEASE_ID が消える
- [ ] 新 branch ならその branch に commit、main にはまだ未マージ (integrator は target branch に直接 commit、別途 merge は手動)

## 失敗時の log

各 step で stderr を docs/kernel-v2/dogfood.md に追記。expected と differ なら issue を記録。

## 完了判定

Step 1-8 全て期待通り → T-OS-418 done。

## 次のステップ (Owner morning judgment)

- Dogfood 成功 → mode flip 判定可能
- Dogfood 失敗 → 失敗箇所を T-OS-422+ task として登録、修正
