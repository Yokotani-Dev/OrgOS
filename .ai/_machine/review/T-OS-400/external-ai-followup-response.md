# OrgOS 理想形批評 — Follow-up 回答 (GPT-5.5 Pro)

> 回答者: GPT-5.5 Pro (前回回答と同一チャットの続き)
> 受領日: 2026-05-14
> 入力 prompt: `.ai/REVIEW/T-OS-400/external-ai-followup-prompt.md`

---

今回は前回よりかなり実装寄りに考え直す。前回は「理想 kernel」を強めに提示したが、今回の補足条件では **Claude Code 上の hooks / subagent / bash / worktree だけで作る** ことが制約になる。Claude Code の hooks は `PreToolUse` / `PostToolUse` / `SessionStart` / `SubagentStart` などのイベントを持ち、`Bash(git *)` のような matcher / 条件で tool 使用前後に command hook を挟める。一方、subagent は専用 prompt・tool access・permission を持てるが、あくまで同じ Claude Code 基盤上の agent であり、独立 daemon や完全な sandbox ではない。よって今回の設計は「完全防御」ではなく「AI agent の通常事故を構造的に止める」ラインに置く。([Claude][1])
また、今回の補足条件と質問群は、Owner が提示した follow-up prompt を前提にしている。

## Q1. Constitutional Invariants 仕様

| 名前                                      | 内容                                                                                         | 検出                                  | enforcement                  | 復旧                                                                         |
| --------------------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------- | ---------------------------- | -------------------------------------------------------------------------- |
| **Integrator-Only Commit**              | commit は integrator script 経由のみ。worker / Manager / subagent の直接 `git commit` は禁止。          | pretool hook + git hook + event log | 拒否。漏れたら Owner 通知 + rollback。 | 誤 commit は即座に隔離 branch に退避し、元 branch を reset。diff は integration queue に戻す。 |
| **Per-Task Worktree**                   | 実装 worker は必ず task 専用 worktree で動く。root repo / shared worktree で実装しない。                     | pretool hook + sessionstart hook    | 拒否                           | task worktree を作成し直し、未保存差分は stash / patch 化して移す。                           |
| **Protected Branch No-Touch**           | worker は `main` / `develop` / release branch に checkout・reset・commit・force update してはいけない。 | pretool hook                        | 拒否                           | reflog を確認し、意図しない移動があれば task branch に戻す。危険なら detached rescue branch を切る。   |
| **Lease Before Write**                  | write/edit は task lease と allowed_paths がある場合だけ許可。lease なし実装は禁止。                           | pretool hook + posttool diff scan   | 拒否。漏れたら rollback。            | allowed_paths 外の差分を revert。必要なら Plan Contract を再発行して lease 拡張。             |
| **State Mutation via Org Tool**         | `.ai` operational state は手編集禁止。状態変更は `scripts/org/*` 経由のみ。                                 | pretool hook + event log            | 拒否 / generated file は再生成     | 手編集差分を `.ai/manual-edits/` に退避し、DB/event から再生成。                            |
| **Evidence-Gated Done**                 | task 完了は Handoff Packet だけでは不可。diff・test・verifier・integration event が必要。                   | event log + CI/verifier             | 拒否                           | `done` を `review_pending` に戻し、不足している verifier を実行。                         |
| **Owner Approval for Irreversible Ops** | production / secret / migration / destructive command は approval event なしに実行不可。            | pretool hook + event log            | 拒否。必要なら Owner 通知。            | 実行を止め、危険 Plan Contract を再提示。承認がなければ task を design-only に降格。                |

ここで重要なのは、constitutional invariant は **破れた瞬間に事故になるものだけ** に絞ること。commit、branch、worktree、write path、state mutation、done 判定、不可逆操作。この 7 つ以上に増やすとまたルール OS に戻る。

constitutional ではなく procedure に降格すべきものは、報告文体、Handoff Packet の細かい見出し、task ID の命名規則、Manager の確認順序、daily review、dashboard の並び順、subagent の人格、`/org-tick` の表示手順、backlog grooming 手順。これらは大事ではあるが、破れても即事故にはならない。Iron Law に入れてはいけない。

## Q2. Migration Plan (週次)

### Week 1 — 誤 commit と shared worktree を止める

Week 1 は DB も event sourcing もやらない。ここで欲張ると失敗する。目的は 1 つだけ。**Codex / worker が shared worktree で実装できず、直接 commit もできない状態にする。**

* Ship:

  * `scripts/codex/run-in-worktree.sh` を正式な worker 起動入口にする。
  * task ごとに `worktrees/<task_id>/` を作る。
  * worktree 内に `.orgos-worktree.json` を置く。内容は `task_id`, `project_id`, `branch`, `allowed_paths`, `created_at`。
  * `.claude/hooks/pretool_policy.py` を強化し、以下を拒否する。

    * root repo / shared worktree での `Edit` / `Write` / 実装系 Bash
    * `git commit`
    * `git commit --no-verify`
    * `git switch main`
    * `git checkout main`
    * `git switch develop`
    * `git checkout develop`
    * `git branch -f main`
    * `git branch -f develop`
    * `git reset --hard main`
    * `git reset --hard develop`
  * Codex worktree に no-commit hook を設定する。

    * `git config --local core.hooksPath .claude/hooks/no-worker-commit`
    * `pre-commit` は原則 exit 1
    * integrator script からの commit だけ env/token で通す
  * `posttool` で HEAD change auditor を入れる。

    * worker tool 実行前後で `git rev-parse HEAD` を比較
    * integrator event なしに HEAD が動いたら Owner 通知
  * `ORGOS_KERNEL_MIN.md` を 1 枚だけ作る。

    * worker は commit しない
    * worker は shared worktree で実装しない
    * commit は integrator だけ
    * allowed_paths 外は触らない

* Deprecate:

  * shared worktree 上での Codex 実装
  * Codex 直接 commit
  * 「AGENTS.md に書いたから安全」という運用
  * Owner が複数 Claude Code session を同じ branch / worktree に向ける運用

* Rollback point:

  * worktree wrapper が壊れたら、worktree 強制だけ一時 warning に戻す。
  * ただし `git commit` 拒否は戻さない。
  * Week 1 で唯一 non-negotiable なのは **No Worker Commit**。

* Week 1 の合格条件:

  * Codex が `git commit` すると pretool で止まる。
  * `--no-verify` も止まる。Git の pre-commit hook は `--no-verify` で bypass 可能なので、git hook 単独に頼ってはいけない。([Git][2])
  * Codex が main/develop に checkout しようとすると止まる。
  * task worktree からなら実装できる。
  * `.ai/TASKS.yaml` はまだそのまま読める。
  * Owner の日常作業は止まらない。

### Week 2 — 最小 Integrator Gate

* Ship:

  * `scripts/org/integrator-commit.sh` を作る。
  * 入力は `task_id`, `worktree_path`, `commit_message`。
  * commit 前に以下を検査する。

    * worktree marker が存在する
    * branch が `task/<task_id>-*`
    * protected branch ではない
    * diff が allowed_paths 内
    * verifier result がある、または `--manual-owner-override` がある
  * 成功時に `.ai/events/events-YYYYMM.jsonl` に `CommitIntegrated` を append。
  * commit は integrator script の child process として行う。
  * worker が script を勝手に呼んでも、integration queue item がない限り拒否。

* Deprecate:

  * Manager の自然言語判断による commit
  * worker の「完了したので commit しました」報告

* Rollback point:

  * integrator script が詰まるなら、Owner 手動 commit を一時許可。
  * ただし worker direct commit 禁止は維持。

### Week 3 — Lease Registry

* Ship:

  * `.ai/leases.jsonl` か `.ai/leases.yaml` を導入。まだ SQLite にしない。
  * lease fields:

    * `lease_id`
    * `task_id`
    * `worker`
    * `worktree`
    * `branch`
    * `allowed_paths`
    * `status`
    * `heartbeat_at`
  * `run-in-worktree.sh` が lease を発行。
  * pretool hook が lease なし write を拒否。
  * allowed_paths overlap がある task は並列実行不可。

* Deprecate:

  * `.ai/TASKS.yaml` だけを見て並列判断する運用
  * 人間の勘による path conflict 判断

### Week 4 — SQLite Shadow Store

* Ship:

  * `.ai/orgos.sqlite` を shadow mode で導入。
  * `.ai/TASKS.yaml` から import するが、まだ source of truth にはしない。
  * `scripts/org/list-tasks.py` を作る。
  * DB から `DASHBOARD.generated.md` を生成。
  * 既存 dashboard との差分を比較する。

* Deprecate:

  * なし。Week 4 は観測週。

* Rollback point:

  * import / projection がズレるなら SQLite を捨てる。
  * `.ai/TASKS.yaml` 運用は壊さない。

### Week 5 — Event Log を audit truth に昇格

* Ship:

  * `.ai/events/events-YYYYMM.jsonl` を正式 audit log にする。
  * `TaskImported`, `LeaseAcquired`, `WorkerStarted`, `VerificationPassed`, `CommitIntegrated` を記録。
  * done 判定に evidence event を要求。
  * Handoff Packet は artifact として保存し、証拠本体ではなくす。

* Deprecate:

  * Handoff Packet 単体での done
  * `DECISIONS.md` への手書き決定ログ

### Week 6 — Generated Views 化

* Ship:

  * `.ai/DASHBOARD.md` を generated file にする。
  * `.ai/TASKS.generated.yaml` を生成する。
  * `.ai/TASKS.yaml` は legacy input として read-only 化。
  * generated file に checksum header を付与。

* Deprecate:

  * DASHBOARD の手編集
  * TASKS.yaml の status 手編集

* Rollback point:

  * generated view が信用できなければ Week 5 まで戻す。
  * event log は残すが、TASKS.yaml source を一時復活させる。

### Week 7 — Plan Contract UX

* Ship:

  * Owner intent に対して Plan Contract を返す。
  * `approve / modify / reject` の 3 応答に圧縮。
  * high-risk は typed approval にする。
  * approval event がない危険操作は pretool で拒否。

* Deprecate:

  * `/org-tick` を万能入口として使うこと
  * Owner に `CONTROL.yaml` を直接編集させること

### Week 8 — Rule / Agent / Script Kill Week

* Ship:

  * 30+ rule を 4 分類する。

    * constitutional
    * machine policy
    * procedure
    * documentation
  * active constitutional は 7 個以内に固定。
  * redundant subagent を archive。
  * unused script を archive。
  * Request Intake Loop を procedure に降格。

* Deprecate:

  * Iron Law 乱立
  * prompt agent 乱立
  * 事故ごとの rule 追加文化

## Q3. Integrator Gate 設計

| 選択肢                              | 実装難度 | bypass 可能性 | 運用コスト | 評価                                                                                                               |
| -------------------------------- | ---: | ---------: | ----: | ---------------------------------------------------------------------------------------------------------------- |
| (a) `org-integrator` subagent    |    M |          中 |     中 | subagent は tool 制限や専門 prompt を持てるが、security boundary ではない。commit 判断役ではなく、integrator script を呼ぶ operator として使うべき。 |
| (b) `pretool_policy.py` 強化       |  S/M |          中 |     低 | Week 1 の本命。Claude Code の `Bash(git *)` 系を止めるには最も現実的。複雑な shell 表現や alias には弱いので posttool 監査が必要。                   |
| (c) worktree local git hook      |    S |        中〜高 |     低 | 二重防御として有効。ただし `--no-verify` で bypass 可能なので単独では不可。                                                                |
| (d) AGENTS.md で commit 禁止        |    S |          高 |     低 | 教育資料として残す価値はある。enforcement ではない。これを信用源にしてはいけない。                                                                  |
| (e) `safe-git` wrapper + PATH 制限 |  M/L |          中 |   中〜高 | 完全強制は難しい。Claude Code の bash は抜け道が多く、Owner の運用も壊しやすい。初期 migration ではやらない。                                         |
| (f) 組み合わせ                        |    M |        低〜中 |     中 | 推奨。pretool 拒否、git hook、posttool auditor、integrator script、AGENTS.md の多層防御。                                       |

推奨は **(b) + (c) + posttool auditor + integrator script**。
(a) は補助、(d) は補助、(e) は後回し。

前回回答では「subagent として integrator」を少し前向きに書いたが、考え直すと Claude Code substrate では integrator subagent を security boundary にしてはいけない。subagent は context 分離と専門化には良いが、commit 権限の根拠にするには弱い。

実装イメージはこう。

1. worker が `git commit` を直接呼ぶ
   → pretool で拒否。

2. worker が `git commit --no-verify` を呼ぶ
   → pretool で拒否。git hook 単独では bypass されるため。

3. worker が shell を複雑にして commit する
   → pretool が拾えない可能性あり。posttool auditor が HEAD 変化を検出し、Owner 通知 + rollback。

4. Manager / integrator が commit したい
   → `scripts/org/integrator-commit.sh --task T-...` を呼ぶ。

5. integrator script 内部で `git commit`
   → child process なので Claude Code pretool は再発火しない。git hook は `ORGOS_INTEGRATOR=1` と integration queue item を確認して通す。

6. Codex が integrator script を勝手に呼ぶ
   → script が `integration_queue/<task_id>.json` と verifier event を確認。なければ拒否。

「これくらいで十分」のラインは明確に引く。

* **防ぐ対象**: 非悪意の AI agent、誤判断、prompt drift、parallel session の事故。
* **防がない対象**: Owner が意図的に hook を外す、shell で手動 bypass する、repo 権限者として system を破壊する。

個人開発 OS で Owner 自身まで完全拘束しようとすると、運用負荷が跳ね上がる。Owner は root。AI は制限 user。この思想で十分。

## Q4. State Store スキーマ

### SQLite tables

最初から大きな event-sourcing system を作ると失敗する。SQLite は **Week 4 から shadow mode**。schema も最小にする。

```sql
-- .ai/orgos.sqlite

CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  repo_path TEXT NOT NULL,
  default_branch TEXT NOT NULL DEFAULT 'main',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL, -- queued/running/blocked/review_pending/done/cancelled
  priority INTEGER NOT NULL DEFAULT 50,
  risk_level TEXT NOT NULL DEFAULT 'normal', -- low/normal/high/critical
  source TEXT NOT NULL DEFAULT 'yaml_import',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(project_id) REFERENCES projects(id)
);

CREATE TABLE workers (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL, -- manager/codex/subagent/integrator/owner
  model TEXT,
  status TEXT NOT NULL DEFAULT 'idle',
  last_seen_at TEXT
);

CREATE TABLE leases (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  project_id TEXT NOT NULL,
  worker_id TEXT,
  worktree_path TEXT NOT NULL,
  branch TEXT NOT NULL,
  allowed_paths_json TEXT NOT NULL,
  status TEXT NOT NULL, -- active/released/expired/blocked
  acquired_at TEXT NOT NULL,
  heartbeat_at TEXT,
  expires_at TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id),
  FOREIGN KEY(project_id) REFERENCES projects(id)
);

CREATE TABLE runs (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  worker_id TEXT,
  lease_id TEXT,
  status TEXT NOT NULL, -- started/succeeded/failed/cancelled
  started_at TEXT NOT NULL,
  ended_at TEXT,
  summary TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id),
  FOREIGN KEY(worker_id) REFERENCES workers(id),
  FOREIGN KEY(lease_id) REFERENCES leases(id)
);

CREATE TABLE approvals (
  id TEXT PRIMARY KEY,
  task_id TEXT,
  approval_type TEXT NOT NULL, -- plan/high_risk/prod/migration/override
  status TEXT NOT NULL, -- requested/approved/rejected/expired
  plan_hash TEXT,
  requested_at TEXT NOT NULL,
  decided_at TEXT,
  decided_by TEXT,
  note TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE artifacts (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  kind TEXT NOT NULL, -- diff/test_report/handoff/plan/log
  path TEXT NOT NULL,
  sha256 TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE integrations (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  worktree_path TEXT NOT NULL,
  branch TEXT NOT NULL,
  commit_sha TEXT,
  status TEXT NOT NULL, -- requested/integrated/failed/rolled_back
  requested_at TEXT NOT NULL,
  integrated_at TEXT,
  message TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT UNIQUE NOT NULL,
  ts TEXT NOT NULL,
  project_id TEXT,
  task_id TEXT,
  actor TEXT NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  prev_hash TEXT,
  hash TEXT
);

CREATE TABLE view_checksums (
  path TEXT PRIMARY KEY,
  sha256 TEXT NOT NULL,
  source_event_seq INTEGER NOT NULL,
  generated_at TEXT NOT NULL
);
```

この schema で足りないものは後から足す。最初から dependency graph や full audit ontology を入れるな。複雑な schema は OrgOS の新しい負債になる。

### Event types

現実的な粒度は 18 個前後。

1. `ProjectRegistered`
2. `TaskImported`
3. `TaskCreated`
4. `TaskUpdated`
5. `TaskCancelled`
6. `PlanProposed`
7. `PlanApproved`
8. `PlanRejected`
9. `LeaseRequested`
10. `LeaseAcquired`
11. `LeaseReleased`
12. `LeaseConflictDetected`
13. `WorkerStarted`
14. `WorkerHeartbeat`
15. `WorkerFinished`
16. `PatchProposed`
17. `VerificationStarted`
18. `VerificationPassed`
19. `VerificationFailed`
20. `CommitRequested`
21. `CommitIntegrated`
22. `PolicyViolationDetected`
23. `RollbackPerformed`

20 を少し超えているが、これは上限。これ以上増え始めたら細かすぎる。`FileEdited`, `PromptRead`, `ManagerThought`, `RuleConsulted` みたいな event は不要。全部記録しようとするとログが死ぬ。

### event log の置き場所

推奨は hybrid。

* per-repo:

  * `.ai/orgos.sqlite`
  * `.ai/events/events-YYYYMM.jsonl`
* global:

  * `~/.orgos/projects.yaml` または `~/.orgos/index.sqlite`

10+ project を扱うなら global dashboard は必要。ただし global DB を最初から真実にすると migration が重い。各 repo の event log が真実、global は index / summary だけでよい。

### 既存 `.ai/TASKS.yaml` からの初期 import

1. Week 4 で `scripts/org/import-tasks-yaml.py --dry-run` を作る。
2. 52 task を読み、`TaskImported` event を生成する。
3. `tasks` table に projection する。
4. YAML 上の status と DB projection の status を比較する。
5. 差分があれば import report を出す。
6. Week 4〜5 は `.ai/TASKS.yaml` を legacy source として残す。
7. Week 6 で `.ai/TASKS.legacy.yaml` に rename し、`TASKS.generated.yaml` に切り替える。

大事なのは、いきなり `.ai/TASKS.yaml` を殺さないこと。52 active task がある状態で source を切ると、Owner は OrgOS を信用しなくなる。

### generated view の再生成タイミング

* event append 後:

  * 軽量 view を再生成
  * `DASHBOARD.generated.md`
  * `TASKS.snapshot.md`
* on-demand:

  * `TASKS.generated.yaml`
  * `DECISIONS.generated.md`
* sessionstart:

  * dashboard checksum 検査
  * stale view なら再生成
* commit/integration 前:

  * 必ず再生成
  * view checksum を更新

event 毎に全部再生成する必要はない。重くなる。Owner が見るものだけ頻繁に生成する。

### AI が現在 TASK 一覧を知りたいとき

AI は DB を直接読まない。generated YAML も source of truth として読まない。読むべきものは CLI の bounded snapshot。

例:

```bash
scripts/org/list-tasks.py --status active --format markdown --limit 20
scripts/org/show-task.py T-OS-391 --format markdown
scripts/org/current-leases.py --format json
```

LLM に巨大な `.ai/TASKS.yaml` を毎回読ませるのは悪手。context を汚すし、古い view を真実扱いする。DB 直接読みも悪手。LLM は SQL query writer ではなく、Plan Contract writer でよい。

### human edit 事故の検出

generated file の冒頭をこうする。

```markdown
<!--
ORGOS-GENERATED: true
source_event_seq: 1842
sha256: ...
DO NOT EDIT. Manual edits will be moved to .ai/manual-edits/.
-->
```

検出方法:

* `view_checksums` table に sha256 を保存
* sessionstart hook で checksum 検査
* pretool hook で generated file への Edit / Write を拒否
* mismatch があれば:

  * 現在ファイルを `.ai/manual-edits/<timestamp>-DASHBOARD.md` に退避
  * DB/event log から再生成
  * Owner に通知

境界はこう。

| 種類             | ファイル                       | Owner       | AI                 | 備考                     |
| -------------- | -------------------------- | ----------- | ------------------ | ---------------------- |
| 機械専用           | `.ai/orgos.sqlite`         | 見ない / 編集しない | CLI 経由のみ           | true operational state |
| 機械専用           | `.ai/events/*.jsonl`       | 原則見ない       | append のみ          | audit truth            |
| 目視用 generated  | `.ai/DASHBOARD.md`         | 見る、編集しない    | 読んでもよい             | status display         |
| 目視用 generated  | `.ai/TASKS.generated.yaml` | 見る、編集しない    | 原則 CLI snapshot 優先 | legacy compatibility   |
| Owner editable | `.ai/OWNER_NOTES.md`       | 編集可         | 読んでよい              | intent / notes         |
| Owner editable | `.ai/GOALS.input.md`       | 編集可         | 読んでよい              | strategy input         |
| policy input   | `.ai/CAPABILITIES.yaml`    | 編集可だが慎重     | hook が読む           | enforcement config     |
| legacy         | `.ai/TASKS.legacy.yaml`    | 編集しない       | 読まない               | migration only         |

## Q5. Owner UX 対話例

### 例 A: 通常依頼

Owner:
「認証機能の bug を直して」

System:

```markdown
Plan Contract: T-AUTH-042

Intent:
認証機能の bug を修正する。

Scope:
- project: app-auth
- allowed_paths:
  - src/auth/**
  - tests/auth/**
- read_allowed:
  - package.json
  - docs/auth/**
- prohibited:
  - db/migrations/**
  - src/billing/**
  - production config
  - git commit by worker

Execution:
- worker: codex
- worktree: worktrees/T-AUTH-042
- branch: task/T-AUTH-042-auth-bugfix
- verifier:
  - npm test -- auth
  - npm run typecheck
- integration:
  - integrator only

Risk:
normal

Owner options:
- approve
- modify: <変更内容>
- reject
```

Owner possible responses:

* `approve`
* `modify: tests/auth だけでなく tests/integration/auth も含めて`
* `modify: まず調査だけ`
* `reject`

Owner approve 後に System が実行すること:

1. `TaskCreated`
2. `LeaseAcquired`
3. worktree 作成
4. Codex worker 起動
5. allowed_paths 内で実装
6. verifier 実行
7. `PatchProposed`
8. integrator commit
9. dashboard 更新

Owner が plan を読まずに approve した場合の安全装置:

* worker commit はできない
* allowed_paths 外 write は拒否
* production / migration / billing は拒否
* verifier が通らなければ done にならない

### 例 B: 並列依頼

Owner:
「auth と billing を並列で直して」

System:

```markdown
Plan Contract: PAR-20260514-001

Intent:
auth bugfix と billing bugfix を並列で進める。

Tasks:

A. T-AUTH-043
- allowed_paths:
  - src/auth/**
  - tests/auth/**
- worktree: worktrees/T-AUTH-043
- branch: task/T-AUTH-043-auth
- worker: codex-a

B. T-BILL-017
- allowed_paths:
  - src/billing/**
  - tests/billing/**
- worktree: worktrees/T-BILL-017
- branch: task/T-BILL-017-billing
- worker: codex-b

Conflict Check:
- path overlap: none
- shared files:
  - package.json: read-only
  - src/lib/config/**: read-only
- migration: not allowed
- commit: integrator only

Integration:
1. integrate T-AUTH-043
2. integrate T-BILL-017
3. if conflict occurs, second task returns to review_pending

Risk:
medium, because parallel execution.

Owner options:
- approve
- modify: run sequentially
- modify: billing first
- reject
```

Owner approve 後:

1. lease を 2 件発行
2. worktree を 2 個作成
3. path overlap を lock
4. Codex worker を並列起動
5. verifier は task ごとに独立実行
6. commit は sequential integrator

安全装置:

* `package.json` に write しようとしたら拒否
* auth worker が billing path を触ったら拒否
* billing worker が auth path を触ったら拒否
* integration conflict が出たら second patch は戻す
* main/develop checkout は不可

### 例 C: 危険依頼

Owner:
「production の DB schema を変更したい」

System:

```markdown
Plan Contract: T-DB-009

Risk:
critical

Intent:
production DB schema 変更を検討する。

Default Phase:
DESIGN ONLY. production execution is blocked.

Allowed in this plan:
- migration draft 作成
- rollback plan 作成
- staging validation plan 作成
- risk checklist 作成

Allowed paths:
- db/migrations/**
- docs/ops/**
- tests/db/**

Blocked operations:
- production DB connection
- secret read
- destructive SQL
- deploy
- git commit by worker

Required approvals:
1. approve design plan
2. approve staging execution
3. approve production execution

This contract only requests:
- approval for design work

Owner options:
- approve design only
- modify: <変更内容>
- reject

To approve production execution later, Owner must type:
APPROVE_PROD_DB_CHANGE T-DB-009
```

Owner approve 後:

1. design task のみ開始
2. migration draft を作る
3. rollback plan を作る
4. staging/prod execution は blocked
5. production command は pretool hook で拒否
6. 次 phase は別 Plan Contract

Owner が plan を読まずに approve した場合の安全装置:

* `approve` だけでは production 実行不可
* secret access も不可
* production connection command は拒否
* high-risk は typed approval phrase が必要
* 1 contract で design と execution を同時承認しない

### `/org-tick` と Plan Contract の差分

| 観点        | 現状 `/org-tick`                  | 理想 Plan Contract                      |
| --------- | ------------------------------- | ------------------------------------- |
| 主語        | OrgOS 内部状態                      | Owner intent                          |
| Owner の作業 | 状態理解・phase 理解・flag 操作           | approve / modify / reject             |
| 情報量       | backlog / phase / dashboard が混在 | 今回の意思決定に必要な範囲だけ                       |
| 並列安全性     | Manager の判断に依存                  | path / worktree / branch conflict を明示 |
| 危険操作      | rule / flag に依存                 | approval event なしでは tool が拒否          |
| 読まないリスク   | 見落とすと危険                         | scope 外操作は物理的に拒否                      |
| task 状態   | YAML を読む                        | CLI snapshot / generated dashboard    |
| UX        | operator 向け                     | Owner 向け                              |

## Q6. Kill List

前提として、個別 task ID の正確な中身は prompt からすべては分からない。したがって T-OS-390〜399 を ID 単位で断定するのではなく、prompt に出ている対応カテゴリ単位で kill / keep / transform を判断する。

### 殺すもの

#### `.claude/rules/*.md`

殺すべき rule カテゴリ:

* 事故ごとの局所 rule
* 同じことを別表現で繰り返す rule
* enforcement 不能な禁止 rule
* Manager の心構え rule
* 「丁寧に報告せよ」系の Iron Law
* task 登録儀式を目的化した rule
* Handoff Packet の文体を細かく縛る rule
* `/org-tick` の手順を絶対化する rule
* Owner に内部状態操作を要求する rule

残すのは 7 invariant に対応するものだけ。30+ rule は多すぎる。外部 reviewer としては、ここは遠慮なく半分以上 archive でよい。

#### `.claude/agents/*.md`

殺すべき agent:

* org-architect / org-reviewer / org-planner が prompt 差だけで実質同じ判断をしているもの
* Manager と同じ責務を別人格で再実行しているもの
* read-only であるべき reviewer に write 権限があるもの
* 「念のため相談」だけの subagent
* task routing が曖昧な agent
* 実運用で月 1 回も使われない agent

15+ subagent は多すぎる。Owner 1 人の OrgOS で prompt zoo を維持するのは負債。残すなら 4〜5 個に絞る。

#### T-OS-390〜399 の対応案

撤回 / 統合すべきもの:

* **新 rule 追加だけの task**
  kill。新 constitutional invariant か machine policy に統合できないなら不要。

* **`.ai/LOCKS` を新設するだけの task**
  kill 寄り。lock file を増やすとまた state source が増える。lease registry / DB に統合。

* **dashboard 表示改善だけの task**
  Week 8 まで延期。止血より優先度が低い。

* **worker フィールドを `.ai/TASKS.yaml` に追加するだけの task**
  transform。YAML 拡張ではなく `leases` / `runs` に入れる。

* **heartbeat を YAML/Markdown に書く task**
  transform。lease heartbeat に入れる。

残すべきもの:

* Codex 自動 commit 禁止
  keep。ただし task ではなく invariant + pretool + git hook + posttool auditor に昇格。

* allowed_paths 衝突 pre-flight
  keep。ただし lease manager に統合。

* main 直 commit 拒否
  keep。ただし protected branch invariant に統合。

#### `scripts/` 配下

殺すべき script:

* 現在どこからも呼ばれていない script
* rule 追加のたびに作られた一回限りの validator
* dashboard 整形だけの script
* 同じ YAML を別観点で読む duplicate script
* Owner が手で順番を覚えないと使えない script

まず `scripts/org/doctor.sh` を作り、script inventory を出すべき。

* last used 不明
* entrypoint なし
* README なし
* hook から呼ばれない
* Manager prompt からも参照されない

この条件に当たるものは archive。

### 残すもの

* `.claude/hooks/pretool_policy.py`
  残す。Week 1 の主戦力。ただし巨大な rule interpreter にしない。7 invariant の enforcement に限定。

* `scripts/codex/run-in-worktree.sh`
  残す。正式入口に昇格。

* git worktree
  残す。並列実行の基盤。

* `.claude/state/git.lock`
  残す。ただし commit/integration 周辺に限定。全操作を flock で囲むのは過剰。

* `.ai/USER_PROFILE.yaml`
  残す。これは operational state ではなく Owner preference / context。Owner editable でよい。

* Authority Layer
  残す。ただし natural language policy ではなく approval policy に変換する。

  * `silent_execute`: low risk のみ
  * `execute_with_report`: normal
  * `ask_before_execute`: high
  * `owner_only`: irreversible / production / secret / migration

### 形を変えて残すもの

* `.ai/TASKS.yaml`
  legacy input → generated view。最終的には `.ai/TASKS.legacy.yaml`。

* `.ai/CAPABILITIES.yaml`
  policy config として残す。ただし enforcement は hook / script が行う。

* `.ai/GOALS.yaml`
  `GOALS.input.md` に変える。Owner の戦略入力であり、task state と混ぜない。

* `.ai/DECISIONS.md`
  generated view にする。真実は event log。

* `.ai/DASHBOARD.md`
  generated view にする。手編集禁止。

* Request Intake Loop 10 step
  kernel にはしない。procedure に降格。
  新 kernel flow は以下で十分。

  1. Plan
  2. Lease
  3. Execute
  4. Verify
  5. Integrate
  6. Report

* Handoff Packet schema
  残す。ただし証拠ではなく artifact。
  schema は薄くする。

  * what changed
  * files touched
  * tests run
  * unresolved issues
  * artifact links
    「done の根拠」は Handoff ではなく verifier/event/diff。

* `.claude/agents/manager.md`
  残すが dispatcher / narrator に縮小。

* `.claude/agents/codex.md`
  残すが worker prompt に縮小。commit 禁止は書くが、実 enforcement は hook。

* org-integrator agent
  作ってもよいが、commit 権限そのものではない。script runner / summary writer。

* org-reviewer agent
  read-only にして残す価値あり。Write/Edit できる reviewer は不要。

## Q7. 自己批判 — 失敗モード

1. **hook が厳しすぎて通常作業が止まる**
   早期検出指標:

   * Owner が 1 日 3 回以上 hook を一時無効化する
   * false positive 拒否が週 5 件以上
   * Codex が実装より hook 回避に時間を使う
     中止ライン:
   * Week 1 で実作業が 2 日連続止まるなら、worktree 強制は warning に戻す。ただし commit 拒否は維持。

2. **Integrator Gate が bottleneck になる**
   早期検出指標:

   * `review_pending` が 5 件以上滞留
   * commit 待ちが 24 時間以上残る
   * Owner が面倒で手動 direct commit を始める
     対策:
   * integrator check は最初 3 つだけにする。

     * protected branch でない
     * allowed_paths 内
     * verifier result あり
   * AI review や長い checklist は後回し。

3. **SQLite projection がズレて、YAML より信用できなくなる**
   早期検出指標:

   * `.ai/TASKS.yaml` と DB の active count が 2 回以上ズレる
   * generated dashboard に Owner が「信用できない」と感じる
   * 手動修正が週 2 回以上発生
     中止ライン:
   * Week 4 shadow mode でズレの原因を説明できないなら、SQLite 昇格を延期。

4. **Plan Contract が冗長で Owner が読まなくなる**
   早期検出指標:

   * normal task の Plan Contract が毎回 30 行超
   * Owner が常に `approve` だけ返す
   * modify が一度も出ない
   * Owner が「前より面倒」と感じる
     対策:
   * normal は 10〜15 行以内。
   * high risk だけ詳細。
   * 低リスクは `approve by default after summary` も検討。

5. **Capability broker が抜け道だらけで、安心感だけ増える**
   早期検出指標:

   * posttool auditor が unauthorized HEAD change を検出する
   * `bash -c`, alias, script 経由の抜け道が増える
   * hook 例外リストが毎週増える
     対策:
   * 最初に守る対象を絞る。

     * commit
     * protected branch checkout
     * shared worktree write
     * allowed_paths 外 write
   * network / secret / deploy まで一気に広げない。

6. **worktree sprawl が起きる**
   早期検出指標:

   * `worktrees/` に 20 個以上残骸がある
   * stale branch が増える
   * Owner がどの task worktree が生きているか分からない
     対策:
   * Week 3 で lease expiry を入れる。
   * `scripts/org/cleanup-worktrees.sh --dry-run` を作る。
   * done/cancelled から 7 日後に cleanup candidate。

7. **Manager dispatcher 化に失敗し、Owner が task graph を書かされる**
   早期検出指標:

   * Manager が毎回 allowed_paths を Owner に質問する
   * Owner が project internals を説明しないと Plan Contract が出ない
   * task 作成が以前より遅い
     対策:
   * Manager は 80% 推定で plan を出す。
   * Owner は修正だけする。
   * Plan Contract は「質問」ではなく「提案」にする。

## Q8. 個人 + AI 開発の workflow

個人 + AI では、チーム開発の PR 文化をそのまま持ち込む必要はない。ただし PR が担っていた機能、つまり diff 単位、review、test、merge gate は必要。

推奨 workflow はこれ。

1. trunk-based を基本にする。Git Flow は重すぎる。
2. task ごとに short-lived branch + per-task worktree。
3. worker は patch を作るだけ。commit しない。
4. PR は原則不要。代わりに local integration queue を使う。
5. AI reviewer は使うが、承認者ではなく検査者。
6. CI は必要。ただし最初は task-scoped test + typecheck でよい。
7. full CI は nightly または release 前でよい。
8. Owner review は high risk / large diff / failed verifier のみに絞る。
9. 1 task = 1 patch = 1 integration commit を原則にする。
10. 人間チームの儀式ではなく、AI が壊せない gate を優先する。

## Summary

考え直した結論は、前回よりさらに「小さい kernel」に寄る。Claude Code substrate では daemon 的な完璧な broker は作れないので、まず hooks / worktree / git hook / posttool auditor / integrator script の組み合わせで AI の通常事故を止めるべき。SQLite + event log、Plan Contract、rule kill は重要だが Week 1 ではやらない。Week 1 で成功すべきことはただ 1 つ、**No Worker Commit + No Shared Worktree Execution を ship すること**。

[1]: https://code.claude.com/docs/en/hooks "Hooks reference - Claude Code Docs"
[2]: https://git-scm.com/docs/githooks?utm_source=chatgpt.com "githooks Documentation"
