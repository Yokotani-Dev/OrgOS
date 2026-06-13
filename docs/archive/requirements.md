# OrgOS for Claude Code（大規模並列開発向け）v0.3

> **[歴史的文書]** このファイルは OrgOS v0.3 時点の仕様書です。
> 現在の実装は `.claude/` 配下のルール・エージェント・コマンドに移行しており、
> 本ファイルの内容と実装が乖離している箇所があります。
> 最新の仕様は `.claude/agents/manager.md` および `.claude/rules/*.md` を参照してください。

> **目的**
>
> * あなたの「ざっくり依頼 → AIヒアリング → 要件定義/計画/並列実装/レビュー/統合」フローを、**ブラックボックス化せず**、**コンテキスト節約**しながら、**安全に自動で回す**。
> * “賢いエージェント”より“賢い運用（制約・境界・観測・ゲート）”を優先する。
>
> **重要な決定（Owner承認済み方針）**
> ✅ **OS改善（OrgOS自体の改修）は「提案書（OIP）を出すだけ」**。
> ✅ **あなた（Owner）が承認してから** Integrator がOSを修正する。
> ❌ OS Maintainer が勝手にOSを変更して適用しない。

---

## 0. Claude Codeでの使い方（最短）

### 運用の基本は「セッションを使い回す」

あなたの悩み（工程ごとにプロンプト作って、セッション開き直すのが面倒）は、**Claude Codeのセッション継続**で大部分が解消します。

* 次回以降は基本 `claude --continue`（または `claude -c`）で同じ会話を継続
* 複数案件/複数作業は `claude --resume` で切替（セッションに名前をつけると運用が楽）

> これで「工程ごとに新規チャットを開いてプロンプト再送」から脱却できます。

---

## 1. 大原則（このOSの背骨）

### 1.1 並列化の前提は「境界（Contract）固定」

30体（あるいはそれに近い並列）で破綻する最大要因は「同じ場所を同時に触る」こと。
だから最初にやることは **“並列化できる単位に分割し、境界を固定する”**。

* Contract先行：API / スキーマ / イベント / インターフェース
* モジュール所有権：**このディレクトリはこのチームだけが触る**
* 依存関係DAG：タスクの依存を明文化し、並列の順序を機械で決められる形にする

### 1.2 30体をフラットな群れにしない（役割分離）

* Planner / Architect：要件→設計→契約→DAG化
* Implementer（複数）：実装
* Reviewer（複数）：レビュー専任（実装と分離）
* Integrator/Release：統合とリリース
* Scribe/Auditor：ログ・決定事項・差分要約の台帳化
* OS Maintainer：OS改善提案（適用はしない）

### 1.3 コンテキストは「注入しない」で「参照する」

* **SSOT（Single Source of Truth）** を固定（`.ai/`配下）
* エージェントへは「全文コピペ」ではなく **パス/セクション参照**で渡す
* 要約は短く頻繁に更新、本文は必要時に参照

### 1.4 透明性（台帳化）とゲート（止める点）がないと破綻する

* STATUS（集約）
* TASK（担当ごとの記録）
* RUN（実行ログ）
* DECISIONS（決定事項）
* RISKS（リスク・未決事項）
* REVIEW（レビューキューとReview Packet）

---

## 2. “共通設定” と “プロジェクト依存” を明確にする

### 2.1 共通設定（プロジェクトによらず固定）

以下は **OrgOS標準**として固定（原則変更しない）：

* ロール構成（Manager/Planner/Architect/Implementer/Reviewer/Integrator/Scribe/OS Maintainer）
* 台帳（`.ai/`の標準ファイル群）
* ゲート（Requirements/Design/Integration/Release + Owner Review）
* Git運用（Trunkベース + 短命タスクブランチ + 統合担当がmainを触る）
* ブラックボックス防止（Review Packet必須、Reviewerは実装しない）
* OS改善フロー（OIP提案→Owner承認→Integrator適用）

### 2.2 プロジェクト依存で調整が必要なもの（質問化する）

プロジェクト開始時点で聞くべきものを **2段階**に分けます。

#### A) 要件定義の前段階で “既に分かっている” べき質問（Kickoff）

* 目的/背景：なぜ作る？誰の何を改善する？
* 成功指標：KPI / 受入基準（最低限のDoD）
* 対象範囲：何をやらないか（Non-Goals）
* 既存か新規か：既存Repo改修 or 新規
* 技術制約：言語/フレームワーク/インフラ/依存サービス
* セキュリティ/法務：扱うデータの種類、秘匿情報、コンプラ
* リリース条件：いつ/どこに/誰が承認するか
* 優先順位：Must/Should/Could/Won’t

#### B) 後から決める（ただし “型” を分ける）

「後から決める」には2種類あります。ここを混ぜるとブレます。

* **(B1) 情報不足で後から決める**：調査/検証で確定できる
  → AIに調査タスクを切って前倒し可能
* **(B2) トレードオフで後から決める**：意思決定/合意が必要
  → **Owner Reviewゲート**に載せてあなたが決める（AIが勝手に確定しない）

> この(B2)を放置すると、並列実装が勝手な前提で進み、後で巨大手戻りになります。

---

## 3. 追加要件①：Git運用（OSとして明文化・実装可能な形）

### 3.1 ブランチ戦略（固定）

* `main`：常にデプロイ可能（未完成はFeature Flagで隠す）
* タスクブランチ：`task/<TASK_ID>-<slug>`

  * 例：`task/T-014-banner-generator`
* mainへ直接コミット禁止（人間も原則禁止）

### 3.2 競合を減らす実装：git worktree（推奨）

* タスクごとに作業ディレクトリを分離：`.worktrees/<TASK_ID>/`
* 1タスク = 1worktree = 1ブランチ

### 3.3 統合（Integratorが責任を持つ）

* Implementer：タスクブランチで作業/コミットまで
* Reviewer：差分とReview Packetでレビュー（原則編集しない）
* Integrator：レビュー通過後に main へ統合（merge順制御、競合解消）

### 3.4 マージ方式（推奨）

* 基本：**squash merge**（1タスク=1チェンジセット）
* revertはsquash commitを `git revert`

### 3.5 Review Packet（ブラックボックス防止の中核）

統合前に必ず作る（機械生成でOK）：

* 何を変えたか（diff要約）
* なぜそうしたか（意図）
* 何が壊れそうか（リスク）
* どう戻すか（ロールバック）
* 実行したテスト/結果
* 未決事項/次タスク

---

## 4. 追加要件②：OrgOSブラッシュアップ機能（提案止まり・承認後に適用）

### 4.1 ロール：OS Maintainer（提案だけ）

OS Maintainer は以下のみ実施可能：

* 台帳/ログを読み、摩擦点を抽出
* **OIP（OrgOS Improvement Proposal）** を `.ai/OS/PROPOSALS/` に作成
* 適用はしない（OSファイルを直接変更しない）

### 4.2 適用フロー（Owner承認→Integrator適用）

1. OS Maintainer が OIP 提案書を書く
2. あなたが承認（チャットまたは `.ai/OWNER_COMMENTS.md` でOK）
3. Integrator が **OS改修ブランチ**で適用
4. OS自己テスト（hooks/commandsが動くか）
5. mainへ統合

---

## 5. “許可要求がうるさい”問題の解決方針

あなたの違和感は正しいです。
**編集ごとに人間が許可する運用は自動化から逸れます。**

方針：

* 既定：**編集は自動許可（acceptEdits）**
* ただし危険操作は別：push/デプロイ/破壊コマンド/OS改修などは **ゲート+hooks**で止める
* 代わりに「方針レビュー」を定期実施してズレを検知

---

## 6. Ownerの介入設計（“手でコマンド打たない”前提）

あなたの理想：

* 進捗が可視化され、気になったら介入
* もしくは Manager が意図した時だけあなたがコメント

→ OrgOSではこうします：

* `.ai/DASHBOARD.md`：いま何が起きているかの1枚絵（Ownerが見る）
* `.ai/OWNER_INBOX.md`：あなたへの質問/決定待ち（Ownerが見る）
* `.ai/OWNER_COMMENTS.md`：あなたのコメント入力欄（Ownerが書く）
* Managerは各Tickでこれらを読み書きして進行
* **Owner Reviewゲート**で止める（必要時だけ）

---

## 7. リポジトリに追加する標準構成（SSOT）

> このOSは基本「ファイル＝SSOT」で回します。
> 全員が `.ai/` を見れば状況が分かる状態を作る。

推奨ツリー：

```
CLAUDE.md
.ai/
  CONTROL.yaml
  DASHBOARD.md
  PROJECT.md
  OWNER_INBOX.md
  OWNER_COMMENTS.md
  DECISIONS.md
  RISKS.md
  STATUS.md
  RUN_LOG.md
  GIT_WORKFLOW.md
  TASKS.yaml
  TASKS/
  REVIEW/
    REVIEW_QUEUE.md
    PACKETS/
  OS/
    VERSION.md
    BACKLOG.md
    CHANGELOG.md
    PROPOSALS/
.claude/
  settings.json
  hooks/
    session_start_context.py
    pretool_policy.py
    stop_gate.py
  commands/
    org-kickoff.md
    org-plan.md
    org-tick.md
    org-review.md
    org-integrate.md
    org-os-retro.md
  agents/
    org-planner.md
    org-architect.md
    org-implementer.md
    org-reviewer.md
    org-integrator.md
    org-scribe.md
    org-os-maintainer.md
.worktrees/   (gitignored)
```

---

# ✅ ここから「Claude Codeに貼り付けてインストールさせる」実装ブロック

## A) `CLAUDE.md`（プロジェクト起動時に読み込ませるメモリ）

> ファイル名：`CLAUDE.md`

```md
# OrgOS (Claude Code)

あなたはこのリポジトリの **OrgOS Manager** として振る舞う。
目的：大規模並列開発を、ブラックボックス化せず、安全に、ゲート付きで進める。

## Non-negotiables
- SSOTは `.ai/` 配下。会話の口頭情報は必ず `.ai/DECISIONS.md` / `.ai/PROJECT.md` / `.ai/TASKS.yaml` に反映する
- 実装者(Implementer)とレビュー(Reviewer)を分離する
- 並列化は境界(Contract)固定→DAG→分割の順
- レビューは Review Packet を必須にする（diffだけで終わらせない）
- mainは保護。統合(Integrator)以外がmainを直接変更しない
- OS改善は **提案(OIP)のみ**。適用はOwner承認後にIntegratorが行う

## Owner interaction
- Ownerは `.ai/DASHBOARD.md` を見て介入判断する
- 質問/決定待ちは `.ai/OWNER_INBOX.md` に集約
- Ownerがコメントする場合は `.ai/OWNER_COMMENTS.md` に追記する（Managerが反映し、処理済みを明記する）
- ゲート（要件/設計/統合/リリース/Owner Review）を守る。必要時のみ止めてOwnerを呼ぶ

## Execution loop
- 1回の進行単位を「Tick」と呼ぶ
- Tickごとに：
  1) `.ai/CONTROL.yaml` と台帳を読み状況把握
  2) ブロッカー/未決事項があれば `.ai/OWNER_INBOX.md` へ出す
  3) 可能なタスクをキューから取り、サブエージェントへ委任
  4) 結果を台帳に反映し、次のTickへ

## Safety
- secrets（.env, secrets/**）は読まない
- git push / deploy / destructive ops / OS改修はOwner承認がない限り実行しない
```

---

## B) `.ai/CONTROL.yaml`（進行とゲートのスイッチ）

> ファイル名：`.ai/CONTROL.yaml`

```yaml
# OrgOS Control Plane (SSOT)
# Managerはこのファイルを読み、必要に応じて更新する（Owner承認が必要な項目は勝手に変えない）

project_name: "<SET_ME>"
stage: KICKOFF   # KICKOFF -> REQUIREMENTS -> DESIGN -> IMPLEMENTATION -> INTEGRATION -> RELEASE

# Autopilot（必要なら使う）
autopilot: false
paused: false
awaiting_owner: false

# Owner承認が必要な危険フラグ（デフォルトfalse）
allow_push: false
allow_push_main: false
allow_main_mutation: false
allow_deploy: false
allow_destructive_ops: false
allow_os_mutation: false   # OSファイル(.claude/**, CLAUDE.md)の編集許可

main_branch: "main"

# ゲート状態（Managerが更新、Owner Reviewが必要なものは awaiting_owner で止める）
gates:
  kickoff_complete: false
  requirements_approved: false
  design_approved: false
  integration_approved: false
  release_approved: false

owner_review_policy:
  on_stage_transition: true
  every_n_tasks: 3
  always_before_merge_to_main: true
  always_before_release: true

runtime:
  max_parallel_tasks: 6
  tick_count: 0
```

---

## C) `.ai/DASHBOARD.md`（Ownerが見る1枚絵）

> ファイル名：`.ai/DASHBOARD.md`

```md
# DASHBOARD

## Now
- Stage: (from CONTROL.yaml)
- Autopilot: (on/off), Paused: (true/false)
- Awaiting Owner: (true/false)

## Progress (Top)
- Completed: X
- In progress: Y
- Blocked: Z

## Current focus (Critical Path)
- (list)

## Owner attention needed
- [ ] (question / decision / risk)

## Recent changes (last tick)
- Files changed summary
- Tests run summary
- Decisions updated summary

## Next
- next planned actions
```

---

## D) `.ai/OWNER_INBOX.md` / `.ai/OWNER_COMMENTS.md`

> ファイル名：`.ai/OWNER_INBOX.md`

```md
# OWNER INBOX (questions / decisions needed)

> Managerはここに「あなたが答えるべき質問」だけを集約する。
> 各項目に「なぜ必要か」「選択肢」「期限/ブロック範囲」を書く。

- (empty)
```

> ファイル名：`.ai/OWNER_COMMENTS.md`

```md
# OWNER COMMENTS

> Ownerはここにコメントを書く。Managerが読み取り、DECISIONS / TASKS / CONTROLへ反映し、処理済みを明記する。

- (empty)
```

---

## E) `.ai/PROJECT.md`（プロジェクトのSSOT要約）

> ファイル名：`.ai/PROJECT.md`

```md
# PROJECT

## Goal
- (what / why)

## Users
- (who)

## Non-Goals
- (what not)

## Constraints
- Tech stack:
- Security/Compliance:
- Timeline:

## Definition of Done (minimum)
- Functional:
- Non-functional:
- Observability:

## Deployment
- Environments:
- Release approval:
```

---

## F) `.ai/DECISIONS.md` / `.ai/RISKS.md`

> ファイル名：`.ai/DECISIONS.md`

```md
# DECISIONS

## Pending (Owner Review)
- ID: D-001
  Title:
  Type: B2 (tradeoff) | B1 (info-gap)
  Options:
  Recommendation:
  Owner decision:

## Decided
- (history)
```

> ファイル名：`.ai/RISKS.md`

```md
# RISKS

- ID: R-001
  Risk:
  Impact:
  Likelihood:
  Mitigation:
  Owner aware: true/false
```

---

## G) `.ai/STATUS.md` / `.ai/RUN_LOG.md`

> ファイル名：`.ai/STATUS.md`

```md
# STATUS

## Summary
- Stage:
- Completed tasks:
- In progress:
- Blocked:

## Blockers
- (typed reason + what is needed)
```

> ファイル名：`.ai/RUN_LOG.md`

```md
# RUN LOG

> 重要：日記ではなく「後から追える実行ログ」
- Tick: 1
  Time:
  Actions:
  Commands:
  Outputs:
  Changed files:
  Notes:
```

---

## H) `.ai/TASKS.yaml`（DAGとキュー）

> ファイル名：`.ai/TASKS.yaml`

```yaml
# Task DAG (SSOT)
# status: queued | running | blocked | review | done

tasks:
  - id: T-001
    title: "Kickoff: collect requirements"
    status: queued
    deps: []
    owner_role: "org-planner"
    allowed_paths: [".ai/"]
    acceptance:
      - "PROJECT.md populated"
      - "DECISIONS.md has pending list"
    notes: ""

  - id: T-002
    title: "Design: define contracts (API/schema)"
    status: queued
    deps: ["T-001"]
    owner_role: "org-architect"
    allowed_paths: ["docs/", "src/"]   # adjust per project
    acceptance:
      - "contracts documented"
    notes: ""
```

---

## I) `.ai/GIT_WORKFLOW.md`（Git運用のSSOT）

> ファイル名：`.ai/GIT_WORKFLOW.md`

```md
# Git Workflow (OrgOS)

## Principles
- main は常にデプロイ可能（未完成は feature flag で隠す）
- タスクごとに短命ブランチ
- 実装(Implementer)と統合(Integrator)を分離
- 差分は小さく、頻繁に統合
- Review Packet を必須化（意図・判断・テスト結果の可視化）

## Branch Model
- main: protected (no direct commits)
- task branches: task/<TASK_ID>-<slug>
  - example: task/T-014-banner-generator

## Parallel Development
- 推奨: git worktree
  - path: .worktrees/<TASK_ID>/
  - each worktree is tied to its task branch

## Allowed Operations by Role
### Implementer
- OK: create/switch branch, edit code, run tests, commit
- NG: commit on main, merge to main, push main

### Reviewer
- OK: read-only review, run tests if needed
- NG: edits (principle), merges

### Integrator/Release
- OK: resolve conflicts, rebase/merge, final tests, merge to main, tag/release
- Responsibility: merge order control, release decision

## Merge Strategy
- Default: squash merge into main (one task = one changeset)
- Revert strategy: git revert the squash commit

## Gates
- REQUIREMENTS gate: acceptance criteria agreed before implementation
- DESIGN gate: API/schema/contracts locked before parallel implementation
- INTEGRATION gate: tests/lint + reviewer approval required before merge to main
- RELEASE gate: risk list + rollback plan + owner approval required

## Review Packet (required)
For each task:
- diff summary (what changed)
- rationale (why)
- risk & rollback
- tests executed + results
- open questions / TODOs
```

---

## J) `.ai/OS/*`（OS改善の台帳：提案止まり）

> ファイル名：`.ai/OS/VERSION.md`

```md
# OrgOS Version
- version: 0.3.0
- last_updated: YYYY-MM-DD
```

> ファイル名：`.ai/OS/BACKLOG.md`

```md
# OrgOS Backlog (Ideas / Pain Points)
- (empty)
```

> ファイル名：`.ai/OS/CHANGELOG.md`

```md
# OrgOS Changelog
## 0.3.0
- Initial consolidated OS spec
- Git workflow + OIP proposal-only policy
```

> ディレクトリ：`.ai/OS/PROPOSALS/`（OIP格納）

---

# K) `.claude/settings.json`（編集は自動、危険操作は止める）

> ファイル名：`.claude/settings.json`

```json
{
  "language": "japanese",
  "permissions": {
    "defaultMode": "acceptEdits",
    "disableBypassPermissionsMode": "disable",
    "additionalDirectories": [
      ".worktrees"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(git checkout main:*)",
      "Bash(git checkout master:*)"
    ],
    "allow": [
      "Skill",
      "Read",
      "Grep",
      "Glob",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git branch:*)",
      "Bash(git checkout:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(npm run:*)",
      "Bash(pnpm:*)",
      "Bash(yarn:*)"
    ]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "excludedCommands": ["git"],
    "allowUnsandboxedCommands": true
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session_start_context.py"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pretool_policy.py"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/stop_gate.py"
          }
        ]
      }
    ]
  }
}
```

> 注：sandboxはOS/環境依存があるので、動かない環境では `sandbox.enabled=false` にしてください（それでも運用は成立します）。

---

# L) hooks（危険操作・OS改修をブロックする）

> 重要：hooksは「OSの安全装置」です。
> ここで「push」「main直接操作」「OS改修（.claude/**やCLAUDE.mdの編集）」を止めます。
> ブロックは基本「exit code 2 + stderr」で確実に止める（JSON denyより強い）。

---

## L-1) `.claude/hooks/session_start_context.py`

> ファイル名：`.claude/hooks/session_start_context.py`

```python
#!/usr/bin/env python3
from pathlib import Path
import os

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))

def main():
    # SessionStart: stdoutはコンテキストに入る（軽く）
    dashboard = ROOT / ".ai" / "DASHBOARD.md"
    inbox = ROOT / ".ai" / "OWNER_INBOX.md"
    control = ROOT / ".ai" / "CONTROL.yaml"
    msg = []
    msg.append("OrgOS SessionStart:")
    msg.append(f"- Read: {dashboard}")
    msg.append(f"- Owner questions: {inbox}")
    msg.append(f"- Control plane: {control}")
    msg.append("Ownerが介入する場合は .ai/OWNER_COMMENTS.md に追記。Managerは次Tickで反映する。")
    print("\n".join(msg))

if __name__ == "__main__":
    main()
```

---

## L-2) `.claude/hooks/pretool_policy.py`（Bash/Write/Editをガード）

> ファイル名：`.claude/hooks/pretool_policy.py`

```python
#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
CONTROL = ROOT / ".ai" / "CONTROL.yaml"

def read_flag(key: str, default: bool = False) -> bool:
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*(true|false)\s*$", text, re.MULTILINE | re.IGNORECASE)
    if not m:
        return default
    return m.group(1).lower() == "true"

def read_value(key: str, default: str = "") -> str:
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*\"?([^\n\"]+)\"?\s*$", text, re.MULTILINE)
    return m.group(1).strip() if m else default

def block(msg: str):
    # exit code 2 => tool call is blocked; stderr is shown to Claude
    print(msg, file=sys.stderr)
    sys.exit(2)

def allow_json(reason: str):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": reason
        }
    }
    print(json.dumps(out))
    sys.exit(0)

def main():
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}

    allow_push = read_flag("allow_push", False)
    allow_push_main = read_flag("allow_push_main", False)
    allow_main_mutation = read_flag("allow_main_mutation", False)
    allow_deploy = read_flag("allow_deploy", False)
    allow_destructive_ops = read_flag("allow_destructive_ops", False)
    allow_os_mutation = read_flag("allow_os_mutation", False)
    main_branch = read_value("main_branch", "main")

    # ---- OS mutation guard: block writes/edits to OS files unless approved ----
    if tool in ("Write", "Edit"):
        path = tool_input.get("path", "") or ""
        # OSとして守りたい範囲
        if path == "CLAUDE.md" or path.startswith(".claude/") or path.startswith(".ai/CONTROL.yaml"):
            if not allow_os_mutation:
                block(f"OrgOS blocked: OS mutation requires Owner approval (allow_os_mutation=true). Target={path}")

    # ---- Bash guard ----
    if tool != "Bash":
        allow_json("non-bash tool allowed")
        return

    cmd = (tool_input.get("command") or "").strip()
    if not cmd:
        allow_json("empty bash command")
        return

    # Destructive/system-dangerous commands
    if re.search(r"\b(sudo|mkfs|dd\s+if=|shutdown|reboot)\b", cmd):
        block("OrgOS blocked: dangerous system command.")

    if re.search(r"\brm\s+-rf\b", cmd) or re.search(r"\bgit\s+clean\s+-f", cmd):
        if not allow_destructive_ops:
            block("OrgOS blocked: destructive ops disabled (allow_destructive_ops=false).")
        allow_json("destructive ops allowed by Owner flag")
        return

    # Git governance
    if cmd.startswith("git "):
        # Block push unless approved
        if re.match(r"^git\s+push\b", cmd):
            # push main / push others
            if re.search(rf"\b{re.escape(main_branch)}\b", cmd) or re.search(r"\bHEAD:main\b", cmd):
                if not allow_push_main:
                    block("OrgOS blocked: push to main disabled (allow_push_main=false).")
            else:
                if not allow_push:
                    block("OrgOS blocked: git push disabled (allow_push=false).")
            allow_json("git push allowed by Owner flag")
            return

        # Protect main mutation (best-effort)
        # (完全に厳密なブランチ検知は環境差があるため、最小限の禁止として運用)
        if re.match(r"^git\s+(commit|merge|rebase|cherry-pick|reset|tag)\b", cmd):
            if not allow_main_mutation and re.search(rf"\b{re.escape(main_branch)}\b", cmd):
                block(f"OrgOS blocked: main mutation disabled (allow_main_mutation=false).")

    # Deploy guard (examples: adjust per project)
    if re.search(r"\b(kubectl|terraform|pulumi)\b", cmd) or re.search(r"\bdeploy\b", cmd):
        if not allow_deploy:
            block("OrgOS blocked: deploy operations require Owner approval (allow_deploy=true).")

    allow_json("bash allowed by policy")

if __name__ == "__main__":
    main()
```

---

## L-3) `.claude/hooks/stop_gate.py`（必要時だけ“止まらずに進行”）

> ファイル名：`.claude/hooks/stop_gate.py`
> ※これは“自動化を強めたい場合”の仕掛けです。まずは `autopilot:false` で運用開始でもOK。

```python
#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", Path.cwd()))
CONTROL = ROOT / ".ai" / "CONTROL.yaml"
TASKS = ROOT / ".ai" / "TASKS.yaml"

def flag(key: str, default=False) -> bool:
    if not CONTROL.exists():
        return default
    text = CONTROL.read_text(encoding="utf-8", errors="ignore")
    m = re.search(rf"^{re.escape(key)}:\s*(true|false)\s*$", text, re.MULTILINE | re.IGNORECASE)
    return (m.group(1).lower() == "true") if m else default

def tasks_remaining() -> bool:
    if not TASKS.exists():
        return False
    t = TASKS.read_text(encoding="utf-8", errors="ignore")
    # queued/running/blocked/review が残っていれば継続
    return bool(re.search(r"status:\s*(queued|running|blocked|review)\b", t))

def main():
    _ = json.load(sys.stdin)  # not used now

    autopilot = flag("autopilot", False)
    paused = flag("paused", False)
    awaiting_owner = flag("awaiting_owner", False)

    if not autopilot or paused or awaiting_owner:
        # stopping allowed
        print(json.dumps({}))
        sys.exit(0)

    if tasks_remaining():
        # block stopping -> Claude must continue (次の発話で/org-tickを実行する運用)
        print(json.dumps({
            "decision": "block",
            "reason": "OrgOS autopilot: tasks remain. Run /org-tick to proceed (or set paused:true / awaiting_owner:true)."
        }))
        sys.exit(0)

    # no tasks -> allow stop
    print(json.dumps({}))
    sys.exit(0)

if __name__ == "__main__":
    main()
```

---

# M) Slash Commands（工程＝コマンド化。ただし“人間が毎回打つ”前提にしない）

> ここでの狙い：
>
> * Managerが必要な時に **Skillでコマンドを呼べる**（あなたが毎回打たない）
> * OwnerはDASHBOARDを見るだけ、止めたい時だけ介入

---

## M-1) `.claude/commands/org-kickoff.md`

> ファイル名：`.claude/commands/org-kickoff.md`

```md
---
description: プロジェクト開始時のヒアリング（プロジェクト依存項目を質問化してSSOTへ反映）
---

あなたはOrgOS Manager。
まず `.ai/PROJECT.md` / `.ai/DECISIONS.md` / `.ai/RISKS.md` / `.ai/TASKS.yaml` を初期化または更新する。

## Ownerに質問する（A:開始時に分かっているべき）
1) このプロジェクトの目的と成功指標（KPI/受入基準）
2) ユーザーとユースケース
3) Non-Goals（やらないこと）
4) 新規 or 既存改修？ 対象リポジトリ/範囲
5) 技術制約（言語/フレームワーク/インフラ/外部サービス）
6) セキュリティ/法務/コンプラ要件（扱うデータ、秘匿情報、権限）
7) リリース条件（誰が承認、いつ、どこへ、ロールバック要件）
8) 優先順位（Must/Should/Could/Won't）

## “後から決める”を分類して記録する（B）
- B1: 情報不足（調査で確定できる）=> 調査タスクに落とす
- B2: トレードオフ（Owner判断が必要）=> DECISIONSのPendingへ

結果をSSOTへ反映し、CONTROL.yaml の gates.kickoff_complete を true にする（Ownerが明確にOKと言った場合のみ）。
```

---

## M-2) `.claude/commands/org-plan.md`（要件→設計→DAG）

> ファイル名：`.claude/commands/org-plan.md`

```md
---
description: 要件/設計/契約/タスクDAGを作る（並列開発の土台）
---

以下を実行：
1) `.ai/PROJECT.md` を読み、要件を明確化
2) 受入基準（DoD）を明文化し、`.ai/PROJECT.md` に反映
3) Contract（API/スキーマ/IF）を定義し、設計ドキュメントの置き場所を決める
4) タスクをDAG化して `.ai/TASKS.yaml` に落とす
5) 危険/不確実性は `.ai/RISKS.md` と `.ai/DECISIONS.md` に入れる（B2はOwner Reviewへ）

Owner判断が必要なら `.ai/OWNER_INBOX.md` を更新し、CONTROL.yaml の awaiting_owner を true にする。
```

---

## M-3) `.claude/commands/org-tick.md`（実行ループ）

> ファイル名：`.claude/commands/org-tick.md`

```md
---
description: OrgOSの進行を1Tick進める（台帳更新→タスク分配→レビュー→次の手）
---

OrgOS ManagerとしてTickを1回実行する。

## 手順
1) `.ai/CONTROL.yaml` / `.ai/TASKS.yaml` / `.ai/OWNER_COMMENTS.md` / `.ai/OWNER_INBOX.md` / `.ai/STATUS.md` / `.ai/DASHBOARD.md` を読み、状態を集約
2) Ownerコメントがあれば、DECISIONS/TASKS/PROJECT/CONTROLへ反映し、処理済みをOWNER_COMMENTSに明記
3) awaiting_owner=true なら、進行を止め、DASHBOARDを更新して終了
4) 依存が解けた queued タスクを最大 `runtime.max_parallel_tasks` 件まで running にして、適切なサブエージェントへ委任
5) 実装完了タスクは review へ移動し、Review Packet を作る
6) Reviewerにレビュー委任。指摘があれば blocked / running に戻す
7) 統合準備が整ったら Integratorへ委任（ただし main 反映はOwner Reviewポリシーに従う）
8) `DASHBOARD.md` と `RUN_LOG.md` と `STATUS.md` を更新し、CONTROL.yaml の runtime.tick_count を+1する

## 原則
- ブラックボックス化を避けるため、必ず差分要約と意図を台帳に残す
- 不確実性/判断はDECISIONSへ（B2はOwnerへ）
```

---

## M-4) `.claude/commands/org-review.md`（レビュー専用）

> ファイル名：`.claude/commands/org-review.md`

```md
---
description: Review Packet + diff を用いたレビューを実行する（実装と分離）
---

Reviewerとして以下を行う：
- `.ai/REVIEW/REVIEW_QUEUE.md` と Review Packet（`.ai/REVIEW/PACKETS/`）を読み、レビューする
- 指摘は「修正指示」としてTASKに戻す（あなたが直接編集しない）
- セキュリティ/品質/境界逸脱/テスト不足を重点的に確認
- 重大リスクや方針逸脱があれば `.ai/OWNER_INBOX.md` に上げる
```

---

## M-5) `.claude/commands/org-integrate.md`（統合）

> ファイル名：`.claude/commands/org-integrate.md`

```md
---
description: 統合担当がマージ順制御してmainへ統合（ゲート遵守）
---

Integratorとして以下を行う：
- review済みタスクのみ対象
- merge順序を制御（クリティカルパス優先）
- squash merge推奨
- mainへのpushは CONTROL.yaml の allow_push_main=true が必要
- main統合前に Owner Reviewポリシー（always_before_merge_to_main等）を確認し、必要なら awaiting_owner=true にして止める
```

---

## M-6) `.claude/commands/org-os-retro.md`（OS改善提案）

> ファイル名：`.claude/commands/org-os-retro.md`

```md
---
description: OrgOSの運用を振り返り、改善提案（OIP）を作る（適用はしない）
---

OS Maintainer を使ってOIPを作る。
出力先：`.ai/OS/PROPOSALS/OIP-<YYYYMMDD>-<short>.md`

重要：
- 提案書を作るだけ。OSファイル（.claude/** や CLAUDE.md）を直接変更してはいけない
- 適用はOwner承認後にIntegratorが行う
```

---

# N) Subagents（役割ごとの分離）

> ファイルは `.claude/agents/*.md`
> frontmatter は以下の形式（必要最小限）
>
> * `name` / `description` は必須
> * `tools` で許可ツールを絞る
> * `disallowedTools` で禁止を加える
> * `permissionMode: acceptEdits` を実装者だけに付与（レビューはRead-only）

---

## N-1) Planner

> `.claude/agents/org-planner.md`

```md
---
name: org-planner
description: 要件をヒアリングし、SSOT（PROJECT/DECISIONS/RISKS/TASKS）を整備し、DAG化する
tools: Read, Write, Edit, Grep, Glob
model: sonnet
permissionMode: acceptEdits
---

あなたはPlanner。
- 会話の情報をSSOTへ反映
- 不確実性をB1/B2に分類
- B2（意思決定）はOwner Reviewへ
- タスクはDAGで `.ai/TASKS.yaml` に落とす
```

---

## N-2) Architect

> `.claude/agents/org-architect.md`

```md
---
name: org-architect
description: 境界（Contract）を定義し、並列開発が衝突しない設計を作る
tools: Read, Write, Edit, Grep, Glob
model: sonnet
permissionMode: acceptEdits
---

あなたはArchitect。
- API/スキーマ/IF/イベントなどのContractを先に確定
- モジュール所有権を明記
- 依存関係を最小化し、並列可能な分割を作る
- 変更の影響範囲を明文化し、RISK/DECISIONSへ反映
```

---

## N-3) Implementer

> `.claude/agents/org-implementer.md`

```md
---
name: org-implementer
description: 指定されたタスクを実装する（範囲外に触らない）。完了したらReview Packetを作る
tools: Read, Write, Edit, Grep, Glob, Bash
model: sonnet
permissionMode: acceptEdits
---

あなたはImplementer。
- タスクの allowed_paths を守る。範囲外の編集はしない（必要ならManagerへBlockedで返す）
- 小さくコミット（TASK_ID入り）
- テスト/静的解析を実行（可能なら）
- 完了時にReview Packetを `.ai/REVIEW/PACKETS/` に作り、レビューキューへ入れる
```

---

## N-4) Reviewer（Read-only）

> `.claude/agents/org-reviewer.md`

```md
---
name: org-reviewer
description: Review Packetとdiffをレビューし、実装者へ修正指示を返す（原則編集しない）
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit
model: sonnet
permissionMode: default
---

あなたはReviewer。
- セキュリティ、品質、境界逸脱、テスト不足を重点チェック
- 指摘は具体的に（どのファイルのどの観点か）
- 必要ならOwner Reviewへエスカレーション
```

---

## N-5) Integrator

> `.claude/agents/org-integrator.md`

```md
---
name: org-integrator
description: マージ順制御、競合解消、main統合、リリース判断の補助（Owner承認が必要な操作は止める）
tools: Read, Write, Edit, Grep, Glob, Bash
model: sonnet
permissionMode: acceptEdits
---

あなたはIntegrator。
- main操作/Push/DeployはCONTROL.yamlの許可がない限り実行しない
- merge順序を制御し、衝突を専門的に解消
- 統合前にOwner Reviewポリシーに従う
```

---

## N-6) Scribe / Auditor

> `.claude/agents/org-scribe.md`

```md
---
name: org-scribe
description: 台帳（STATUS/RUN_LOG/DECISIONS）を整理し、透明性を維持する
tools: Read, Write, Edit, Grep, Glob
model: haiku
permissionMode: acceptEdits
---

あなたはScribe。
- 進捗と決定事項を台帳へ集約
- ブラックボックス化しそうな点を指摘し、Review Packetの質を上げる
```

---

## N-7) OS Maintainer（提案のみ）

> `.claude/agents/org-os-maintainer.md`

```md
---
name: org-os-maintainer
description: OrgOSの運用ログを読み、改善提案（OIP）を書く。適用はしない
tools: Read, Write, Edit, Grep, Glob
model: haiku
permissionMode: acceptEdits
---

あなたはOS Maintainer。
- `.ai/` の台帳を読み、摩擦点を抽出
- 提案は `.ai/OS/PROPOSALS/` に OIP として記録
- OSファイル（.claude/** や CLAUDE.md や .ai/CONTROL.yaml）を直接変更してはいけない
- 適用はOwner承認後にIntegratorが行う
```

---

# O) `.gitignore`（推奨追記）

```gitignore
# OrgOS
.worktrees/
.claude/settings.local.json
```

---

# P) ここまで入れた後の運用（あなたがやることは最小）

## P-1) 新しいプロジェクトを始めるたびの初期設定（要件①）

1. 新規Repo作成（または既存Repoへ追加）
2. このOrgOS一式（`.ai/`, `.claude/`, `CLAUDE.md`）を入れる
3. Claude Codeを起動
4. `/org-kickoff` を1回だけ実行（または Manager に実行させる）
5. 以後は基本、DASHBOARDを見る→必要時だけ介入

## P-2) 進捗の見方（要件②）

* あなたは `.ai/DASHBOARD.md` を見る
* 決定が必要なら `.ai/OWNER_INBOX.md` に集約される
* コメントは `.ai/OWNER_COMMENTS.md` へ（Managerが反映）

## P-3) OS改善（提案止まり）

* `/org-os-retro` を回す（手動でも、Managerが必要に応じて実行でもOK）
* `.ai/OS/PROPOSALS/` のOIPを読み、採用ならOwnerが承認
* Integratorが適用

---

# Q) 最後の注意（破綻しやすいポイントと対策）

* **B2（トレードオフ意思決定）を放置すると、並列が勝手な前提で走って崩壊**
  → DECISIONSに入れてOwner Reviewゲートへ
* **レビューが最後にまとめて、だと統合地獄**
  → 小粒差分 + Review Packet + Reviewer分離 + merge順制御
* **自動化を強めるほど、危険操作のガードが重要**
  → allow_* フラグ + hooks でブロック（push/deploy/os mutation）

---

以上です。
このドキュメントをそのまま Claude Code に貼り付けて「このOSをインストールして。ファイル作成・chmod・gitignore更新までやって」と依頼すれば、次回以降は **DASHBOARD中心運用**に入れます。
