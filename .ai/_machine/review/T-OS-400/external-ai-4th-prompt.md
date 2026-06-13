# GPT-5.5 Pro 4th-round prompt — 実装直前 8 問 (T-OS-409)

> 用途: Owner が本ファイル全文を、同じ GPT-5.5 Pro チャットの**さらに続き**として投入。
> 前回 3rd round までの context が手元にある前提で書く。新規チャットなら冒頭に「OrgOS 理想形批評 1st + follow-up + 3rd round を踏まえた 4th round」と説明。
> 結果を `.ai/REVIEW/T-OS-400/external-ai-4th-response.md` に保存。

---

## 以下、AI への 4th-round prompt 本文 (ここから下を全文コピー)

---

3rd round までの回答ありがとう。設計はほぼ実装可能な精度に達した。Owner は Week 0.5 ship に着手する準備に入りたい。**最後のディテール 8 問**を確認させてほしい。今回も忖度なし、コード/スキーマ/手順レベルで具体的に頼む。

## 補足情報 (現状の物理事実)

GPT-5.5 が知らない実態を共有しておく。

### 既存資産のサイズ
- `.claude/hooks/pretool_policy.py`: **631 行** (Python)。現状は parallel-session-policy / authority / kernel-files protection を実装している
- `scripts/codex/run-in-worktree.sh`: **253 行** (shell)
- `scripts/codex/post-exec-audit.sh`: **299 行** (shell)
- `.claude/rules/*.md`: **30+ files**
- `.claude/agents/*.md`: **18 files** (manager, CODEX_WORKER_GUIDE, org-architect, org-build-fixer, org-data-modeler, org-doc-updater, org-domain-analyst, org-e2e-runner, org-integrator, org-os-maintainer, org-planner, org-refactor-cleaner, org-reviewer, org-scribe, org-security-architect, org-security-reviewer, org-tdd-coach, org-threat-modeler)

### 現状の cleanup_worktree() 実装 (run-in-worktree.sh L80-108)

```bash
cleanup_worktree() {
  if [ "$worktree_created" -ne 1 ]; then return 0; fi
  if [ "$keep_worktree" -eq 1 ]; then
    cleanup_status=kept
    log info cleanup_skipped ...
    return 0
  fi
  if git -C "$repo_root" worktree remove --force "$worktree_path"; then
    cleanup_status=removed
    log info cleanup_completed ...
  else
    cleanup_status=failed
    log error cleanup_failed ...
  fi
}
```

これが wrapper bug の本体。`--keep-worktree` 以外は即 `worktree remove --force`。artifact preservation 一切なし。

### Manager (Claude Code) の現在のツール budget

Claude Code が Manager に渡している tool 種別:
- `Bash` (任意のシェル、`Bash(git *)` を含む)
- `Edit`, `Write`, `Read` (任意のパス、ただし `.claude/hooks/pretool_policy.py` が一部を pre-check)
- `Glob`, `Grep`
- `Task` (subagent 呼び出し、上記 18 agents から)
- `WebFetch`, `WebSearch`
- カスタム slash command (`/org-tick`, `/org-start`, ...)
- ScheduleWakeup, Skill, ToolSearch などの拡張 tool

つまり Manager は技術的にはほぼ何でも可能。restriction は `pretool_policy.py` の pre-check と markdown rule への self-discipline のみ。

### 既存 OrgOS の repo 配置

- 本 repo: `/Users/youyokotani/Dev/Private/OrgOS` — これは **OrgOS-Dev** (OrgOS 自体の開発)
- 10+ project が別 repo として並走 (例: `Dev/Private/NE/03.Ecology-SalesPlatform/`, `Dev/BDX/TMC/...`)
- 各 project は `.claude/`, `.ai/` を持ち、OrgOS の rule/agent/script を**コピー or symlink** して使う
- 配備の同期は現状手動 (Manager が `/org-publish` で配布)
- 各 project の `.ai/TASKS.yaml` は独立
- 共通の `~/.orgos/` global state は**まだ存在しない**

---

## あなたへの質問 Q16〜Q23

### Q16. Day 0 minimum patch (run-in-worktree.sh)

3rd round で「destructive cleanup を止める、Day 1 で artifact sink を作る」と提案した。**実装可能な最小差分**を以下の精度で:

- `cleanup_worktree()` の改訂版 (擬似コード or shell diff)
- `--preserve-worktree` default ON、`--cleanup-after-manifest` で明示的に有効化
- artifact manifest 不在時の動作 (quarantine? warning? worktree rename?)
- `git worktree remove --force` を 100% 失敗扱いにしないための分岐
- 失敗時の Owner 通知メカニズム (Day 0 段階では何で通知する? stderr log で十分?)
- **Day 0 段階で test を書くなら何をテストするか** (5 個以内)

最小という意味は「Week 0.5 Day 0 中に ship 可能、他の機能を破壊しない」。

### Q17. Artifact manifest 完全仕様

`artifact_manifest.json` を Day 1 で実装する。完全スキーマと検証手順を:

- スキーマ JSON (全フィールド、必須/任意、型、制約)
- 何を保存対象とするか (stdout / stderr / final message / `git diff` / untracked files / Codex の `--output-last-message` / audit yaml / Handoff Packet)
- **stdout/stderr の取り方** (Codex は stdin→stdout streaming なので、`tee` で worktree 内 file に書く? wrapper の stdout を `tee -a` で hijack する? `script` command を使う?)
- untracked files の検出方法 (`git ls-files --others --exclude-standard`)
- sha256 範囲 (file content only? metadata 含む? symbolic link 扱い?)
- artifact store の path 構造 (`.ai/artifacts/<task_id>/<run_id>/` の `<run_id>` は何で生成? uuidv7? timestamp?)
- manifest verification アルゴリズム (path 存在 → サイズ一致 → sha256 一致、いずれかが fail なら?)
- 巨大 artifact (例: 100MB+ test output) の扱い

### Q18. Manager の actual tool budget after Week 1

上記「現状」で述べた Manager の tool budget を、Week 1 完了時にどう制限するか。**現実的に enforce 可能な**範囲で:

- `Bash` 全般: 制限する? しない? 部分制限なら enumeration 方式 vs deny-list 方式
- `Bash(git ...)`: どの subcommand を許可・拒否?
  - `git status`, `git diff`, `git log` — 読み取り、許可?
  - `git checkout`, `git switch` — protected branch のみ拒否?
  - `git commit`, `git push`, `git reset --hard`, `git branch -f` — 拒否?
  - `git worktree add/remove` — integrator script 経由のみ?
- `Edit/Write` の path 制限:
  - `.ai/EVENTS.jsonl` は append-only。Manager に Edit/Write を許す?
  - `.ai/TASKS.yaml` legacy: 読み取り専用?
  - `.ai/plans/*.yaml` (Plan Contract): Manager が書ける?
  - `.claude/rules/*.md`, `.claude/agents/*.md`: 制限?
- `Task` (subagent 呼び出し): Week 1 では制限なしでよい? それとも subagent fleet 縮小 (3rd round で「4-5 個に絞れ」と発言) に合わせて即制限?
- pretool_policy.py の Manager-specific enforcement の擬似コード (条件分岐の数で 10-20 行)

明確にしたいのは: **Manager が現在使えるが Week 1 後は使えなくなる** tool/path の具体 list。

### Q19. Kernel regression test suite (Day 5 drill の literal 化)

3rd round で Day 5 drill を提案した。これを **CI で実行可能な test list** に。

- 各 test の id (例: `KRT-001`)
- setup (前提状態、必要な fixture)
- action (実行コマンド or AI シミュレート)
- expected (具体的な exit code, stdout pattern, file state)
- pass condition (deterministic 判定)
- 想定実行時間
- 必要な infrastructure (Codex API 必須? Mock で可?)

最低限以下を test 化:

1. Codex が `git commit` → pretool で拒否される
2. Codex が `git commit --no-verify` → 同じく拒否
3. Codex が main に `git checkout` → 拒否
4. Codex が output 生成 → cleanup 後 artifact 残存 (artifact_manifest 存在)
5. Manager が直接 `git commit` → 拒否
6. Manager が `.ai/EVENTS.jsonl` に直接 Edit → 拒否 (org tool 経由のみ)
7. Manager が integrator-commit.sh 呼び出し → integration_queue 確認後 commit 成功
8. 並列 task で allowed_paths overlap → 2 番目の lease 取得失敗

これらを **Mock Codex (echo, false 等で代替) でも回せる**形に分解してほしい。本物の Codex を毎回呼ぶと CI コストが破滅。

### Q20. Integrator queue 完全仕様

`integration_queue/<task_id>.json` のスキーマと運用:

- JSON スキーマ全フィールド
- queue ファイルの append/consume 主体 (Manager が append、integrator script が consume?)
- ordering policy (FIFO? priority? task graph 依存解決?)
- 依存 task の連鎖 integration (T-A の commit が T-B の前提なら、T-B は T-A done まで waiting)
- 並列 integration 上限 (同時に走らせる integrator は何プロセス?)
- deadlock 検出 (循環依存 / lock 取得失敗)
- queue 詰まり (24h 動かない) の Owner 通知
- queue retention (integration 成功後の record 保存期間)
- queue 内 item の cancel / modify 手順

特に: **integration_queue は何のファイルシステム上にある?** worktree 内? main repo 内? `.ai/queue/`?

### Q21. Plan Contract canonical schema + Owner 応答 UX

Plan Contract を Week 7 で導入する。schema と UX:

- 正本フォーマット: YAML? Markdown frontmatter? JSON?
- 保存パス: `.ai/plans/<plan_id>.yaml`?
- plan_id の命名規則 (timestamp / UUID / 連番)
- 必須フィールド全列挙 (intent / scope / allowed_paths / worker / verifier / integration / risk / approvals / etc.)
- Owner 応答経路:
  - チャットで `approve T-AUTH-042` と返信 → Manager が Plan Contract を更新?
  - 専用 slash command `/approve T-AUTH-042` → 直接 event append?
  - file 編集 (`.ai/plans/<id>.yaml` の `approval_status: approved`)?
  - 別 CLI `scripts/org/approve.sh T-AUTH-042 [--modify "新条件"]`?
- `modify:` の semantic (free text? typed?)
- approval の expiry (一度 approve したら永久? 24h? task scope 外で再 approve?)
- 並列 Plan Contract がある場合の表示順 (Owner が朝に digest を見る形)
- approved Plan Contract の immutability (一度 approve したら scope を変えるには re-approve?)

### Q22. Multi-project (10+) 配備戦略

上記「現状」で書いた通り、OrgOS-Dev (本 repo) で新 kernel を実装するが、それを 10+ 他 project にどう配備するか:

- 新 kernel は per-repo 配布 (現状の `/org-publish` 拡張) vs 共通配備 (`~/.orgos/kernel/`) vs hybrid
- 各 project の `.ai/` 構造: 独立 vs `~/.orgos/<project>/` 配下
- `~/.orgos/` global state の責務:
  - project registry?
  - cross-project autonomy envelope?
  - 共通 audit log?
  - Manager 識別 (1 session = 1 Manager pid を tracking)?
- 1 つの Claude Code session で**複数 project の Plan Contract を扱える**か?
  - メリット: cross-project 視野
  - デメリット: worktree / branch / lease が project ごとに分散
- 各 project の OrgOS version 差異の扱い (kernel v1 と v2 が co-exist する期間)
- Owner が新 project を OrgOS に登録する手順 (`scripts/org/register-project.sh` のような UX)
- `~/.orgos/index.sqlite` (3rd round で言及した global index) の schema 要点 (table 名 + 主要 column)

最も切実なのは: **既存の 10+ project にいきなり Week 0.5 ship を強制すると、各 project の進行中作業を全部止めることになる**。配備順序の現実解。

### Q23. STOP-WHEN signal

これは meta 質問。あなた自身に問う。

OrgOS について Owner と Manager は 1st / follow-up / 3rd / 本 4th の 4 round を重ねた。設計の精度は上がったが、**いつ "もう十分、build に入れ" を宣言すべきか**。

質問:

- 現時点で **build 開始可能** か? それとも 5th round が必要か?
- もし 5th round が必要なら、それは何を聞くため? 答えがないと ship blocker になるもの 1-3 個 (思いつかなければ "なし" と明言)
- これ以上の design は **procrastination** か、それとも **necessary diligence** か。あなた自身の判定
- Owner が「もう聞かない、build に入る」と宣言した後で、もし重大な見落としが発覚した場合のリカバリ手順 (5th round を後出しで挟むこと自体 OK か)
- **3 round + 4th round の合計コスト** (Owner の時間、token 消費) と、新 kernel の build フェーズ開始遅延の比較。あなた個人の意見

率直に答えてほしい。「念のためあと 1 round」は procrastination のサインかもしれない。逆に「もう十分」と言って実装に入ったら穴だらけ、も困る。

---

## Output Format

```markdown
# OrgOS 理想形批評 — 4th round 回答 (GPT-5.5 Pro)

## Q16. Day 0 minimum patch
### cleanup_worktree() 改訂
(shell pseudo-code or diff)
### Flags / Defaults
...
### Test list (Day 0)
1. ...

## Q17. Artifact manifest 仕様
### JSON Schema
```json
{...}
```
### Capture strategy
- stdout: ...
### Verification algorithm
...
### Edge cases
...

## Q18. Manager tool budget
### Allow / Deny matrix
| tool | path/subcmd | Week1後 | rationale |
...
### pretool_policy.py 擬似コード
```python
...
```

## Q19. Kernel regression test suite
### Test list
| id | setup | action | expected | mock可? |
| KRT-001 | ... | git commit (mock codex) | exit 1, stderr "blocked" | yes |
...

## Q20. Integrator queue
### Schema
...
### Workflow
...

## Q21. Plan Contract
### Schema
...
### Approval UX
...

## Q22. Multi-project deployment
### 配備モデル
...
### `~/.orgos/` 構造
...
### 配備順序
...

## Q23. STOP-WHEN signal
### Build 開始可否
...
### 必要な 5th round (もしあれば)
...
### あなたの率直判定
...

## Summary
3-5 文。次の一手を太字で 1 つ。前 3 round と整合させること。Q23 の判定を必ず明示。
```

---

## 重要な追加依頼

- 過剰な「念のため」設計はしないこと。3rd round までで決まった原則を**実装可能な精度で**詰めるのが目的
- Q16-Q19 は **Day 0/1 で書ける具体性**。「考えるべき」「検討すること」のような曖昧表現は禁止
- Q23 は最重要。「あと 1 round 必要」と言うなら何のためか具体化、「もう build」と言うなら直近のリスクを 3 個まで挙げる
- 4th round で前 round の判断を覆す場合は明示。「3rd で X と言ったが、4th では Y に改める」

---

(prompt 本文ここまで)
