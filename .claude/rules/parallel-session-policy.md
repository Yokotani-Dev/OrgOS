# Parallel Session Policy — Iron Law

> 共有 `.git` への並行アクセスは想定外のブランチ切り替え + 想定外コミットを生む。
> 1 リポジトリで動作可能な並行 Claude Code セッションは 1 つまで。Codex CLI 並列実行時は別 worktree 必須。例外なし。

## Purpose

Owner Issue (2026-05-10):
> 9 プロセス (Claude セッション 4 + Codex 4 + resume 1) が同じ `.git` を共有していた。
> reflog で 3 回の意図しないブランチ切替を確認。`main` ブランチへの誤コミットも発生。

git は単一作業者前提のツール。`HEAD` の状態は 1 つしか持てない。複数プロセスが同じワーキングディレクトリで git 操作を行うと、最後の git 操作の結果のブランチに全プロセスが影響を受ける。

OrgOS の `.claude/settings.json` は `additionalDirectories: [".worktrees"]` を宣言しており **設計は worktree 並列を想定**しているが、実運用では worktree が活用されていなかった。本 rule でこのギャップを埋める。

## Iron Law

1. **1 リポジトリで動作可能な並行 Claude Code セッションは 1 つまで**。複数セッションが必要なら別 worktree で起動する。
2. Codex CLI 並列実行時は、各 Codex を **別 worktree で起動**する。同一 working directory での並列起動禁止。
3. Manager は git 操作 (`git checkout`, `git commit`, `git merge`, `git rebase`, `git stash`) を実行する前に **必ず現在ブランチを確認**する。
4. **意図しないブランチ切り替えを検出**したら、即座に作業を停止し Owner に報告する。reflog で復旧可能でも自動修復は行わない。
5. Owner が明示的に許可した場合のみ並行運用可。許可は `.ai/CONTROL.yaml` の `allow_parallel_sessions: true` で記録する。
6. `git commit` 実行直前は必ず `git branch --show-current` で expected_branch との一致を確認する。

## Required Behavior

### セッション開始時

Manager は以下を `.claude/state/session-<sessionId>.yaml` に記録:

```yaml
session_id: <sessionId>
started_at: <ISO8601>
expected_branch: <branch_name>  # git branch --show-current の結果
worktree_path: <abs_path>       # 現在 worktree
```

### git 操作前

以下を `git` コマンド実行前に必ず確認:

1. `git branch --show-current` で現在ブランチを取得
2. `expected_branch` と比較
3. 一致しなければ **即座に停止し Owner 報告**
4. lock file (`.claude/state/git.lock`) の存在確認 (T-OS-363 で実装)

### Codex 起動時

`bash scripts/codex/run-in-worktree.sh <TASK_ID>` (T-OS-362 で実装) を経由する。直接 `codex exec` を呼ばない。

暫定: T-OS-362 実装前は **Codex 並列実行を 1 つに制限**する (sequential 実行)。

## Detection Rules

### 並行セッション検出

```bash
ps aux | grep -c "claude --output-format" | tr -d ' '
```

結果 > 1 の場合、並行セッション運用中。Iron Law 違反候補。

### Codex 並列検出

```bash
ps aux | grep -c "codex exec" | tr -d ' '
```

結果 > 1 かつ各プロセスの `cwd` が同じなら **Iron Law 違反**。

### 意図しないブランチ切り替え検出

```bash
# expected と current が異なる
[ "$(cat .claude/state/expected_branch)" != "$(git branch --show-current)" ]
```

## Red Flags

以下を検出したら即座に停止:

- 複数の Claude Code セッションが同一 `.git` を共有している
- 複数の Codex CLI が同一 working directory で起動している
- `git branch --show-current` の結果が `expected_branch` と異なる
- `git reflog` に Owner が指示していない `checkout` エントリが存在する
- `.claude/state/git.lock` が他セッションによって保持されている (T-OS-363 後)
- worktree なしで Codex CLI を background 並列起動しようとしている

## Violation Response

- 並行運用検出 → Owner に「並行セッション運用中です」と報告。続行可否を確認
- 意図しないブランチ切り替え検出 → 即座に作業停止、reflog 提示、`git branch -f` での復旧手順を Owner に提示
- 複数 Codex 同時起動 → 1 つに絞る or worktree で分離

## Migration Path

| Phase | 状態 |
|---|---|
| **Phase 0 (現在)** | 本 rule で運用ガード。Codex 並列は sequential に降格 |
| **Phase 1 (T-OS-361)** | pretool_policy.py にブランチ整合性チェック追加 |
| **Phase 2 (T-OS-362)** | Codex 起動を worktree wrapper 経由に強制 |
| **Phase 3 (T-OS-363)** | git 協調ロック導入 (flock) |
| **Phase 4 (T-OS-364)** | アーキテクチャ再設計 (Manager は git 禁止、git-coordinator 集約) |

## Relationship To Other Rules

- `.claude/rules/agent-coordination.md`: 並列実行 (allowed_paths 衝突) の延長として、git ブランチ衝突も扱う
- `.claude/rules/authority-layer.md`: git mutation は high risk + irreversible に分類
- `.claude/rules/rationalization-prevention.md`: Iron Law 違反として扱う
- `.claude/agents/CODEX_WORKER_GUIDE.md`: Codex 起動規約 (T-OS-362 で更新)

## Related Incident

2026-05-09 の reflog:

```
9cca46a HEAD@{2026-05-09 01:02:11}: merge origin/develop  (Owner not requested)
9cca46a HEAD@{2026-05-09 01:02:02}: checkout: feature/fit-restart-04 -> main  (Owner not requested)
```

Manager セッション内で **3 回**ブランチが意図せず切り替わり、`main` ブランチに想定外コミットが乗る寸前で発見。`git branch -f` で reflog から手動復旧。
