# OrgOS Post-Implementation Review — 5th round (GPT-5.5 Pro)

> 回答者: GPT-5.5 Pro (1st〜4th + 5th の連続チャット)
> 受領日: 2026-05-16
> 入力 prompt: `.ai/REVIEW/T-OS-400/external-ai-5th-prompt.md`
> **判定: PAUSE WEEK 4; HARDEN + DOGFOOD FIRST**
> 次の一手: **KRT-011 を追加し、Manager が新フローで dogfood commit を 1 件通すこと**

---

## Q24. 実装と spec の乖離点

1. **Integrator Gate は実装されたが、実運用では dogfood されていない**
   これは一番大きい。KRT-007 は通っているが、実際の 9 commit はすべて Manager raw commit。つまり「gate が動くこと」は証明されたが、「OrgOS が gate を使って運用できること」はまだ証明されていない。spec は "commit capability を integrator script に移す" だった。現実は "script はあるが Manager が旧来フローで commit" である。

2. **Lease Before Write が runtime check として存在するが、Manager の日常操作に組み込まれていない**
   active lease なしで `.ai/TASKS.yaml`, `.ai/REVIEW`, `.ai/DECISIONS.md`, `.ai/CODEX/ORDERS` を多数 Edit/Write している。これは warn mode だから許されたが、enforce 後に Manager の通常作業が大量に deny される可能性が高い。加えて、allowed_paths の path 比較は実戦で危ない。repo-relative 正規化、symlink、case-insensitive macOS、`..`、glob の重なり、generated artifact path をどこまで許すかがまだ十分実証されていない。

3. **State Mutation via Org Tool の思想に反して、TASKS.yaml 直接編集が継続し、実害が出た**
   duplicate-key corruption は「将来の懸念」ではなく既に起きた事故。YAML は last-wins で壊れ方が静かなので、OrgOS の状態管理には非常に相性が悪い。Week 4 で SQLite shadow store に進む前に、`.ai/TASKS.yaml` 直接 Edit を止めるか、少なくとも duplicate key を拒否する validator を必須にする必要がある。

4. **pretool_policy.py が 930 行まで肥大化し、policy_core.py 分離が遅れている**
   これは短期 bootstrap としては許容できるが、構造的には危険域に入っている。631→930 行の増加は、前回まで批判していた "patch-on-patch" の再発に近い。純粋関数 `evaluate(action, actor, cwd, command, path, lease, mode)` と hook I/O adapter を分けないと、テスト fixture と実 hook の乖離を見つけにくい。

5. **Codex handoff の canonical output path がまだ壊れている**
   artifact manifest に logs が残っているので Invariant #6 はかなり改善した。しかし `.ai/CODEX/RESULTS/T-OS-XXX.txt` に書けない sandbox 問題を未修正のままにしているため、Week 5 で EVENTS.jsonl / artifact source を formalize するときに再燃する。今は streaming log で拾えているが、それは durable interface ではない。

補足で最も危ない細部は、`ORGOS_INTEGRATOR=1` bypass の扱い。もし raw Bash で `ORGOS_INTEGRATOR=1 git commit` が pretool を通る実装なら、Integrator Gate は抜け穴つきである。pretool は raw `git commit` を env に関係なく拒否し、`ORGOS_INTEGRATOR=1` は **git hook 側で integrator script の child process だけを通すための内部印**に限定すべき。

## Q25. Manager self-rule violation 評価

### 許容範囲か構造問題か

**bootstrap 例外としては一部許容。ただし、このまま続けば構造問題。**

9 commit のうち、kernel がまだ存在しない Day 0/1 初期の raw commit は bootstrap として説明できる。問題は、Integrator Gate と KRT-007 が入った後も Manager がその gate を使わずに commit し続けた点。これは "論理的には warn mode だから OK" では済まない。OrgOS の一番危険な習慣、つまり **Manager が便利だから旧来の万能 operator に戻る** という失敗モードがそのまま出ている。

今回の self-violation は moral failure ではなく、設計上の赤信号である。Manager は「ルールを理解しているから例外」ではない。Manager が一番強い tool budget を持つので、むしろ一番縛る必要がある。

### bootstrap 完了後の運用

bootstrap 完了後は、Manager も以下を守るべき。

```text
Manager raw git commit: 禁止
Manager git add && git commit: 禁止
Manager cp worktree -> main repo: 禁止
Manager direct TASKS.yaml edit: 禁止
Manager direct EVENTS.jsonl edit: 禁止
Manager active lease なし Write/Edit: 禁止
```

通常 commit flow は必ずこれ。

```text
1. acquire lease
2. make/change through allowed path
3. collect artifacts
4. request integration
5. integrator-commit.sh
6. event append
7. release lease
```

kernel 自体のメンテナンスも例外ではない。必要なら `kernel-maintenance` lease を発行する。

### dry-run の要否

**必須。enforce flip 前に Manager 自身が新フローで 1 commit 完走するまで、enforce してはいけない。**

dry-run は toy ではなく、本物の小さい commit にする。

例:

```text
Task: T-OS-DOGFOOD-001
Change: docs/ or tests/kernel/ に 1 行追加
Flow:
  acquire-lease.sh
  Edit within lease
  collect-artifacts.sh
  request-integration.sh
  integrator-commit.sh
  release-lease.sh
Expected:
  Manager raw commit なし
  queue item consumed
  CommitIntegrated event
  artifact manifest verified
```

これが通らないなら、KRT-007 が通っていても enforce する資格はない。

### アカウンタビリティ設計

「Manager が破ったが Owner が止めなかったので Owner が有罪」は雑すぎる。責任分解はこう。

| 事象                                     | 扱い                                         |
| -------------------------------------- | ------------------------------------------ |
| warn mode 中の Manager raw commit        | `BootstrapOverride` として記録。許容だが debt。       |
| enforce 後の Manager raw commit 成功       | system bug。                                |
| Manager が warning を無視して旧 flow 継続       | governance bug。Owner に morning digest で明示。 |
| Owner が明示的に override                   | Owner responsibility。ただし event 必須。         |
| Manager が self-approval で high-risk 実行 | system bug。                                |

今すぐやるべきは、9 commit を責めることではなく、`BOOTSTRAP-OVERRIDES.md` または EVENTS に以下を記録すること。

```text
These 9 commits were made before/during warn-mode bootstrap.
They are explicitly non-compliant with future Integrator-Only Commit.
After enforce, this pattern is prohibited.
```

## Q26. 隠れた失敗モード予測

1. **enforce shock**
   早期検出指標: enforce 後 1 時間で deny が 10 件以上、Manager が作業不能、`set-kernel-mode warn` したくなる。
   対策: full enforce 前に dogfood commit。さらに raw commit / protected branch / artifact cleanup は enforce、lease/write は canary enforce から始める。

2. **YAML corruption 再発**
   早期検出指標: duplicate key validator failure、allowed_paths が unexpected に変わる、post-exec-audit が突然全ファイル disallow。
   対策: `.ai/TASKS.yaml` direct Edit 禁止。`scripts/org/update-task.py` 経由にする。PyYAML last-wins は使わず、duplicate key を error にする loader を使う。

3. **real Claude Code hook と fixture test の乖離**
   早期検出指標: KRT は pass するが実セッションで deny されない、actor が manager/codex と識別できない、Bash command parser が実 JSON とズレる。
   対策: 1 回だけ本物の Claude Code pretool 経由で raw `git commit`, `git checkout main`, `.ai/EVENTS.jsonl Edit` を試す "live hook smoke test" を作る。

4. **`ORGOS_INTEGRATOR=1` bypass の悪用または誤通過**
   早期検出指標: raw Bash で `ORGOS_INTEGRATOR=1 git commit` が通る、または pretool log に bypass reason が出る。
   対策: KRT-011 を追加。raw env bypass は deny。git hook だけが integrator child process を許す。

5. **lease stale / path false positive の増加**
   早期検出指標: stale lease が残り続ける、allowed path なのに deny、allowed でない path が通る、heartbeat が更新されない。
   対策: `list-leases.sh --stale`, `release-lease.sh --force --owner-override`, path canonicalization test を追加。

## Q27. enforce flip タイミング

### 推奨

**即時 full enforce は不可。だが N 日 warn 観察も不要。**

warn mode を何日も続けると warning fatigue になる。Owner / Manager は warning を「ログのノイズ」として扱い始める。よって推奨はこう。

```text
1. 今日: dogfood commit を 1 件、新フローで実行
2. KRT-011 / KRT-012 を追加
3. live hook smoke test を実施
4. その後、OrgOS-Dev だけ enforce
5. 10+ project には cleanup preservation と raw commit deny だけ段階配布
```

full enforce の前に最低限必要なのは "時間" ではなく "証拠"。

### dry-run 手順

1. **snapshot**

   * current branch
   * `.ai/TASKS.yaml`
   * `.claude/state/kernel-mode.json`
   * `.ai/leases`
   * `.ai/queue`
   * `git status`

2. **KRT 追加**

   * KRT-011: `ORGOS_INTEGRATOR=1 git commit` raw Bash は deny
   * KRT-012: `.ai/TASKS.yaml` direct Edit は deny または validator fail

3. **Manager dogfood**

   * acquire lease
   * small file edit
   * collect artifacts
   * request integration
   * integrator commit
   * release lease

4. **live hook smoke**

   * Manager raw `git commit` → deny
   * Manager `.ai/EVENTS.jsonl` direct Edit → deny
   * Manager `git checkout main` from task context → deny

5. **enforce flip**

   * `scripts/org/set-kernel-mode.sh enforce`
   * 直後に deny log を確認

### enforce 後に必ず壊れる既存運用

かなり壊れる。壊れるべきものも含む。

* Manager の raw `git commit`
* Manager の `git add && git commit`
* Manager の worktree から main repo への `cp`
* `.ai/TASKS.yaml` 直接 Edit
* `.ai/DECISIONS.md` 直接 Edit
* `.ai/EVENTS.jsonl` 直接 Edit
* `.claude/hooks/pretool_policy.py` 直接 Edit
* `.claude/rules/*.md` 直接 Edit
* subagent が lease なしに Write/Edit
* `git worktree remove --force`
* `git reset --hard`
* `git branch -f`
* `/org-tick` が state file を直接更新している場合、その更新

特に `/org-tick` が legacy state mutation を含むなら、enforce 後に壊れる可能性が高い。

### rollback 最短手順

最短 rollback はこれ。

```bash
scripts/org/set-kernel-mode.sh warn --reason "enforce rollback: <reason>"
```

ただし、これだけだと raw commit も warn に戻る。より良いのは per-invariant mode。

```json
{
  "default": "warn",
  "IntegratorOnlyCommit": "enforce",
  "ProtectedBranchNoTouch": "enforce",
  "DurableArtifactBeforeCleanup": "enforce",
  "LeaseBeforeWrite": "warn"
}
```

まだ per-invariant mode がないなら、enforce 前に入れる価値がある。最悪でも `No Worker Commit` だけは warn に戻さない方がよい。

## Q28. Week 4 前ハードニング

1. **Manager dogfood commit を 1 件成功させる**
   Week 4 より先。これが通らないなら Week 4 に進むべきではない。KRT ではなく実運用で integrator queue を使う。

2. **YAML direct edit を止める / duplicate key validator を入れる**
   `.ai/TASKS.yaml` に対して direct Edit を deny するか、少なくとも pretool / posttool で duplicate key を即 fail させる。Week 4 の SQLite import は legacy YAML を読むので、ここが壊れていると DB が腐る。

3. **`ORGOS_INTEGRATOR=1` raw bypass test を追加する**
   KRT-011。`ORGOS_INTEGRATOR=1 git commit -m x` が pretool で deny されることを確認。これは catastrophic bypass の確認。

4. **Codex handoff sandbox 問題を修正する**
   Codex に main repo `.ai/CODEX/RESULTS` へ直接書かせようとする設計をやめる。wrapper が worktree 内 / stdout / tmp から artifact store に吸い上げる。canonical source は `.ai/artifacts/<task>/<run>/output-last-message.txt` にする。

5. **pretool_policy.py を最低限分割する**
   full refactor は Week 8 でよいが、Week 4 前に次だけは分ける。

   * git command parser
   * path policy
   * lease lookup
   * decision object
     930 行 monolith のまま SQLite shadow store に進むと、state と policy の bug が絡んで切り分け不能になる。

## Q29. tests 信用度

### 検証されていないもの (top 5)

1. **real Claude Code hook 経由の挙動**
   fixture mode は必要だが、実 hook JSON、exit code、matcher、actor identification、subagent context を完全には再現しない。ここがズレると KRT は pass しても本番で抜ける。

2. **real Codex CLI の sandbox / streaming / output behavior**
   Mock Codex は echo/printf。実 Codex は streaming、sandbox restriction、`--output-last-message` failure、長時間実行、partial output、non-zero exit を起こす。今回既に sandbox 問題が出ている。

3. **concurrency**
   並列 lease acquisition、同時 artifact collection、同時 queue consume、git lock contention、同時 worktree cleanup が薄い。今回の事故の元は並列性なので、ここが薄いのは危険。

4. **path canonicalization edge cases**
   symlink、unicode、space、case-insensitive macOS、`../`, absolute path、glob overlap、hidden files、generated files が十分 test されていない可能性が高い。

5. **long-running state / expiry**
   30 min heartbeat expiry、stale lease reclaim、queue item 24h stall、artifact retention、disk pressure が test されていない。35 test は "短時間 happy/deny path" に偏っている。

### Mock と real の乖離リスク

Mock test は価値がある。CI cost を抑え、policy regression を速く検出できる。しかし Mock だけで production readiness と見なすのは危険。

必要な追加 test は少数でよい。

```text
Live-001: real Claude Code pretool denies Manager raw git commit
Live-002: real Claude Code pretool denies Manager TASKS.yaml Edit
Live-003: real Codex run produces artifact manifest despite output-last-message sandbox issue
Conc-001: two lease acquisitions for overlapping paths race; only one succeeds
Bypass-001: ORGOS_INTEGRATOR=1 raw git commit is denied
```

これ以上 test を増やしすぎるより、この 5 つが重要。

## Q30. 実装品質評価

| 層                                     | 評価     | 理由                                                                                                |
| ------------------------------------- | ------ | ------------------------------------------------------------------------------------------------- |
| Invariants 設計                         | **A**  | 7 invariant の選び方は妥当。Artifact durability を入れたのも正しい。ただし Owner Approval #7 が未実装なので S ではない。           |
| Invariants 実装 (pretool_policy.py)     | **B-** | 35 tests pass は良いが、930 行 monolith、fixture/real hook 乖離、Manager dogfood 不足が重い。                     |
| Integrator gate (scripts/org/)        | **B**  | queue + integrator + test は良い。ただし実 commit に未使用なので実運用 confidence はまだ低い。                            |
| Lease registry                        | **B-** | registry と tests は前進。ただし Manager が使っておらず、heartbeat / stale / path canonicalization が未成熟。          |
| Artifact preservation                 | **A-** | wrapper bug の本質に対処している。manifest + logs + fail-closed は強い。sandbox output-last-message 未修正で S ではない。 |
| Tests (mock 範囲)                       | **A-** | 35/35、SKIP 0、Day0-Week3 を網羅。Mock regression としてはかなり良い。                                            |
| Tests (現実 coverage)                   | **C+** | real Claude Code hook、real Codex sandbox、concurrency、long-running expiry が薄い。                     |
| Manager 自身の dogfooding                | **D+** | 正直ここは悪い。新フローを作ったが使っていない。enforce 前の最大 blocker。                                                     |
| Documentation / DECISIONS / SYNTHESIS | **A-** | 開示の粒度が高く、自己違反も隠していない。これは良い。ただし bootstrap override ledger が必要。                                     |
| 既存 OS との migration 度                  | **B**  | Week 0-3 を ship したのは大きい。ただし mode=warn、旧 state edit、multi-project rollout 未完で本番移行は途中。              |

総合評価は **B+**。
実装量とテスト量は良い。だが「Manager が新 kernel を使っていない」という一点で A には届かない。

## Q31. 最も重要な見落とし候補

最大の見落とし候補は **Integrator bypass が本当に閉じているか**。

特に `ORGOS_INTEGRATOR=1` が危険。もし raw Bash で以下が通るなら、kernel の中心が抜ける。

```bash
ORGOS_INTEGRATOR=1 git commit -m "bypass"
```

この場合、worker / Manager は integrator script を使わず、env var だけで git hook を突破できる。pretool が raw git commit を無条件 deny していれば大丈夫だが、実装説明に "`ORGOS_INTEGRATOR=1` bypass" とある以上、私はここを最大リスクとして見る。

Week 4-8 に進む前に潰すべきこと:

```text
KRT-011:
  actor=manager or codex
  command='ORGOS_INTEGRATOR=1 git commit -m bypass'
  expected=deny by pretool
```

さらに git hook 側も、可能なら env var だけでなく queue item / marker / parent script context を見るべき。完全な parent verification は難しくても、少なくとも raw pretool bypass は拒否しなければならない。

これが開いていると、No Worker Commit は見かけだけになる。
YAML corruption や lease stale も重要だが、commit gate bypass は catastrophic に近い。

## Summary

Week 0-3 の実装は、量・速度・テストの面ではかなり良い。ただし Manager が raw commit / cp / lease なし Edit を続けたため、新 kernel はまだ **実運用で dogfood されていない**。Week 4 SQLite に進む前に、Manager 自身が integrator queue 経由で 1 本 real commit を成功させ、`ORGOS_INTEGRATOR=1 git commit` bypass を KRT で潰し、TASKS.yaml direct edit 対策を入れるべき。判定は「STOP BUILD」ではなく **PAUSE WEEK 4; HARDEN + DOGFOOD FIRST**。次の一手は **KRT-011 を追加し、Manager が新フローで dogfood commit を 1 件通すこと**。
