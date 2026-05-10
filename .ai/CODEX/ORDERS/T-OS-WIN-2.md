# Work Order: T-OS-WIN-2 (Issue #4 Phase β)

## Task
- ID: T-OS-WIN-2
- Title: agent-coordination.md の Codex 起動規約をプラットフォーム分岐対応
- Role: implementer
- Priority: P1

## Allowed Paths
- `.claude/rules/agent-coordination.md` (編集)
- `.claude/agents/CODEX_WORKER_GUIDE.md` (編集)
- `.ai/CODEX/RESULTS/T-OS-WIN-2.md`

## Reference
- Issue #4: https://github.com/Yokotani-Dev/openOrgOS/issues/4
- T-OS-WIN-1 成果物: scripts/platform/detect.sh (macos / linux / windows-wsl / windows-native 判定)

## Dependencies
- T-OS-WIN-1: done

## Context

現在 agent-coordination.md と CODEX_WORKER_GUIDE.md は Mac 前提 (`/opt/homebrew/bin/codex`) で記述されている。
T-OS-WIN-1 で実装した detect.sh の判定結果に基づき、プラットフォーム別の起動方式を Iron Law として明文化する。

## Acceptance Criteria

### A1: agent-coordination.md にプラットフォーム分岐セクション追加
既存の Codex 起動規約セクションを拡張:

```markdown
## Codex CLI 起動規約 (プラットフォーム分岐)

CONTROL.yaml の `platform` 値に従って起動方式を選択する (Iron Law):

### macos
```bash
/opt/homebrew/bin/codex exec --full-auto --skip-git-repo-check ...
```

### linux
```bash
codex exec --full-auto --skip-git-repo-check ...
# (PATH 解決に任せる)
```

### windows-wsl (推奨)
```bash
bash .ai/CODEX/codex-wsl.sh exec --full-auto ...
# 内部で wsl -d Ubuntu -- bash -c '...' に変換
# 詳細は T-OS-WIN-3 で実装される wrapper を参照
```

### windows-native (非推奨)
```
[!] WSL の導入を強く推奨します。
    workspace-write sandbox が動作せず、read-only fallback のみとなります。
    OpenAI codex#15850, #17179, #18821 参照。
```
```

### A2: CONTROL.yaml の platform 値で自動選択するロジック規約化
agent-coordination.md に明記:
- Manager は Codex 起動前に CONTROL.yaml の platform を確認
- platform 未設定 → detect.sh を呼び出して判定 + 記録
- platform 別の起動コマンド template を Manager の Tick フローで使用

### A3: CODEX_WORKER_GUIDE.md にトラブルシューティング追加
プラットフォーム別の典型問題:

```markdown
## プラットフォーム別トラブルシューティング

### Windows-native で sandbox が動作しない
- 症状: `workspace-write` が `read-only` にフォールバック
- 原因: OpenAI codex#15850 / #17179 / #18821 (2026-04 時点未解決)
- 対応: WSL Ubuntu に移行、CONTROL.yaml の platform を windows-wsl に変更

### Windows-WSL で auth.json が見つからない
- 症状: `codex auth: not signed in`
- 対応: Windows 側 ~/.codex/auth.json を WSL に同期 (T-OS-WIN-3 wrapper が自動化)

### Linux で codex CLI が見つからない
- 症状: `command not found: codex`
- 対応: npm i -g @openai/codex (Node 22+)
```

### A4: 既存 Mac 例の保持
agent-coordination.md の既存 Mac 用サンプルコマンド (例:
`/opt/homebrew/bin/codex exec --full-auto ...`) は壊さない。
プラットフォーム別セクションの一例として位置付け直す。

### A5: 検証
- agent-coordination.md が dead link なし
- CODEX_WORKER_GUIDE.md がエージェント定義 frontmatter として valid
- Manager Quality Eval 退行なし

### A6: T-OS-WIN-3 への示唆
agent-coordination.md と CODEX_WORKER_GUIDE.md の windows-wsl セクションで、
具体的な codex-wsl.sh 仕様の要件を明記:
- 引数転送、パス変換、auth.json 同期、ShellCheck パス

## Instructions

1. T-OS-WIN-1 の detect.sh 出力 enum を前提に作業
2. agent-coordination.md は既存構造を尊重して **追加** 中心
3. CODEX_WORKER_GUIDE.md は既存トラブルシューティングセクションがあれば追記、なければ新規セクション
4. **重要**: `.ai/DECISIONS.md`, `.ai/TASKS.yaml`, CLAUDE.md, manager.md 編集禁止

## Report

`.ai/CODEX/RESULTS/T-OS-WIN-2.md`:
1. 変更ファイル一覧
2. A1-A6 対応表
3. プラットフォーム別起動コマンド一覧
4. T-OS-WIN-3 への要件
5. ステータス: DONE / DONE_WITH_CONCERNS / BLOCKED

## Handoff Packet (必須)
schema 準拠。
