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
### Implementer (Codex)
- OK: create/switch branch, edit code, run tests, commit
- NG: commit on main, merge to main, **push（全面禁止）**

### Reviewer (Codex)
- OK: read-only review, run tests if needed
- NG: edits (principle), merges, **push（全面禁止）**

### Integrator/Release (Claude)
- OK: resolve conflicts, rebase/merge, final tests, merge to main, tag/release
- Responsibility: merge order control, release decision
- Push は Owner 承認後のみ

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

---

## Git Hooks Setup (Codex Push事故防止)

Codex は Claude Code hooks の外で動作するため、git native hooks で push を防止する。

### 初回セットアップ（必須）

リポジトリをクローンした後、以下を実行：

```bash
git config core.hooksPath .githooks
```

これにより `.githooks/` 内のフックが有効になる。

### 含まれるフック

#### `.githooks/pre-push`
- `allow_push=false` の場合、すべての push をブロック
- `allow_push_main=false` の場合、main/master への push をブロック
- `.ai/CONTROL.yaml` のフラグを参照して判定

### 確認方法

```bash
# 現在の hooks パスを確認
git config --get core.hooksPath

# .githooks になっていればOK
```

### トラブルシューティング

**Q: push がブロックされた**
A: `.ai/CONTROL.yaml` の `allow_push` / `allow_push_main` を確認。
   Owner 承認後に Integrator が `true` に変更する。

**Q: hooks が効かない**
A: `git config core.hooksPath .githooks` を再実行。

**Q: CI/CD で hooks を無効にしたい**
A: CI 環境では `git config core.hooksPath ""` を設定するか、
   `--no-verify` オプションを使用（ただし慎重に）。
