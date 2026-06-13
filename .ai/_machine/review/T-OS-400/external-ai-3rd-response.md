# OrgOS 理想形批評 — 3rd round 回答 (GPT-5.5 Pro)

> 回答者: GPT-5.5 Pro (1st + follow-up + 3rd の連続チャット)
> 受領日: 2026-05-14
> 入力 prompt: `.ai/REVIEW/T-OS-400/external-ai-3rd-prompt.md`

---

## Q11. 3視点比較

### 収束点

3 視点はかなり強く収束している。これは偶然ではない。OrgOS の失敗モードが、個別実装バグではなく構造欠陥として十分に露出しているからだ。

1. **Markdown rule ではなく runtime enforcement が必要**
   Manager は「Rule 30+ と runtime enforcement 5 未満の解離」と表現し、Codex は policy pure function / state validator を推し、私は pretool + git hook + posttool auditor を推した。言い方は違うが、全員「自然言語 rule では守れない」と結論している。

2. **Manager は dispatcher に降格すべき**
   Manager の責務過剰、私の planner / dispatcher / narrator 化、Codex の「機械化可・構造化可・LLM 必須」の分類は同じ方向。Manager を万能実行者にする設計は終わらせるべき、という収束。

3. **状態は event / projection に寄せるべき**
   Manager は `.ai/EVENTS.jsonl` SSOT、私は SQLite + jsonl、Codex は projection/event log。差はあるが、「7 個の YAML/MD がそれぞれ真実を持つ状態」は全員否定している。

4. **Codex / worker は capability boundary に閉じ込めるべき**
   worktree、allowed_paths、lease、commit gate。これも完全収束。worker の善意や prompt 理解を信用しない。

5. **Owner UX は intent → plan に変えるべき**
   Owner が `CONTROL.yaml` や phase を直接操作するのではなく、Plan Contract を approve / modify / reject する形に寄せるべき、という点も一致。

6. **rule 単調増加を止める必要がある**
   Manager の四半期 consolidation、私の Kill List、Codex の simplest viable alternative は、いずれも「増え続ける rule / agent / script を減らせ」と言っている。

7. **観測可能性と証拠が必要**
   Handoff Packet や audit log の宣言ではなく、diff、test、artifact、event、verifier result が必要。wrapper bug はこの点を実証している。

前回 follow-up では、Claude Code の primitive 制約、Week 1 ship、Kill List、State Store、Plan Contract の具体化が重要だと整理した。今回の新情報はその方向性を補強している。

### 対立点

#### 対立 1: enforcement 層の粒度

* Manager: 全 Iron Law に runtime check 必須
* Codex: OPA より Python pure function + YAML rule table で十分
* 私: pretool + git hook + posttool auditor + integrator script

仲裁: **Codex + 私の組み合わせが正しい。Manager の言い方は正しいが、そのまま実装すると危険。**

「全 Iron Law に runtime check」は正しい。ただし Iron Law が 30 個あるなら破綻する。だからまず Iron Law を 7 個以内に削る。そのうえで、enforcement は OPA ではなく Python pure function で十分。Claude Code substrate では OPA/Cedar を入れるより、`pretool_policy.py` から呼べる小さな `policy_core.py` を作るほうが現実的。

最終案:

```text
policy_core.py
  └── pure function: evaluate(action, actor, cwd, branch, lease, approval, diff) -> allow/deny/warn

pretool_policy.py
  └── Bash/Edit/Write 前に policy_core を呼ぶ

posttool_audit.py
  └── HEAD change / artifact preservation / diff drift を検出

git hook
  └── 最後の防御。ただし単独では信用しない。

integrator-commit.sh
  └── commit 権限を持つ唯一の経路
```

つまり、Manager の「runtime check 必須」は原則として採用、Codex の「Python pure function + YAML rule table」は実装形として採用、私の「pretool + git hook + posttool auditor」は enforcement point として採用。

#### 対立 2: 8 週移行 vs simplest viable alternative

* Manager: Phase A-E の段階移行
* Codex: OrgOS を半分捨てて `scripts/org-task` + `scripts/org-validate` + `CHECKLIST.md` に戻す案を短期 stabilization として評価
* 私: 8 週間 migration、Week 1 で commit / shared worktree を止める

仲裁: **Codex の simplest viable alternative を Week 0 / Week 1 の安定化モードとして取り込むべき。全面採用はしない。**

OrgOS を半分捨てるのは、長期要件「10+ project 並列 AI 運用」には弱い。しかし、短期 stabilization としては非常に強い。今の OrgOS は複雑すぎる。したがって 8 週計画の前に、実質 2〜3 日の **Stabilization Mode** を置くべき。

3rd round での訂正:

* 前回: Week 1 = No Worker Commit + No Shared Worktree
* 今回: **Week 0.5 = Artifact Preservation + Cleanup Fail-Safe**
* その後に Week 1 = No Worker Commit + No Shared Worktree

wrapper bug を見た以上、worktree 強制を先に進めると「安全に隔離した成果物を cleanup で消す」という事故を増やす可能性がある。

#### 対立 3: 状態 store の権威配置

* Manager: `.ai/EVENTS.jsonl` が SSOT
* 私: SQLite + append-only event log
* Codex: projection/event log

仲裁: **権威は EVENTS.jsonl、SQLite は projection。少なくとも migration 期間中はそうする。**

ここは私の follow-up を少し訂正する。前回は SQLite をやや強く言いすぎた。SQLite は便利だが、初期導入時に projection bug が出ると、OrgOS はさらに混乱する。したがって最初の権威は append-only event log に置く。

推奨:

```text
.ai/EVENTS.jsonl          = authoritative audit/event source
.ai/orgos.sqlite          = rebuildable projection/query cache
.ai/DASHBOARD.md          = generated view
.ai/TASKS.generated.yaml  = generated compatibility view
.ai/TASKS.yaml            = legacy input, later readonly
```

SQLite は SSOT ではない。壊れたら消して EVENTS から再生成できるべき。

#### 対立 4: FSM vs Plan Contract

Codex の FSM 案は正しい。ただし FSM は Owner UX ではない。Plan Contract は UX、FSM は runtime。両方必要。

```text
Owner intent
  -> Plan Contract
  -> approved transition request
  -> FSM transition
  -> required evidence check
  -> event append
  -> projection update
```

Request Intake Loop を 10 step prompt checklist として維持するのはやめる。Typed FSM に変える。

### 盲点

3 視点とも、または少なくとも前回までは、以下を軽視していた。

1. **Artifact durability**
   wrapper bug が示した通り、allowed_paths と audit があっても成果物が消える。これは policy failure ではなく durability failure。憲法レベルで扱う必要がある。

2. **Manager の身分問題**
   「worker は commit しない」と言っても、Manager が commit してよいなら抜け穴になる。ここを曖昧にしたまま Week 1 に入ると失敗する。

3. **mid-flight task migration**
   52 task がある状態で、running / queued / paused / uncommitted diff をどう扱うか。前回までは新規 task 目線が強かった。

4. **autonomy と approval fatigue**
   Plan Contract を増やすと Owner が rubber-stamp する。これは安全ではなく、見かけの承認儀式になる。

5. **cleanup / rollback / artifact preservation のテスト**
   「実行できるか」ではなく「失敗時に成果物が残るか」をテストしていなかった。

6. **global cross-project scheduling**
   10+ project 並列では、repo 内だけでなく Owner の認知予算、AI worker 枠、夜間 autonomy 枠も resource である。

### 最終仲裁

3 視点を点数付けするとこう。

| 視点             |  点 | 評価                                                                                |
| -------------- | -: | --------------------------------------------------------------------------------- |
| Manager vision |  A | 診断と原則は鋭い。ただし実装粒度が粗く、Phase A-E はやや抽象的。                                             |
| Codex partial  | A- | practical。FSM と simplest viable alternative は重要。ただし partial 欠落で全体判断は不完全。          |
| 私の follow-up   | A- | Week 1 / schema / Plan Contract は具体的。ただし artifact durability と Manager 身分を過小評価した。 |
| 統合案            | S- | 3 視点を合わせるとかなり強い。ただし実装でまた肥大化するリスクあり。                                               |

最終判断:

* enforcement は **Python policy core + pretool/posttool/git hook/integrator**。
* 状態の権威は **EVENTS.jsonl**。SQLite は projection。
* Plan Contract は UX。runtime は **typed FSM**。
* Codex の simplest viable alternative は **Week 0 stabilization** として採用。
* Manager は **commit 不可**。ここは絶対に例外を作らない。

### follow-up 訂正/補強

3rd round で改める点は 4 つ。

1. **SQLite を SSOT と言わない**
   SSOT は `.ai/EVENTS.jsonl`。SQLite は rebuildable projection。

2. **Week 0.5 を追加する**
   wrapper output preservation を直さずに worktree 強制を進めるのは危険。

3. **Evidence-Gated Done を Durable Artifact invariant に拡張する**
   done 以前に、cleanup 前の永続化が憲法レベルで必要。

4. **Manager も raw commit 禁止**
   Manager 例外は作らない。Manager ができるのは integrator script に commit request を出すことだけ。

## Q12. Manager 身分

### 役割判定

Manager は worker ではない。integrator でもない。Owner proxy でもない。

Manager は **control-plane dispatcher / planner / narrator** である。

ここを曖昧にすると壊れる。Manager に「commit してよい特権」を与えると、Codex 禁止をいくら強めても意味がない。なぜなら現状では Manager も `.ai/DECISIONS.md`、`TASKS.yaml`、git commit、push をしているからだ。新 kernel では、Manager の直接 commit は禁止する。

ただし、Owner が毎回手動 commit する必要はない。線引きはこう。

```text
Manager が git commit する: 禁止
Manager が integrator script に commit request を出す: 許可
integrator script が invariant / lease / verifier / approval を検査して commit する: 許可
Owner が手動で root 権限として override する: 許可。ただし event に残す
```

重要なのは、「誰が command を発話したか」ではなく「どの capability path で commit が行われたか」。Manager が `git commit` と打ったら拒否。Manager が `scripts/org/integrator-commit.sh T-123` を呼び、script が条件を満たした場合だけ commit する。

### Manager は Plan Contract を自分で承認できるか

できない。

ただし、standing approval に基づく **policy auto-approval** は可能。これは Manager の自己承認ではない。

悪い例:

```text
Manager: この plan は低リスクなので自分で approve します。
```

良い例:

```text
policy_core:
  standing_approval_id: SA-LOW-RISK-001
  condition:
    risk <= low
    allowed_paths within src/auth/**
    no migration
    no production
    diff_budget <= 200 lines
  result: auto_approved
```

この場合、approval event の actor は `policy:SA-LOW-RISK-001` であり、Manager ではない。Manager は approval を「行う」のではなく、policy decision を「記録する」。

High risk / irreversible / production / secret / migration は常に Owner approval。Manager は承認できない。

### Manager × 7 invariant 適用表

ここでは 3rd round 改訂版の 7 invariant として扱う。

| invariant                            | Manager 適用 | 理由                                                                                                             |
| ------------------------------------ | ---------- | -------------------------------------------------------------------------------------------------------------- |
| Integrator-Only Commit               | **適用**     | Manager の raw `git commit` は禁止。commit は integrator script のみ。Manager 例外は作らない。                                  |
| Per-Task Worktree                    | **条件付き適用** | Manager が実装・修正・生成物作成を行う場合は task worktree / org tool 経由。読み取り・planning は root でも可。                               |
| Protected Branch No-Touch            | **適用**     | Manager が main/develop を checkout/reset/commit できると全 invariant が抜ける。protected branch 更新は integrator script のみ。 |
| Lease Before Write                   | **適用**     | Manager も allowed_paths / lease なしに project file を書いてはいけない。state 更新は専用 org tool 経由。                            |
| State Mutation via Org Tool          | **適用**     | Manager の `.ai/TASKS.yaml` / `.ai/DECISIONS.md` 直接編集は禁止。event append / projection writer 経由にする。                |
| Durable Artifact Before Cleanup/Done | **適用**     | Manager は artifact manifest なしに cleanup / done 化してはいけない。Handoff Packet だけでは不可。                                 |
| Owner Approval for Irreversible Ops  | **適用**     | production / secret / migration / destructive command は Manager でも不可。standing approval の対象にも原則しない。             |

例外を許すなら、唯一の例外は **Owner manual override**。Manager override ではない。

### 責務境界 5-7 行

1. Manager は Owner intent を解釈し、Plan Contract を作る。
2. Manager は lease / policy / state script を呼べるが、operational state を直接編集しない。
3. Manager は worker を dispatch できるが、worker と同じく raw commit はできない。
4. Manager は verifier を起動し、結果を要約できるが、証拠なしに done にしない。
5. Manager は integrator commit を request できるが、commit 可否は integrator script が決める。
6. Manager は standing approval の範囲内で自律実行できるが、自己承認はできない。
7. Manager は irreversible ops を実行せず、Owner approval を要求する。

これで「Manager dispatcher 化」と「Manager commit 禁止」は両立する。

## Q13. 既存52task migration

### 推奨戦略

推奨は **trickle migration + global safety overlay**。

選択肢ごとの評価はこう。

| 戦略                              | 評価                                     |
| ------------------------------- | -------------------------------------- |
| 完全停止                            | 安全だが現実的でない。Owner の 10+ project 運用を止める。 |
| 旧 flow 継続                       | 危険。事故がまた起きる。                           |
| 全 active task を Plan Contract 化 | 52 件一括承認は rubber-stamp になる。安全ではない。     |
| trickle migration               | 最も現実的。ただし旧 flow にも安全 overlay をかける必要あり。 |

つまり、52 task を一気に変換しない。だが、旧 flow を無防備に継続もしない。

推奨状態ラベル:

```yaml
migration_mode:
  - legacy_queued
  - legacy_running_needs_triage
  - sandboxed_legacy
  - plan_contract_ready
  - migrated
  - cancelled
```

最初にやるのは「変換」ではなく「棚卸し」。

### Week 1 mid-flight 扱い

Week 1 開始時点で running task があるなら、いきなり hook を強制して壊すのではなく、短い migration freeze を置く。停止期間は 1〜2 時間でよい。

手順:

1. **new worker 起動を一時停止**
   既存 session は触るが、新規 Codex は出さない。

2. **全 running task の snapshot を取る**

   * cwd
   * branch
   * HEAD
   * `git status --porcelain`
   * uncommitted diff
   * untracked files
   * active process / run id
   * output files

3. **mid-flight Codex の worktree を判定**

   * task worktree 上なら `sandboxed_legacy`
   * shared/root 上なら `legacy_running_needs_triage`

4. **shared/root 上の実装を止める**

   * 未 commit diff を patch に保存
   * untracked files を tar / artifact 化
   * task worktree を作って再開

5. **Codex がまだ走っているなら cleanup を止める**
   wrapper bug があるので、artifact preservation 修正前に cleanup させてはいけない。

6. **No Worker Commit を先に入れる**
   旧 flow でも新 flow でも、worker direct commit は即禁止。

7. **running task は full Plan Contract 化しない**
   代わりに “Continuation Contract” を作る。内容は worktree / branch / allowed_paths / commit禁止 / artifact保存だけ。

Continuation Contract 例:

```markdown
Continuation Contract: T-OS-123

This task is mid-flight legacy work.

Current state:
- branch: task/T-OS-123
- worktree: worktrees/T-OS-123
- uncommitted diff: yes
- artifacts preserved: yes

Allowed to continue:
- allowed_paths: existing touched paths only
- worker commit: no
- cleanup before artifact manifest: no

Owner approval:
- not required for continuation
- required if scope expands
```

### 旧flow リスク抑制

旧 flow を残すなら、最低限この overlay を全 task にかける。

* raw `git commit` 拒否
* main/develop checkout 拒否
* cleanup before artifact preservation 拒否
* shared/root worktree write は warning ではなく原則拒否
* `.ai` operational state 直接編集は warning から始めてもよいが、Week 2 以降拒否
* Handoff Packet 単体 done 禁止

特に commit だけは observe mode にしてはいけない。最初から enforce。

### 新規依頼との優先順位

8 週間の migration 中に Owner が新規依頼を出すのは当然ある。禁止すると OrgOS は実用性を失う。

比率の目安:

* Week 0.5〜1: migration 80%、新規 20%。新規は緊急・低リスクだけ。
* Week 2〜3: migration 60%、新規 40%。新規は Plan Contract lite 必須。
* Week 4〜6: migration 40%、新規 60%。SQLite/event は shadow なので通常運用を増やせる。
* Week 7〜8: migration 30%、新規 70%。rule kill / UX 整理中心。

ただし例外がある。production incident、顧客影響、セキュリティ修正は migration より優先。ただし **旧 flow ではなく safety overlay 上で実行** する。

### rollback 戦略

rollback は必要だが、「危険な旧 OrgOS に完全復帰」は rollback ではない。それは再事故許可である。

rollback の階層:

1. **hook mode rollback**
   `enforce` → `warn` に戻す。ただし `git commit` 拒否だけは維持。

2. **worktree enforcement rollback**
   worktree 強制が壊れたら一時的に shared write を warning に戻す。ただし cleanup preservation と commit gate は維持。

3. **state migration rollback**
   SQLite / generated view が壊れたら `.ai/TASKS.yaml` legacy source に戻す。EVENTS は残す。

4. **full rollback request from Owner**
   「旧 OrgOS に戻したい」と言われても、戻すのは UX / state 表示だけ。AI direct commit は復活させない。

事前に作るべき snapshot:

```text
.ai.backup.<timestamp>/
branches snapshot
worktrees inventory
events snapshot
TASKS.yaml copy
hook config copy
```

## Q14. Wrapper bug + Week 1 精度

### 追加 / 修正 invariant

これは面白い事例ではない。設計を直撃する事故である。

前回の 7 invariant に 8 個目を足すのではなく、6 番目を改訂する。

旧:

```text
Evidence-Gated Done
task done は Handoff Packet だけでは不可。diff / test / verifier result / event が必要。
```

新:

```text
Durable Artifact Before Cleanup/Done
worker output, diff, untracked files, Handoff, logs, audit result は cleanup 前に durable artifact store へ保存されなければならない。artifact manifest がない run は done にできず、worktree cleanup も禁止。
```

これは constitutional でよい。なぜなら、成果物が消えると検証も integration も監査もできないからだ。

具体仕様:

| 項目            | 内容                                                                                                |
| ------------- | ------------------------------------------------------------------------------------------------- |
| durable store | root repo 側の `.ai/artifacts/<task_id>/<run_id>/` または `~/.orgos/artifacts/<project>/<task>/<run>/` |
| manifest      | `artifact_manifest.json` に path, sha256, size, source_path, copied_at                             |
| 必須保存          | stdout/stderr, last message, generated markdown, `git diff`, untracked files, audit yaml/json     |
| cleanup 条件    | manifest 作成成功 + artifact existence check 成功                                                       |
| 失敗時           | worktree remove 禁止。`worktrees/<task_id>` を quarantine として残す。                                      |

`post-exec-audit.sh` は「allowed_paths にマッチした」と記録するだけでは不足。audit が allowed と判断した output について、**永続化責任**を持たなければならない。

最低限の修正:

```text
run-in-worktree.sh
  -> codex 実行
  -> collect outputs
  -> git diff 保存
  -> untracked files 保存
  -> copy allowed artifacts to durable store
  -> write artifact_manifest.json
  -> verify manifest
  -> post-exec-audit
  -> cleanup only if manifest verified
```

cleanup は fail-safe ではなく **fail-closed** にする。保存に失敗したら消さない。

### 同型事故の未発見候補

OrgOS には同じ型の事故が他にも潜んでいる可能性が高い。

1. **allowed_paths audit が log だけで rollback しない**
   allowed_paths 外 write を検出しても、revert / block しないなら enforcement ではない。

2. **heartbeat があるが lease reclaim がない**
   heartbeat を記録しても、切れた lease を expire / release しないなら意味がない。

3. **Handoff Packet schema があるが evidence check がない**
   schema が埋まっていても、test result / diff / artifact と対応していなければ自己申告。

4. **Owner approval flag があるが command block がない**
   `ask_before_execute` と書いてあっても、production command を pretool で拒否しないならただの宣言。

5. **DASHBOARD / TASKS が SSOT を名乗るが checksum がない**
   人間や Manager が直接編集しても検出できないなら、projection ではなく漂流メモ。

6. **git.lock があるが全 critical section を覆っていない**
   flock が存在しても、branch checkout / worktree cleanup / commit / integration を同じ lock domain で守っていなければ衝突する。

### Week 1 順序見直し

はい、順序を変えるべき。

前回:

```text
Week 1: No Worker Commit + No Shared Worktree Execution
```

3rd round 改訂:

```text
Week 0.5 / Day 0-1:
  Artifact Preservation + Cleanup Fail-Closed

Week 1 / Day 2-5:
  No Worker Commit + No Shared Worktree Execution
```

具体順序:

#### Day 0: destructive cleanup を止める

* `git worktree remove --force` を一時禁止
* cleanup は `--preserve-worktree` default
* cleanup したい場合は artifact manifest 必須

#### Day 1: artifact sink を作る

* `.ai/artifacts/<task_id>/<run_id>/`
* `artifact_manifest.json`
* stdout / final message / generated files / diff / untracked files を保存
* 保存検証に失敗したら cleanup 中止

#### Day 2: No Worker Commit

* pretool で `git commit` 拒否
* `--no-verify` も拒否
* no-worker commit hook
* posttool HEAD change auditor

#### Day 3: No Shared Worktree Execution

* worker 起動は `run-in-worktree.sh` のみ
* worktree marker 必須
* root/shared write は拒否

#### Day 4: lease marker + allowed_paths

* `.orgos-worktree.json`
* allowed_paths enforcement
* posttool diff scan

#### Day 5: regression drill

実際に以下を試す。

* Codex が commit しようとして止まる
* Codex が main に checkout しようとして止まる
* Codex が output を書いて cleanup されても artifact が残る
* artifact copy に失敗したら worktree が残る
* untracked files が保存される

### 早期検出メトリクス

1. **artifact survival rate**

```text
allowed/audited output files with durable manifest after 24h
-----------------------------------------------------------
allowed/audited output files produced by worker
```

目標は 100%。99% ではだめ。1 件でも消えたら kernel bug。

2. **cleanup-without-manifest count**

```text
number of worktree cleanup operations without verified artifact_manifest
```

目標は 0。

補助指標:

* unauthorized HEAD change count
* run_without_artifact_manifest count
* untracked_files_lost count
* post-exec audit allowed but file missing count

この bug の再発防止は、Week 1 の合格条件に入れるべき。

## Q15. Autonomy 退行

### 設計意図 vs 副作用

autonomy の一部後退は **設計意図**。特に production、migration、secret、destructive command、large diff、cross-project impact は止めるべき。

しかし、低リスク task まで毎回 Owner approval に戻るなら、それは **副作用** であり、設計失敗。Owner 1 人 + 10+ project 並列では、approval なしでは持続しない。

結論:

```text
高リスク autonomy は削る。
低リスク autonomy は standing approval で残す。
中リスク autonomy は batch / time-windowed approval に寄せる。
```

### 維持機構 比較

| 機構                     | 内容                                                  | 向く用途                                          | リスク                   | 推奨度 |
| ---------------------- | --------------------------------------------------- | --------------------------------------------- | --------------------- | --- |
| Standing approval      | 条件に合う task は自動承認                                    | low risk / P2以下 / docs / tests / small bugfix | 条件が広すぎると危険            | 高   |
| Batch approval         | 朝・夕に複数 Plan Contract をまとめて承認                        | medium risk の作業キュー                            | Owner が雑に approve しがち | 高   |
| Time-windowed approval | 次 6 時間だけ特定 project / scope を許可                      | 夜間・週末 autonomy                                | window 内で暴走する可能性      | 中〜高 |
| Diff budget approval   | 変更行数・ファイル数・risk で自動制限                               | 小修正の自律化                                       | 行数だけでは危険度を測れない        | 中   |
| Autonomy envelope      | standing + time + scope + budget + kill switch を束ねる | 10+ project 並列運用                              | 実装がやや重い               | 最高  |
| Full manual approval   | 全部 Owner 承認                                         | high risk                                     | 持続しない                 | 低   |

私の推奨は **Autonomy Envelope**。

例:

```yaml
autonomy_envelope:
  id: AE-LOW-RISK-NIGHTLY
  valid_until: 2026-05-15T08:00:00+09:00
  projects:
    - app-auth
    - app-billing
  allowed_risk:
    - low
    - normal
  allowed_operations:
    - inspect
    - edit
    - test
    - propose_patch
    - integrator_commit_task_branch
  prohibited:
    - production
    - secrets
    - db_migration
    - protected_branch_direct_commit
    - push
  diff_budget:
    max_files: 8
    max_lines: 300
  concurrency:
    max_workers: 2
  stop_conditions:
    - test_failure_twice
    - policy_violation
    - artifact_preservation_failure
    - unauthorized_head_change
```

ここで重要なのは、autonomy を「Manager の裁量」にしないこと。autonomy は capability envelope として定義する。Manager は envelope 内で動く。外に出たら止まる。

### どこまで autonomy を許して安全か

安全に許せる範囲:

* 調査
* read-only analysis
* docs 更新
* test 追加
* small bugfix
* allowed_paths 内の実装
* verifier 実行
* patch proposal
* task branch への integrator commit
* 条件付きで default branch integration

注意付きで許せる範囲:

* default branch への integration
  条件: low/normal risk、diff budget 内、test pass、no shared config、no migration、standing approval あり。

許してはいけない範囲:

* production command
* secret access
* DB migration execution
* destructive SQL
* force push
* protected branch direct manipulation
* dependency major upgrade
* cross-project schema change
* auth/security boundary の大改修
* diff budget 超過

### 個人+AI スケールでの妥当性

autonomy なしは持続しない。

Owner が 1 日にまともに読める Plan Contract は、おそらく 5〜10 件が上限。短いものでも 10〜20 件を超えると rubber-stamp になる。rubber-stamp は approval ではない。むしろ危険な自己欺瞞。

現実的な運用:

* low risk: standing approval
* normal: batch approval
* high: explicit Owner approval
* critical: typed approval + design/execution 分離

Plan Contract は全部に出してよいが、全部を Owner が読む必要はない。standing approval で auto-approved された Plan Contract は、朝の digest で見る。

例:

```text
Nightly Autonomy Digest:
- 7 plans auto-approved by AE-LOW-RISK-NIGHTLY
- 5 completed
- 1 blocked by tests
- 1 blocked by allowed_paths violation
- 0 commits to protected branch
- 0 artifact preservation failures
```

### 事故時責任

責任配分は明文化すべき。

| 事故タイプ                                         | 責任                                     |
| --------------------------------------------- | -------------------------------------- |
| standing approval の範囲内で、想定された低リスク変更が期待外れだった   | Owner の risk acceptance + system の品質問題 |
| standing approval の範囲を超えた操作が実行された             | system bug                             |
| artifact preservation 失敗で成果物消失                | system bug                             |
| Manager が high risk を自己承認した                   | system bug                             |
| Owner が broad standing approval を与えすぎた        | Owner の governance 責任                  |
| policy が曖昧で Manager が危険 scope を low risk 扱いした | shared。policy 設計不備                     |
| verifier failed なのに commit された                | system bug                             |
| Owner manual override で事故                     | Owner 責任                               |

「Owner が standing approval を出したから全部 Owner 責任」は雑すぎる。standing approval は system が範囲を守る前提で成立する。範囲外実行は system bug。

## Summary

3 視点は、runtime enforcement、event/projection、dispatcher Manager、worker sandbox、Owner Plan Contract で強く収束している。ただし 3rd round で重要な訂正がある。Manager は integrator でも Owner proxy でもなく、raw commit は禁止。さらに wrapper bug により、Week 1 の前に artifact preservation / cleanup fail-closed を入れる必要がある。次の一手は **Week 0.5 として "Durable Artifact Before Cleanup" を ship し、その直後に No Worker Commit + No Shared Worktree Execution を入れること**。
