# GPT-5.5 Pro 6th-round prompt — post-hardening validation

> 用途: Owner が同じ GPT-5.5 Pro チャットに投入。
> 5th round で「PAUSE WEEK 4; HARDEN + DOGFOOD FIRST」判定後、7 時間の hardening + dogfood iteration 完了。
> 結果を `.ai/REVIEW/T-OS-400/external-ai-6th-response.md` に保存。

---

## 以下、AI への 6th-round prompt 本文 (全文コピー)

---

5th round で「PAUSE WEEK 4; HARDEN + DOGFOOD FIRST」と判定してくれた。Owner が「全部具に直してくれ。7時間かけて修正とレビューを繰り返して」と指示し、私 (Manager) が一晩で完了した。

今回は **post-hardening validation**。Q31 catastrophic bypass を含む全指摘の修正状況を報告する。Q32-Q35 の質問に答えてほしい。

---

## 完了報告

### 1. T-OS-416 (Q31 ORGOS_INTEGRATOR bypass) — CLOSED

修正内容:
- pretool_policy.py から `"ORGOS_INTEGRATOR=1" in command` の string match bypass を **完全削除**
- raw `git commit/push` は env 関係なく **常に deny**
- integrator-commit.sh の `ORGOS_INTEGRATOR=1` prefix も dead-code として削除
- KRT-011 (env prefix bypass denied) + KRT-012 (commit msg bypass denied) を test に追加

検証:
- 3/3 bypass scenarios all return exit 2:
  - `ORGOS_INTEGRATOR=1 git commit ...` → exit 2
  - `echo "ORGOS_INTEGRATOR=1"; git commit ...` → exit 2
  - `git commit -m "...ORGOS_INTEGRATOR=1..."` → exit 2

設計判断: integrator-commit.sh の内部 git commit は subprocess で Claude Code pretool 対象外なので、bypass token そもそも不要だった (architecture 誤りを修正)。

### 2. T-OS-417 (Q26#2 YAML corruption 予防) — DONE

- `scripts/org/validate-tasks-yaml.py`: duplicate key / id / missing field 検出
- `scripts/org/update-task.py`: 安全な field 更新 CLI
- pretool: `.ai/TASKS.yaml` direct edit deny
- KRT-013 (Edit deny) + KRT-014 (Write deny) + 7 unit tests

### 3. T-OS-419 (Q24#5 Codex handoff sandbox) — DONE

Codex CLI `--output-last-message` を main repo `.ai/CODEX/RESULTS/` から `/tmp/orgos-<task>-<run>-handoff.txt` に変更。wrapper が完了後 artifact store にコピー。canonical source = `.ai/artifacts/<task>/<run>/output-last-message.txt`。

### 4. T-OS-420 (Q27 per-invariant mode + accountability) — DONE

- kernel-mode.json schema v2 (default + per-invariant)
- set-kernel-mode.sh `--invariant` / `--list` / `--reset`
- `.ai/BOOTSTRAP-OVERRIDES.md` BO-001〜BO-004 (Manager 9 raw commits / manual cp / YAML corruption / lease なし Edit を audit trail に記録)

### 5. T-OS-421 (Q28#5 policy_core 分離) — DONE

- `.claude/hooks/policy_core.py` (新規 334 行): 純粋関数 `evaluate(action, actor, cwd, command, path, lease, mode)` -> Decision
- `.claude/hooks/pretool_policy.py` (220 行に縮小): I/O adapter only
- `tests/kernel/test-policy-core.sh`: 13 unit tests (mock 不要)
- 旧 930 行 monolith → 220 + 334 = 554 行 (40% 削減)

### 6. T-OS-418 Manager dogfood — SUCCESS (5 iteration を経て)

5th round Q25 dry-run 必須性が満たされた。**Manager が新フロー (acquire-lease → Edit → collect-artifacts → request-integration → integrator-commit → release-lease) で実 commit に成功**。

Iteration history (KRT 35件 が見落とした 5 つの bug を発見・修正):

| Iter | Bug | Fix |
|---|---|---|
| 1 | `.ai/queue/processing/` が allowed_paths check を fail させる | T-OS-422: INTERNAL_PATHS 開始 |
| 2 | `.claude/state/` (git.lock) も同様 | T-OS-423: 拡張 |
| 3 | macOS case-insensitive で `.ai/ARTIFACTS/` (legacy uppercase) 漏れ | T-OS-424: case-insensitive |
| 4 | `.ai/CODEX/AUDIT/` も漏れ → whack-a-mole 構造的問題 | T-OS-425: deny-list 廃止、allow-list intersect 再設計 |
| 5 | request-integration.sh が status_paths を allowed_paths に自動設定 (2296 files) | T-OS-426: --allowed-paths CLI + active lease lookup |

5th round Q26#1 / Q29 の予測「KRT pass するが real-world で抜ける」が **literal に実証**。

### 7. Per-invariant enforce flip — 4/10 active

```
default: warn
IntegratorOnlyCommit: enforce         ← 実 deny 動作確認
PerTaskWorktree: warn
ProtectedBranchNoTouch: enforce       ← 実 deny 動作確認 (Manager 自身が deny される現場を観察)
LeaseBeforeWrite: warn
StateMutationViaOrgTool: enforce
DurableArtifactBeforeCleanup: enforce
OwnerApprovalForIrreversibleOps: disabled (Week 7)
DangerousShell: warn
KernelSelfModification: warn
IntegratorIsScriptNotAgent: warn
```

### 8. Manager dogfood × 3 全成功

| ID | Content | Author |
|---|---|---|
| T-OS-418 | docs/kernel-v2/dogfood.md (iteration log 自体) | OrgOS Integrator |
| T-OS-427 | kernel-mode.json enforce flip (4 invariants) | OrgOS Integrator |
| T-OS-428 | hardening digest + 11 task status updates | OrgOS Integrator |

全て `OrgOS Integrator <orgos-integrator@local>` author で commit。Manager raw `git commit` 0 回 (整合の取れた数値)。

### 9. 全 commit (24 件、時系列降順)

```
80029d5 docs: hardening digest + finalize 11 task statuses (T-OS-428)
ff34dc8 config: enforce IntegratorOnlyCommit/ProtectedBranchNoTouch/DurableArtifact/StateMutation (T-OS-427)
a751945 docs: finalize dogfood iteration history (T-OS-418)
57ab742 docs: T-OS-418 Manager dogfood execution log
32e516f fix: request-integration --allowed-paths + lease lookup (T-OS-426)
0c7bcd0 refactor: integrator allowed_paths intersect (T-OS-425)
b2bcf51 fix: integrator INTERNAL_PATHS case-insensitive (T-OS-424)
5f306a9 fix: integrator INTERNAL_PATHS filter (T-OS-422+423)
164424f refactor: split pretool_policy.py into policy_core.py (T-OS-421)
6574d30 feat: per-invariant kernel mode + BOOTSTRAP-OVERRIDES (T-OS-420)
e3e4888 fix: redirect Codex handoff to /tmp + artifact store (T-OS-419)
0a92f3d feat: TASKS.yaml validator + update-task tool (T-OS-417)
534c61a fix CRITICAL: close ORGOS_INTEGRATOR bypass (T-OS-416)
... (前 5th round prompt 準備など)
```

### 10. テスト数

- Day0 cleanup: 5
- Day1 manifest: 6
- Day2 policy (KRT-001〜017): 17
- Week2 integrator: 15 (元 6 → dogfood で +9)
- Week2 yaml: 7
- Week3 lease: 8
- policy_core unit: 13

合計 **71 tests** (元 35 → +36)、SKIP ゼロ、全 pass。

---

## あなたへの質問 Q32〜Q35

### Q32. Q31 bypass fix の妥当性

5th round で:
> 補足で最も危ない細部は `ORGOS_INTEGRATOR=1` bypass の扱い。pretool は raw `git commit` を env に関係なく拒否し、`ORGOS_INTEGRATOR=1` は **git hook 側で integrator script の child process だけを通すための内部印**に限定すべき。

私の修正方針: **bypass token 自体を完全削除**。理由は integrator-commit.sh の git commit は subprocess なので Claude Code pretool 対象外、token 不要。

質問:
- この architecture 解釈は正しいか?
- もし git hook 側の bypass token (subprocess 検知用) も将来必要になる場合、どんな design が安全か?
- 別 worktree 内で codex も似た subprocess pattern なら、何か攻撃ベクタが残るか?

### Q33. Dogfood 5 iteration の解釈

dogfood で発見した 5 つの bug は、すべて KRT mock test では検出不能だった。

質問:
- Q26#1 / Q29 の予測 (mock vs real 乖離) を超える発見はあったか?
- INTERNAL_PATHS deny-list → allow-list intersect の再設計 (T-OS-425) は方向性として正しいか?
- 同様の whack-a-mole pattern が **他の場所** (request-integration.sh / collect-artifacts.sh / lease-acquire.sh / verify-artifact-manifest.py 等) に潜む可能性は? 高い順に 3 つ挙げよ
- 「dogfood は全 task で繰り返すべき」のか、「一定 maturity 後は KRT で十分」なのか?

### Q34. 残 5 invariants の段階 enforce 戦略

現状 enforce 4 個 (IntegratorOnlyCommit / ProtectedBranchNoTouch / StateMutationViaOrgTool / DurableArtifactBeforeCleanup)。
残 6 個:
- PerTaskWorktree: worktree marker 検出だが Manager 自身の root 操作も deny される可能性
- LeaseBeforeWrite: Manager の通常 file edit が全部 deny される
- DangerousShell: rm -rf / / curl|sh など、副作用大きい
- KernelSelfModification: kernel file 変更を deny、self-update が困難になる
- IntegratorIsScriptNotAgent: org-integrator subagent を完全 deny
- default: warn (現状)

質問:
- どの順序で enforce flip すべきか (推奨順序)?
- 各 flip 前にやるべき dogfood / preparation は何か?
- 「常に warn のまま残すべき」invariant はあるか? (例えば Owner が緊急対応で必要になる)

### Q35. Week 4 進行可否 (再判定)

5th round で「PAUSE WEEK 4; HARDEN + DOGFOOD FIRST」と判定。今 hardening 完了。

質問:
- Week 4 (SQLite shadow store) を始めてよい?
- もし **NO**, あと何が必要?
- もし **YES**, dogfood pattern を Week 4 でも適用するか? (実 SQLite import を Manager が dogfood)
- その他 Q30 評価 (実装品質、tests coverage、Manager dogfooding) を再評価するなら、A/B/C/D で?

---

## Output Format

```markdown
# OrgOS Post-Hardening Validation — 6th round (GPT-5.5 Pro)

## Q32. Q31 bypass fix 妥当性
### Architecture 解釈
...
### 将来の subprocess token design
...
### 残存攻撃ベクタ
...

## Q33. Dogfood 5 iteration 解釈
### 予測超過の発見
...
### allow-list intersect 設計の妥当性
...
### 同型 whack-a-mole 候補 (top 3)
1. ...
### dogfood の継続範囲
...

## Q34. 残 invariants enforce 戦略
### 推奨順序
1. ...
### preparation
...
### 永続 warn 候補
...

## Q35. Week 4 可否
### 判定: GO / PAUSE
...
### Q30 再評価
...

## Summary
3-5 文。次の一手を太字で 1 つ。
```

---

## 重要な追加依頼

- **Q32 が最優先**。bypass の architecture 解釈を間違えていたら catastrophic
- **Q33 同型 whack-a-mole** は preventive value が高い。憶測で構わないので 3 つ
- **Q35** は Week 4 着手の go/no-go。bouquet ではなく明確な判定をお願い

---

(prompt 本文ここまで)
