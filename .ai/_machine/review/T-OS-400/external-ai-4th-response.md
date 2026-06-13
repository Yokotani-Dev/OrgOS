# OrgOS 理想形批評 — 4th round 回答 (GPT-5.5 Pro)

> 回答者: GPT-5.5 Pro (1st + follow-up + 3rd + 4th の連続チャット)
> 受領日: 2026-05-14
> 入力 prompt: `.ai/REVIEW/T-OS-400/external-ai-4th-prompt.md`
> **判定: STOP DESIGN. START BUILD.**

---

## Q16. Day 0 minimum patch

### cleanup_worktree() 改訂

Day 0 の目的は「成果物保全の仕組みを完成させる」ではなく、**成果物保全なしに worktree を消す挙動を止める**こと。したがって最小 patch は、`cleanup_worktree()` を fail-closed に変えること。

既存の `git worktree remove --force` は完全撤廃ではなく、**manifest 検証済みの場合だけ許可**にする。Day 0 では manifest がまだ本格実装されていないので、デフォルトでは worktree は残る。

```bash
# Defaults near top of run-in-worktree.sh
keep_worktree=1                    # Day 0: preserve by default
cleanup_after_manifest=0            # explicit opt-in only
artifact_manifest_path=""
cleanup_status="not_started"
cleanup_error=0

# New flags:
#   --preserve-worktree          default; keep worktree after run
#   --cleanup-after-manifest     remove worktree only after verified manifest
#   --artifact-manifest PATH     manifest path to verify before cleanup
```

```bash
notify_owner() {
  # Day 0: stderr + repo-local alert log is enough.
  # No Slack/Webhook/daemon. Do not add new infra yet.
  local level="$1"; shift
  local msg="$*"

  echo "ORGOS_${level}: ${msg}" >&2

  if [ -n "${repo_root:-}" ]; then
    mkdir -p "$repo_root/.ai/alerts"
    printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg" \
      >> "$repo_root/.ai/alerts/worktree-cleanup.log" || true
  fi
}

verify_artifact_manifest_minimal() {
  # Day 0 minimal verifier.
  # Day 1 replaces/extends this with scripts/org/verify-artifact-manifest.py.
  local manifest="$1"

  if [ -z "$manifest" ]; then
    return 10
  fi
  if [ ! -f "$manifest" ]; then
    return 11
  fi
  if [ ! -s "$manifest" ]; then
    return 12
  fi

  # If python exists, at least ensure valid JSON.
  python3 - "$manifest" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    data = json.load(f)
required = ["schema_version", "task_id", "run_id", "artifacts"]
missing = [k for k in required if k not in data]
if missing:
    print("missing required keys: " + ",".join(missing), file=sys.stderr)
    sys.exit(2)
if not isinstance(data["artifacts"], list):
    print("artifacts must be list", file=sys.stderr)
    sys.exit(3)
sys.exit(0)
PY
}

mark_worktree_quarantined() {
  local reason="$1"
  cleanup_status="quarantined"
  cleanup_error=1

  if [ -n "${worktree_path:-}" ] && [ -d "$worktree_path" ]; then
    cat > "$worktree_path/.orgos-quarantine" <<EOF
reason: ${reason}
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
task_id: ${task_id:-unknown}
repo_root: ${repo_root:-unknown}
EOF
  fi

  notify_owner "CLEANUP_BLOCKED" \
    "worktree preserved/quarantined: task=${task_id:-unknown} path=${worktree_path:-unknown} reason=${reason}"
}

cleanup_worktree() {
  if [ "$worktree_created" -ne 1 ]; then
    cleanup_status="not_created"
    return 0
  fi

  if [ -z "${worktree_path:-}" ] || [ ! -d "$worktree_path" ]; then
    cleanup_status="missing_path"
    notify_owner "CLEANUP_WARN" "worktree path missing before cleanup: ${worktree_path:-unset}"
    return 0
  fi

  # Day 0 default: preserve. This is intentionally conservative.
  if [ "$keep_worktree" -eq 1 ] && [ "$cleanup_after_manifest" -ne 1 ]; then
    cleanup_status="kept"
    log info cleanup_skipped task_id="$task_id" worktree_path="$worktree_path" reason="preserve_worktree_default"
    return 0
  fi

  # Cleanup is allowed only through explicit --cleanup-after-manifest.
  if [ "$cleanup_after_manifest" -ne 1 ]; then
    mark_worktree_quarantined "cleanup_requested_without_cleanup_after_manifest"
    return 0
  fi

  # Manifest must exist and pass minimal validation.
  if ! verify_artifact_manifest_minimal "$artifact_manifest_path"; then
    mark_worktree_quarantined "artifact_manifest_missing_or_invalid"
    return 0
  fi

  # Only here is git worktree remove allowed.
  if git -C "$repo_root" worktree remove --force "$worktree_path"; then
    cleanup_status="removed_after_manifest"
    log info cleanup_completed task_id="$task_id" worktree_path="$worktree_path" manifest="$artifact_manifest_path"
    return 0
  else
    cleanup_status="remove_failed"
    cleanup_error=1
    notify_owner "CLEANUP_FAILED" \
      "git worktree remove failed after manifest verification: task=${task_id:-unknown} path=${worktree_path:-unknown}"
    return 0
  fi
}
```

重要点は 3 つ。

1. `--preserve-worktree` が default。
2. `--cleanup-after-manifest` がない限り remove しない。
3. manifest 検証が失敗した場合は、worktree を消さず `.orgos-quarantine` marker を置く。

「quarantine? rename?」については、**Day 0 では rename しない**。Git worktree はパスを勝手に rename すると repo 側 metadata とズレる。Day 0 は marker file で十分。rename は余計な事故を増やす。

### Flags / Defaults

推奨 flag behavior:

| flag                       | Day 0 behavior                       |
| -------------------------- | ------------------------------------ |
| no flag                    | worktree を残す                         |
| `--preserve-worktree`      | worktree を残す。default と同じ             |
| `--keep-worktree`          | 既存互換。worktree を残す                    |
| `--cleanup-after-manifest` | manifest 検証後のみ cleanup               |
| `--artifact-manifest PATH` | cleanup 前に検証する manifest              |
| `--force-cleanup`          | Day 0 では作らない。Owner override を増やすのは早い |

`git worktree remove --force` は悪ではない。**manifest 検証済みなら正常経路**として扱う。問題は「成果物保全なしに remove すること」。

### Artifact manifest 不在時の動作

manifest がない場合:

* worktree は残す
* `.orgos-quarantine` を作る
* stderr に `ORGOS_CLEANUP_BLOCKED`
* `.ai/alerts/worktree-cleanup.log` に追記
* wrapper 全体の exit code は、Day 0 では Codex 実行結果を優先してよい

ただし、Manager がこの run を `done` にしてはいけない。Day 1 以降は `cleanup_status != removed_after_manifest && cleanup_status != kept` を state validator で検出する。

### Owner 通知

Day 0 は stderr + repo-local alert log で十分。Slack、メール、daemon、global notification は不要。新しい通知インフラを Day 0 に作るのは過剰。

```text
stderr:
ORGOS_CLEANUP_BLOCKED: worktree preserved/quarantined: task=T-OS-402 path=... reason=artifact_manifest_missing_or_invalid

file:
.ai/alerts/worktree-cleanup.log
```

### Test list (Day 0)

Day 0 の test は 5 個でよい。

1. **default preserve**

   * setup: temp repo + worktree 作成
   * action: wrapper 終了時に `cleanup_worktree` 実行、flag なし
   * expected: worktree directory が残る、`cleanup_status=kept`

2. **manifest なし cleanup 拒否**

   * action: `--cleanup-after-manifest` あり、`--artifact-manifest` なし
   * expected: worktree が残る、`.orgos-quarantine` 作成、stderr に `ORGOS_CLEANUP_BLOCKED`

3. **invalid manifest cleanup 拒否**

   * action: 空 file または invalid JSON を manifest に指定
   * expected: worktree が残る、cleanup blocked

4. **valid minimal manifest cleanup 許可**

   * action: required key を持つ dummy manifest を指定
   * expected: `git worktree remove --force` 成功、worktree directory 消える、`cleanup_status=removed_after_manifest`

5. **existing `--keep-worktree` compatibility**

   * action: 既存 flag `--keep-worktree`
   * expected: worktree が残る。既存利用者を壊さない

## Q17. Artifact manifest 仕様

### JSON Schema

Day 1 の canonical manifest はこれ。長すぎる ontology は避ける。必要十分にする。

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "orgos.artifact_manifest.v1",
  "title": "OrgOS Artifact Manifest",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "schema_version",
    "project_id",
    "task_id",
    "run_id",
    "created_at",
    "repo",
    "actor",
    "execution",
    "artifacts",
    "verification"
  ],
  "properties": {
    "schema_version": {
      "type": "string",
      "const": "orgos.artifact_manifest.v1"
    },
    "project_id": {
      "type": "string",
      "minLength": 1
    },
    "task_id": {
      "type": "string",
      "minLength": 1
    },
    "run_id": {
      "type": "string",
      "pattern": "^[0-9]{8}T[0-9]{6}Z-[A-Za-z0-9._-]+-[a-f0-9]{8}$"
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    },
    "repo": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "repo_root",
        "worktree_path",
        "branch",
        "head_before",
        "head_after"
      ],
      "properties": {
        "repo_root": { "type": "string" },
        "worktree_path": { "type": "string" },
        "branch": { "type": "string" },
        "head_before": { "type": "string" },
        "head_after": { "type": "string" },
        "dirty_after": { "type": "boolean" }
      }
    },
    "actor": {
      "type": "object",
      "additionalProperties": false,
      "required": ["role", "id"],
      "properties": {
        "role": {
          "type": "string",
          "enum": ["manager", "codex", "subagent", "integrator", "owner", "mock"]
        },
        "id": { "type": "string" },
        "model": { "type": "string" },
        "session_id": { "type": "string" }
      }
    },
    "execution": {
      "type": "object",
      "additionalProperties": false,
      "required": ["command_label", "started_at", "ended_at", "exit_code"],
      "properties": {
        "command_label": { "type": "string" },
        "started_at": { "type": "string", "format": "date-time" },
        "ended_at": { "type": "string", "format": "date-time" },
        "exit_code": { "type": "integer" },
        "wrapper_version": { "type": "string" }
      }
    },
    "artifacts": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "id",
          "kind",
          "artifact_path",
          "size_bytes",
          "sha256",
          "required",
          "status"
        ],
        "properties": {
          "id": {
            "type": "string",
            "minLength": 1
          },
          "kind": {
            "type": "string",
            "enum": [
              "stdout",
              "stderr",
              "transcript",
              "output_last_message",
              "git_diff",
              "git_diff_cached",
              "git_status",
              "untracked_file",
              "generated_file",
              "audit_log",
              "handoff_packet",
              "metadata",
              "truncated_log",
              "skipped_large_file",
              "symlink_metadata"
            ]
          },
          "artifact_path": {
            "type": "string",
            "pattern": "^[^/].*"
          },
          "source_path": {
            "type": "string"
          },
          "source_relpath": {
            "type": "string"
          },
          "size_bytes": {
            "type": "integer",
            "minimum": 0
          },
          "sha256": {
            "type": "string",
            "pattern": "^[a-f0-9]{64}$"
          },
          "mode": {
            "type": "string"
          },
          "required": {
            "type": "boolean"
          },
          "status": {
            "type": "string",
            "enum": ["captured", "missing", "skipped", "truncated"]
          },
          "captured_at": {
            "type": "string",
            "format": "date-time"
          },
          "truncation": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "original_size_bytes": { "type": "integer", "minimum": 0 },
              "stored_size_bytes": { "type": "integer", "minimum": 0 },
              "reason": { "type": "string" }
            }
          },
          "symlink": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "target": { "type": "string" },
              "followed": { "type": "boolean" }
            }
          }
        }
      }
    },
    "limits": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "max_log_bytes": { "type": "integer" },
        "max_file_bytes": { "type": "integer" },
        "max_total_bytes": { "type": "integer" }
      }
    },
    "verification": {
      "type": "object",
      "additionalProperties": false,
      "required": ["verified", "verified_at", "errors"],
      "properties": {
        "verified": { "type": "boolean" },
        "verified_at": { "type": "string", "format": "date-time" },
        "errors": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    },
    "cleanup": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "cleanup_allowed": { "type": "boolean" },
        "cleanup_reason": { "type": "string" },
        "cleanup_status": { "type": "string" }
      }
    }
  }
}
```

### Capture strategy

保存対象は以下。

| artifact                     |         必須 | capture 方法                                           |
| ---------------------------- | ---------: | ---------------------------------------------------- |
| stdout                       |         必須 | wrapper stdout を `tee`                               |
| stderr                       |         必須 | wrapper stderr を `tee`                               |
| final message                |         必須 | Codex `--output-last-message` の出力先を artifact dir にする |
| command transcript           |         任意 | stdout/stderr で足りなければ後で追加                            |
| `git status --porcelain=v1`  |         必須 | run 後に保存                                             |
| `git diff --binary`          |         必須 | run 後に保存                                             |
| `git diff --cached --binary` |         必須 | staged がある可能性を潰す                                     |
| untracked files              |         必須 | `git ls-files --others --exclude-standard -z`        |
| generated markdown / Handoff |     必須条件付き | allowed_paths 内にある `.md`, `.yaml`, `.json` など        |
| audit yaml/json              |         必須 | `post-exec-audit.sh` の出力                             |
| verifier result              | Day 1 では任意 | Week 2 以降必須化                                         |

stdout/stderr は `script` command ではなく `tee` で取る。`script` は macOS/Linux で挙動差が大きい。Day 1 には不要。

```bash
artifact_dir="$repo_root/.ai/artifacts/$task_id/$run_id"
mkdir -p "$artifact_dir/logs"

stdout_file="$artifact_dir/logs/stdout.log"
stderr_file="$artifact_dir/logs/stderr.log"
last_msg_file="$artifact_dir/output-last-message.txt"

set +e
codex_cmd=(codex ... --output-last-message "$last_msg_file")

"${codex_cmd[@]}" \
  > >(tee -a "$stdout_file") \
  2> >(tee -a "$stderr_file" >&2)

codex_exit=$?
set -e
```

`tee` によって Manager には streaming が見え続け、同時に artifact に残る。

untracked files:

```bash
mkdir -p "$artifact_dir/files/untracked"

git -C "$worktree_path" ls-files --others --exclude-standard -z |
while IFS= read -r -d '' rel; do
  src="$worktree_path/$rel"
  dst="$artifact_dir/files/untracked/$rel"

  mkdir -p "$(dirname "$dst")"

  if [ -L "$src" ]; then
    # Do not follow symlinks by default.
    target="$(readlink "$src")"
    printf '%s\n' "$target" > "$dst.symlink-target"
  elif [ -f "$src" ]; then
    cp "$src" "$dst"
  fi
done
```

diff:

```bash
git -C "$worktree_path" status --porcelain=v1 > "$artifact_dir/git-status.txt"
git -C "$worktree_path" diff --binary > "$artifact_dir/git-diff.patch"
git -C "$worktree_path" diff --cached --binary > "$artifact_dir/git-diff-cached.patch"
```

sha256 は **file content only**。metadata は manifest に別 field として持つ。symlink は default では追跡しない。symlink target を metadata として保存する。これは secret / outside repo の accidental capture を防ぐため。

run_id は uuidv7 ではなく、Day 1 は portable にする。

```bash
run_ts="$(date -u +%Y%m%dT%H%M%SZ)"
rand="$(uuidgen | tr 'A-F' 'a-f' | cut -c1-8)"
run_id="${run_ts}-${task_id}-${rand}"
```

artifact store:

```text
.ai/artifacts/<task_id>/<run_id>/
  artifact_manifest.json
  artifact_manifest.sha256
  output-last-message.txt
  logs/
    stdout.log
    stderr.log
  git-status.txt
  git-diff.patch
  git-diff-cached.patch
  audit/
    post-exec-audit.yaml
  files/
    untracked/...
    generated/...
```

### Verification algorithm

Day 1 verifier は Python で書く。shell で JSON と sha256 をまともに扱うのはやめる。

```text
verify_artifact_manifest.py MANIFEST

1. JSON parse
2. required top-level fields を確認
3. artifact_path が manifest directory 配下の relative path であることを確認
   - absolute path 禁止
   - ".." 禁止
4. 各 artifact について:
   - status == captured かつ required == true なら存在必須
   - size_bytes と実 file size が一致
   - sha256 が一致
5. required artifact が missing/skipped/truncated なら fail
6. verification.verified が true であることを確認
7. fail したら exit 1
8. pass したら exit 0
```

manifest 自体の sha256 は `artifact_manifest.sha256` に保存する。manifest 内に自分自身の hash を入れると循環するので避ける。

巨大 artifact の扱い:

| 種類                                  | default                                         |
| ----------------------------------- | ----------------------------------------------- |
| stdout/stderr                       | 20MB まで保存。超過時は先頭 10MB + 末尾 10MB、`truncated_log` |
| single file                         | 50MB まで保存。超過時は `skipped_large_file` metadata    |
| total artifact dir                  | 200MB まで                                        |
| binary untracked                    | 50MB 超は skip                                    |
| `node_modules`, `.git`, build cache | 保存対象外                                           |

ただし、required artifact の stdout/stderr は「truncated でも captured」と扱ってよい。巨大 log の完全保存にこだわると Day 1 が壊れる。diff / final message / generated file は required なら完全保存が必要。

### Edge cases

* symlink は追跡しない。
* absolute path を artifact_path に入れない。
* `..` を含む path は manifest verification fail。
* artifact copy 失敗時は cleanup 禁止。
* untracked file が大量にある場合は total limit を超えた時点で skip metadata を残す。
* Codex exit code が non-zero でも artifact capture は実行する。
* Codex が何も出力しなくても stdout/stderr/final message placeholder を作る。

## Q18. Manager tool budget

### Allow / Deny matrix

Week 1 後に Manager が失うべき権限を明確にする。Manager は root ではない。Control-plane dispatcher である。

| tool       | path/subcmd                                                                                                                        |          Week1後 | rationale                                                           |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------- | --------------: | ------------------------------------------------------------------- |
| Bash       | non-git read-only commands                                                                                                         |              許可 | `ls`, `cat`, `grep`, `find`, `python scripts/org/*.py --read` などは必要 |
| Bash       | arbitrary shell                                                                                                                    |            条件付き | 完全 allow は危険。dangerous pattern を deny                               |
| Bash       | `rm -rf`, destructive `find -delete`                                                                                               |              拒否 | Day 1 では雑でも拒否                                                       |
| Bash       | `curl ... \| sh`, `bash <(curl ...)`                                                                                               |              拒否 | supply-chain / remote execution                                     |
| Bash(git)  | `git status`, `git diff`, `git log`, `git show`, `git rev-parse`, `git branch --show-current`, `git ls-files`, `git worktree list` |              許可 | read-only                                                           |
| Bash(git)  | `git fetch`                                                                                                                        |              許可 | working tree を変えない。remote update は許容                                |
| Bash(git)  | `git pull`                                                                                                                         |              拒否 | merge/rebase を伴い working tree を変える                                  |
| Bash(git)  | `git commit`, `git commit --no-verify`                                                                                             |              拒否 | integrator only                                                     |
| Bash(git)  | `git push`                                                                                                                         |              拒否 | Week 1 では integrator/publish path のみ                                |
| Bash(git)  | `git checkout`, `git switch`                                                                                                       |            原則拒否 | wrapper / worktree factory 経由のみ。protected branch は絶対拒否              |
| Bash(git)  | `git reset --hard`                                                                                                                 |              拒否 | destructive                                                         |
| Bash(git)  | `git branch -f`, `git branch -D`                                                                                                   |              拒否 | branch mutation                                                     |
| Bash(git)  | `git merge`, `git rebase`, `git cherry-pick`                                                                                       |              拒否 | integrator path のみ                                                  |
| Bash(git)  | `git stash`                                                                                                                        |            原則拒否 | state を隠す。triage script 経由のみ                                        |
| Bash(git)  | `git worktree add/remove/prune`                                                                                                    |              拒否 | `run-in-worktree.sh` / cleanup script 経由のみ                          |
| Edit/Write | `.ai/EVENTS.jsonl`                                                                                                                 |              拒否 | append-only。`scripts/org/append-event.py` のみ                        |
| Edit/Write | `.ai/TASKS.yaml`                                                                                                                   |              拒否 | legacy read-only。Week 1 で direct mutation を止める                      |
| Edit/Write | `.ai/DASHBOARD.md`                                                                                                                 |              拒否 | generated view                                                      |
| Edit/Write | `.ai/plans/drafts/*.yaml`                                                                                                          |              許可 | draft Plan Contract は Manager が作れる                                  |
| Edit/Write | `.ai/plans/approved/*.yaml`                                                                                                        |              拒否 | approved plan は immutable                                           |
| Edit/Write | `.ai/artifacts/**`                                                                                                                 |            原則拒否 | artifact collector のみ write                                         |
| Edit/Write | `.claude/hooks/**`                                                                                                                 |              拒否 | guardrail self-modification 禁止                                      |
| Edit/Write | `.claude/rules/**`                                                                                                                 |              拒否 | kernel migration task + Owner approval のみ                           |
| Edit/Write | `.claude/agents/**`                                                                                                                |              拒否 | prompt zoo の勝手な変更禁止                                                 |
| Edit/Write | `scripts/codex/**`, `scripts/org/**`                                                                                               |              拒否 | kernel maintenance task + Owner approval のみ                         |
| Read       | any repo path                                                                                                                      |              許可 | planning には read が必要                                                |
| Task       | all 18 subagents                                                                                                                   |            条件付き | Week 1 では削除しないが、write/commit は同じ policy で拘束                         |
| Task       | `org-integrator`                                                                                                                   | 拒否または read-only | integrator agent は security boundary ではない                           |
| Task       | reviewer/planner/scribe 系                                                                                                          |              許可 | ただし tool policy は継承                                                 |

Week 1 で subagent fleet を物理的に 18→5 に削る必要はない。そこまでやると migration が荒れる。だが、**subagent が policy を迂回できる状態は即止める**。Task tool で呼ばれた subagent にも同じ pretool policy を適用する。

### Manager が Week 1 後に失う具体 list

* `git commit`
* `git commit --no-verify`
* `git push`
* `git checkout main`
* `git switch main`
* `git checkout develop`
* `git switch develop`
* `git reset --hard`
* `git branch -f`
* `git worktree remove --force`
* `.ai/EVENTS.jsonl` 直接 Edit/Write
* `.ai/TASKS.yaml` 直接 Edit/Write
* `.ai/DASHBOARD.md` 直接 Edit/Write
* `.claude/hooks/pretool_policy.py` 直接 Edit/Write
* `.claude/rules/*.md` 直接 Edit/Write
* `.claude/agents/*.md` 直接 Edit/Write
* `scripts/codex/run-in-worktree.sh` 直接 Edit/Write
* `scripts/codex/post-exec-audit.sh` 直接 Edit/Write

kernel 開発時だけ例外を作るなら、例外は `Owner approval + kernel maintenance lease + script path` の 3 条件が必要。

### pretool_policy.py 擬似コード

631 行の既存 file に全部を直書きで増やすな。Day 1 で `policy_core.py` に分離するのが理想だが、Day 0/1 は関数分割だけでもよい。

```python
def evaluate_pretool(ctx):
    actor = ctx.actor_role          # manager/codex/subagent/integrator/owner
    tool = ctx.tool_name            # Bash/Edit/Write/Task/...
    cmd = ctx.command or ""
    path = ctx.path or ""
    cwd = ctx.cwd

    if tool == "Bash":
        git = parse_git_command(cmd)
        if git:
            if git.subcmd in {"commit", "push"}:
                return deny("IntegratorOnlyCommit", "raw git commit/push is blocked")

            if git.subcmd in {"reset"} and "--hard" in git.args:
                return deny("ProtectedBranchNoTouch", "git reset --hard is blocked")

            if git.subcmd in {"branch"} and any(a in git.args for a in ["-f", "-D", "-d"]):
                return deny("ProtectedBranchNoTouch", "branch mutation is blocked")

            if git.subcmd in {"checkout", "switch"}:
                target = infer_git_target(git.args)
                if target in {"main", "develop"} or actor != "integrator":
                    return deny("ProtectedBranchNoTouch", "raw checkout/switch is blocked")

            if git.subcmd in {"merge", "rebase", "cherry-pick", "pull"}:
                return deny("IntegratorOnlyCommit", "integration operations require integrator script")

            if git.subcmd == "worktree" and any(a in git.args for a in ["add", "remove", "prune"]):
                return deny("PerTaskWorktree", "worktree mutation requires org wrapper")

            return allow("read-only or permitted git command")

        if looks_destructive_shell(cmd):
            return deny("DangerousShell", "destructive shell command is blocked")

    if tool in {"Edit", "Write"}:
        if is_direct_state_file(path):
            return deny("StateMutationViaOrgTool", "operational state must be changed via org tool")

        if is_kernel_file(path) and not has_kernel_maintenance_lease(ctx):
            return deny("KernelSelfModification", "kernel files require owner-approved maintenance lease")

        if not path_allowed_by_active_lease(ctx):
            return deny("LeaseBeforeWrite", "write outside active lease")

    if tool == "Task":
        if ctx.subagent_name in {"org-integrator"}:
            return deny("IntegratorIsScriptNotAgent", "org-integrator subagent is not allowed in Week 1")
        return allow("subagent allowed; downstream tool calls still checked")

    return allow("default")
```

ここでの大原則は、Manager-specific ではなく **actor-agnostic** にすること。Manager 例外を書くと死ぬ。

## Q19. Kernel regression test suite

### Test harness 前提

本物の Codex API は使わない。Mock で十分。

追加する test harness:

```text
tests/kernel/
  fixtures/
    mock-codex-write-output.sh
    mock-codex-noop.sh
    pretool_git_commit_manager.json
    pretool_git_commit_codex.json
    pretool_edit_events_manager.json
  run-kernel-tests.sh
```

pretool test は Claude Code 本体を起動せず、`pretool_policy.py --test-fixture fixture.json` のように実行できるようにする。なければ Day 1 でこの test mode を足す。

deny の標準:

```text
exit code: 2
stderr contains: ORGOS_POLICY_DENY
```

### Test list

| id      | setup                                                                    | action                                                                  | expected                                                                                 | pass condition                            | time | mock可 |
| ------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------- | ---: | ----- |
| KRT-001 | temp repo。actor=codex fixture                                            | `pretool_policy.py --test-fixture pretool_git_commit_codex.json`        | exit 2, stderr `ORGOS_POLICY_DENY`, reason `IntegratorOnlyCommit`                        | deterministic                             |  <1s | yes   |
| KRT-002 | temp repo。actor=codex                                                    | Bash command `git commit --no-verify -m x` fixture                      | exit 2, `--no-verify` でも deny                                                            | deterministic                             |  <1s | yes   |
| KRT-003 | temp repo。actor=codex                                                    | Bash command `git checkout main` fixture                                | exit 2, reason `ProtectedBranchNoTouch`                                                  | deterministic                             |  <1s | yes   |
| KRT-004 | temp repo + wrapper + mock codex writes `.ai/REVIEW/T/codex-response.md` | `run-in-worktree.sh T --mock-codex --cleanup-after-manifest`            | worktree removed, `.ai/artifacts/T/<run>/artifact_manifest.json` exists, response copied | manifest verify exit 0                    | 3-5s | yes   |
| KRT-005 | actor=manager fixture                                                    | Bash command `git commit -m manager`                                    | exit 2, reason `IntegratorOnlyCommit`                                                    | deterministic                             |  <1s | yes   |
| KRT-006 | actor=manager fixture                                                    | Edit path `.ai/EVENTS.jsonl`                                            | exit 2, reason `StateMutationViaOrgTool`                                                 | deterministic                             |  <1s | yes   |
| KRT-007 | temp repo + queue item + verifier artifact + allowed diff                | `scripts/org/integrator-commit.sh T-KRT-007`                            | exit 0, commit created, queue item moved to done, `CommitIntegrated` event appended      | `git rev-parse HEAD` changed exactly once | 3-5s | yes   |
| KRT-008 | temp repo + lease registry empty                                         | acquire lease A for `src/auth/**`, then lease B for `src/auth/login.py` | second exits 3, stdout/stderr contains `LEASE_CONFLICT`                                  | deterministic                             | 1-2s | yes   |
| KRT-009 | temp repo + worktree                                                     | wrapper with `--cleanup-after-manifest` but no manifest                 | worktree remains, `.orgos-quarantine` exists, stderr `ORGOS_CLEANUP_BLOCKED`             | deterministic                             |   2s | yes   |
| KRT-010 | temp repo + actor=manager                                                | Bash command `git worktree remove --force path`                         | exit 2, reason `PerTaskWorktree`                                                         | deterministic                             |  <1s | yes   |

Mock Codex script:

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p .ai/REVIEW/T-KRT-004
cat > .ai/REVIEW/T-KRT-004/codex-response.md <<'EOF'
# Mock Codex response
This file must survive cleanup.
EOF

echo "mock stdout"
echo "mock stderr" >&2
```

KRT-004 が一番重要。今回の wrapper bug を literal に再現し、修正されたことを証明する。

## Q20. Integrator queue

### Queue location

`integration_queue` は worktree 内に置かない。worktree は消える可能性がある。queue は main repo 側の `.ai/queue/` に置く。

```text
.ai/queue/integration/
  pending/
    <task_id>.json
  processing/
    <task_id>.json
  done/
    YYYYMM/
      <task_id>.<integrated_at>.json
  failed/
  cancelled/
```

### Schema

```json
{
  "schema_version": "orgos.integration_queue.v1",
  "item_id": "IQ-20260514T120000Z-T-AUTH-042-a1b2c3d4",
  "task_id": "T-AUTH-042",
  "project_id": "app-auth",
  "status": "pending",
  "created_at": "2026-05-14T12:00:00Z",
  "created_by": {
    "role": "manager",
    "id": "claude-opus-4.7",
    "session_id": "S-..."
  },
  "priority": 50,
  "dependencies": {
    "tasks": [],
    "queue_items": []
  },
  "worktree": {
    "path": "worktrees/T-AUTH-042",
    "branch": "task/T-AUTH-042-auth-bugfix",
    "base_branch": "main",
    "base_commit": "abc123...",
    "expected_head": "def456..."
  },
  "scope": {
    "allowed_paths": [
      "src/auth/**",
      "tests/auth/**"
    ],
    "prohibited_paths": [
      "db/migrations/**",
      "src/billing/**"
    ],
    "diff_budget": {
      "max_files": 8,
      "max_lines": 300
    }
  },
  "artifacts": {
    "artifact_manifest": ".ai/artifacts/T-AUTH-042/20260514T115900Z-T-AUTH-042-a1b2c3d4/artifact_manifest.json",
    "diff_patch": ".ai/artifacts/T-AUTH-042/20260514T115900Z-T-AUTH-042-a1b2c3d4/git-diff.patch",
    "handoff": ".ai/artifacts/T-AUTH-042/20260514T115900Z-T-AUTH-042-a1b2c3d4/output-last-message.txt"
  },
  "verification": {
    "required": true,
    "status": "passed",
    "commands": [
      "npm test -- auth",
      "npm run typecheck"
    ],
    "artifacts": [
      ".ai/artifacts/T-AUTH-042/20260514T115900Z-T-AUTH-042-a1b2c3d4/verifier.log"
    ],
    "passed_at": "2026-05-14T12:03:00Z"
  },
  "approvals": {
    "plan_id": "P-20260514T110000Z-auth-bugfix-a1b2c3d4",
    "approval_id": "APR-...",
    "approval_hash": "sha256..."
  },
  "commit": {
    "target_branch": "main",
    "message": "fix(auth): handle expired session",
    "author_name": "OrgOS Integrator",
    "author_email": "orgos-integrator@local",
    "trailers": {
      "OrgOS-Task": "T-AUTH-042",
      "OrgOS-Plan": "P-20260514T110000Z-auth-bugfix-a1b2c3d4"
    }
  },
  "attempts": {
    "count": 0,
    "max": 3,
    "last_attempt_at": null,
    "last_error": null
  },
  "retention": {
    "keep_until": "2026-08-14T00:00:00Z"
  }
}
```

### Workflow

1. Manager は queue file を直接書かない。
   `scripts/org/request-integration.sh T-AUTH-042 --plan P-...` を呼ぶ。

2. `request-integration.sh` が検証する。

   * artifact manifest exists
   * verifier passed
   * allowed_paths present
   * branch is task branch
   * no pending duplicate item

3. queue file は atomic write。

   * write to `.tmp`
   * `mv` to `.ai/queue/integration/pending/<task_id>.json`

4. integrator script が consume。

   * `.claude/state/git.lock` を取る
   * pending を priority + created_at 順に読む
   * dependencies 未解決なら skip
   * pending → processing に atomic move
   * 検証
   * commit
   * event append
   * processing → done

5. failed の場合:

   * processing → failed
   * attempts count update
   * Owner alert

### Ordering policy

基本は:

```text
higher priority first
then older created_at first
then task_id lexical
```

依存 task がある場合は dependency resolved まで waiting。task graph dependency は `dependencies.tasks` に明示する。

### 並列 integration 上限

per repo では **1 integrator process**。これは譲らない。parallel integration は事故の温床。

cross-project では project ごとに 1 つまで許容。ただし Week 1〜2 は global でも 1 つでよい。

### Deadlock detection

`queue-doctor.py` を作る。

検出:

* dependency cycle
* pending item が 24h 以上 waiting
* processing item が 30min 以上 stale
* git.lock が 10min 以上取れない
* dependency task が cancelled/done 以外の矛盾状態

cycle は DFS で十分。

### Queue 詰まり通知

Day 1 は `.ai/alerts/integration-queue.log` と stderr。Week 4 以降 dashboard に出す。

```text
ORGOS_QUEUE_STALLED task=T-AUTH-042 age=26h reason=dependency_wait
```

### Retention

* done: 90 日保存
* failed/cancelled: 180 日保存
* event log: 原則永続
* artifact: task done から 90 日、重要 task は manual keep

### Cancel / modify

直接編集禁止。

```bash
scripts/org/cancel-integration.sh T-AUTH-042 --reason "scope changed"
scripts/org/modify-integration.sh T-AUTH-042 --set priority=20
```

実装は単純でよい。

* pending のみ modify/cancel 可
* processing は cancel 不可。stale にしてから failed/cancel
* modify は旧 item を cancelled に移し、新 item を pending に作る

## Q21. Plan Contract

### 正本フォーマット

Canonical は **YAML**。Markdown frontmatter ではない。JSON は機械にはよいが Owner / Manager には読みにくい。Markdown は人間向け表示に良いが canonical には曖昧。

保存先:

```text
.ai/plans/
  pending/
    P-20260514T120000Z-auth-bugfix-a1b2c3d4.yaml
  approved/
  rejected/
  superseded/
  expired/
```

plan_id:

```text
P-<UTC timestamp>-<slug>-<8hex>
例: P-20260514T120000Z-auth-bugfix-a1b2c3d4
```

### Schema

```yaml
schema_version: orgos.plan_contract.v1
plan_id: P-20260514T120000Z-auth-bugfix-a1b2c3d4
project_id: app-auth
status: pending  # draft|pending|approved|rejected|expired|superseded
created_at: "2026-05-14T12:00:00Z"
created_by:
  role: manager
  id: claude-opus-4.7
  session_id: S-...
plan_hash: sha256-of-canonical-plan-without-approval

intent:
  raw: "認証機能の bug を直して"
  summary: "expired session handling の修正"

risk:
  level: normal  # low|normal|high|critical
  reasons:
    - "auth behavior change"
  irreversible: false

tasks:
  - task_id: T-AUTH-042
    title: "Fix expired session handling"
    priority: 50

scope:
  allowed_paths:
    - src/auth/**
    - tests/auth/**
  read_paths:
    - package.json
    - docs/auth/**
  prohibited_paths:
    - db/migrations/**
    - src/billing/**
  prohibited_operations:
    - git_commit_by_worker
    - production_access
    - secret_read
    - db_migration
  diff_budget:
    max_files: 8
    max_lines: 300

worker:
  kind: codex
  count: 1
  worktree_strategy: per_task
  worktree_path: worktrees/T-AUTH-042
  branch: task/T-AUTH-042-auth-bugfix

verifier:
  required: true
  commands:
    - npm test -- auth
    - npm run typecheck
  required_artifacts:
    - stdout
    - stderr
    - git_diff
    - artifact_manifest

integration:
  required: true
  mode: integrator_queue
  target_branch: main
  commit_policy: single_task_commit
  queue_required: true

approvals:
  required: true
  mode: owner_or_standing_policy
  status: pending
  approved_by: null
  approval_id: null
  standing_approval_id: null
  expires_at: "2026-05-15T12:00:00Z"
  typed_phrase_required: null

autonomy:
  eligible: true
  envelope_id: null

dependencies:
  tasks: []

rollback:
  strategy: revert_commit
  notes: "No DB migration; revert should be simple."

owner_options:
  - approve
  - modify
  - reject
```

### Approval UX

Canonical approval route は CLI。slash command は CLI wrapper。chat は convenience であり、Manager が CLI を呼ぶ。

優先順位:

1. `/approve P-...`
2. `scripts/org/approve-plan.sh P-...`
3. chat で `approve P-...` → Manager が CLI 実行
4. file edit は禁止

`approval_status: approved` を Owner が file edit する方式はやめる。state mutation を file edit でやると、また SSOT が割れる。

CLI:

```bash
scripts/org/approve-plan.sh P-20260514T120000Z-auth-bugfix-a1b2c3d4
scripts/org/reject-plan.sh P-... --reason "not now"
scripts/org/modify-plan.sh P-... --add-allowed-path tests/integration/auth/** --note "include integration tests"
```

`modify:` は free text だけにしない。free text は note として受け、Manager が新 plan revision を作る。

modify semantics:

* typed modification:

  * `--add-allowed-path`
  * `--remove-allowed-path`
  * `--set-risk`
  * `--set-priority`
  * `--run-sequentially`
  * `--change-target-branch`
* free text:

  * creates `modification_requested` event
  * Manager creates new plan
  * old plan becomes `superseded`

Approval expiry:

| risk     |           default expiry |
| -------- | -----------------------: |
| low      |                      48h |
| normal   |                      24h |
| high     |                       4h |
| critical | 1h / typed approval only |

一度 approve した plan は immutable。scope を変えるなら re-approve。approval は `plan_hash` に紐づける。plan content が変わったら approval invalid。

Parallel Plan Contract digest:

```text
.ai/plans/digests/DIGEST-20260515-AM.md
```

表示順:

1. critical/high requiring Owner
2. blocked migration/kernel tasks
3. normal pending
4. low auto-approval candidates
5. completed digest

Owner の朝 UX:

```bash
scripts/org/plans-digest.sh --pending --limit 10
scripts/org/approve-plan.sh --batch P-... P-... P-...
```

## Q22. Multi-project deployment

### 配備モデル

推奨は **hybrid**。

* kernel code は `~/.orgos/kernel/<version>/`
* 各 repo には shim / symlink / pinned version
* project state は各 repo の `.ai/`
* global state は `~/.orgos/index.sqlite` と `~/.orgos/projects.yaml`

完全 per-repo copy は version drift がひどくなる。完全 global は project ごとの独立性を壊す。hybrid が現実解。

```text
~/.orgos/
  kernel/
    v0.1.0/
      hooks/
      scripts/
      policy_core.py
    current -> v0.1.0
  index.sqlite
  projects.yaml
  sessions/
  autonomy/
  logs/

<project>/
  .orgos-kernel-version
  .claude/hooks/pretool_policy.py -> ~/.orgos/kernel/v0.1.0/hooks/pretool_policy.py
  scripts/org/... -> ~/.orgos/kernel/v0.1.0/scripts/org/...
  .ai/
    EVENTS.jsonl
    artifacts/
    queue/
    plans/
```

symlink が苦手な repo では copy でもよい。ただし `.orgos-kernel-version` で pin する。

### `.ai/` 構造

`.ai/` は project-local のまま。これは重要。

project-local:

* `.ai/EVENTS.jsonl`
* `.ai/artifacts/`
* `.ai/queue/`
* `.ai/plans/`
* `.ai/TASKS.yaml` legacy
* `.ai/DASHBOARD.md` generated

global:

* project registry
* kernel deployment status
* autonomy envelope
* Manager session tracking
* cross-project dashboard index

共通 audit log は作らない。各 repo の EVENTS が権威。global は index。

### `~/.orgos/` global state の責務

必要最小限:

| global responsibility           |         要否 |
| ------------------------------- | ---------: |
| project registry                |         必須 |
| kernel version registry         |         必須 |
| deployment status               |         必須 |
| session tracking                |         必須 |
| cross-project autonomy envelope |         必須 |
| common audit log                |         不要 |
| cross-project task SSOT         |         不要 |
| global artifact store           | Day 0 では不要 |

### 1 session で複数 project の Plan Contract を扱えるか

扱える。ただし区別する。

* portfolio planning: 1 session で複数 project を見てよい
* execution: 原則 1 active project context ずつ
* integration: per repo で 1 integrator

Manager が複数 project の Plan Contract を作るのはよい。しかし Bash / Edit / Write の実行時には `project_id` と `repo_root` を明示し、pretool が context mismatch を拒否するべき。

### Kernel version co-existence

必ず co-exist 期間を許す。

```text
project A: kernel v0.1.0 Day0 only
project B: kernel v0.1.1 No Worker Commit
project C: kernel legacy warn-mode
```

Plan Contract / integration queue には `min_kernel_version` を入れる。古い project で新機能を使おうとしたら拒否。

### project 登録 UX

```bash
scripts/org/register-project.sh \
  --id ecology-sales \
  --name "Ecology Sales Platform" \
  --repo "/Users/youyokotani/Dev/Private/NE/03.Ecology-SalesPlatform" \
  --default-branch main \
  --kernel-version v0.1.0 \
  --install-hooks \
  --mode warn
```

登録時にやること:

1. repo path exists
2. git repo であることを確認
3. `.ai/` 作成
4. `.orgos-kernel-version` 書き込み
5. hook shim install
6. global index update
7. initial `ProjectRegistered` event append

### `~/.orgos/index.sqlite` schema 要点

```sql
CREATE TABLE projects (
  project_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  repo_path TEXT NOT NULL,
  default_branch TEXT NOT NULL,
  kernel_version TEXT NOT NULL,
  status TEXT NOT NULL,
  registered_at TEXT NOT NULL,
  last_seen_at TEXT
);

CREATE TABLE deployments (
  project_id TEXT NOT NULL,
  kernel_version TEXT NOT NULL,
  mode TEXT NOT NULL, -- warn/enforce/canary/disabled
  installed_at TEXT NOT NULL,
  installed_by TEXT,
  PRIMARY KEY(project_id, kernel_version)
);

CREATE TABLE sessions (
  session_id TEXT PRIMARY KEY,
  manager_id TEXT,
  project_id TEXT,
  repo_path TEXT,
  started_at TEXT NOT NULL,
  last_seen_at TEXT,
  status TEXT NOT NULL
);

CREATE TABLE autonomy_envelopes (
  envelope_id TEXT PRIMARY KEY,
  scope_json TEXT NOT NULL,
  status TEXT NOT NULL,
  valid_from TEXT NOT NULL,
  valid_until TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE project_event_index (
  project_id TEXT NOT NULL,
  event_seq INTEGER,
  event_id TEXT,
  ts TEXT NOT NULL,
  type TEXT NOT NULL,
  task_id TEXT,
  summary TEXT,
  indexed_at TEXT NOT NULL,
  PRIMARY KEY(project_id, event_id)
);
```

### 配備順序

既存 10+ project にいきなり enforce しない。

現実的な rollout:

#### Stage 0: OrgOS-Dev only

* Day 0 patch
* artifact preservation
* cleanup fail-closed
* KRT-001〜KRT-010

#### Stage 1: 1 low-risk project canary

* Day 0 cleanup preservation
* No Worker Commit enforce
* No Shared Worktree warning

#### Stage 2: all projects — cleanup preservation only

* destructive cleanup を止める
* worktree が残る副作用は許容
* これは事故を減らすだけなので広く配れる

#### Stage 3: all projects — No Worker Commit enforce

* AI direct commit は全 project で禁止
* ここは早く広げる

#### Stage 4: project-by-project — No Shared Worktree enforce

* running task triage 済み project から enforce
* 未 triage project は warning

#### Stage 5: Plan Contract / event projection

* canary project から
* 失敗しても old `.ai/TASKS.yaml` が読める状態を維持

切実な点への答え: **Week 0.5 ship を全 project に強制するなら、cleanup preservation だけにする**。これは作業を止めるより、worktree が残って disk を使う方向の副作用なので安全。worktree enforcement は project-by-project。

## Q23. STOP-WHEN signal

### Build 開始可否

**build 開始可能。5th round は不要。**

ここまでで ship blocker は潰れている。Q16〜Q19 は Day 0/1 の実装仕様として十分。Q20〜Q22 は Week 2 以降の仕様として十分。これ以上の design round は、かなり高い確率で procrastination になる。

### 必要な 5th round

現時点では **なし**。

5th round が必要になる条件は、設計質問ではなく実装中の失敗に限定する。

あり得る trigger:

1. `pretool_policy.py` の Claude Code hook 入出力形式が想定と違い、test harness が作れない。
2. `run-in-worktree.sh` の Codex invocation が stdout/stderr capture と相性悪く、exit code が壊れる。
3. symlink/copy 型 multi-project deployment が既存 `/org-publish` と衝突し、rollout が止まる。

この 3 つが起きたら、5th round ではなく **実装ログと失敗 diff を持って targeted review** をするべき。抽象議論を続けるべきではない。

### あなたの率直判定

これ以上の設計は procrastination 寄り。

理由:

* root cause はもう特定済み。
* invariant は決まっている。
* Manager 身分も決まっている。
* Week 0 / Week 1 の ship 順も決まった。
* Day 0 patch の具体実装も決まった。
* test suite も決まった。

残っているリスクは、設計で潰すものではなく build で発見するもの。

直近のリスクは 3 つだけ。

1. **hook false positive で作業が止まる**
   対策: warn/enforce mode を分ける。ただし raw commit deny は維持。

2. **artifact collector が一部 output を拾い漏らす**
   対策: KRT-004 と artifact survival metric。漏れたら worktree cleanup しない。

3. **multi-project rollout で version drift が起きる**
   対策: canary + `.orgos-kernel-version` + global index。

### 重大な見落としが発覚した場合

build に入った後で見落としが発覚したら、設計 round に戻るのではなく、以下の順で止める。

1. affected project の kernel mode を `warn` に下げる
   ただし `No Worker Commit` は enforce 維持。

2. worktree cleanup を全面 preserve に戻す。

3. failing test を KRT に追加する。

4. patch を当てる。

5. 必要なら targeted 5th review を行う。
   ただし議題は 1 個だけにする。

「後出し 5th round」は OK。ただし、build 前の一般設計 round としてではなく、失敗事例に対する incident review として行うべき。

### コスト比較

1st / follow-up / 3rd / 4th の設計コストはすでに十分大きい。Owner の時間、Manager の時間、token、認知負荷を考えると、これ以上の抽象設計は収穫逓減が強い。

一方で、Week 0 Day 0 patch は小さい。`cleanup_worktree()` を fail-closed にするだけで、今回の literal な成果物消失事故は止まる。build 開始遅延のコストの方が、追加設計の期待利益を上回っている。

したがって判定は明確。

```text
STOP DESIGN.
START BUILD.
```

## Summary

4th round で必要な最後の仕様は出揃った。Day 0 は artifact manifest の完全実装ではなく、manifest なし cleanup を止める fail-closed patch から始めるべき。Day 1 に manifest / capture / verification、Day 5 に KRT regression を入れれば、前 3 round の原則は実装可能になる。Q23 の判定は **5th round 不要、build 開始可能**。次の一手は **OrgOS-Dev で `cleanup_worktree()` を fail-closed に変更し、KRT-009 まで通すこと**。
