---
task_id: T-OS-WIN-2
status: DONE_WITH_CONCERNS
handoff_packet:
  schema_version: "1.0"
  task_id: T-OS-WIN-2
  agent: codex-implementer
  status: DONE_WITH_CONCERNS
  completed_at: "2026-05-01T01:38:00+09:00"
  trace:
    request_trace_id: T-OS-WIN-2
    span_id: codex-worker-20260501-0138
    attempt: 1
    parent_span_id: null
    resume_of: null
  changed_files:
    - path: .claude/rules/agent-coordination.md
      summary: Codex CLI 起動規約を CONTROL.yaml の platform 値に基づく分岐規約へ拡張
    - path: .claude/agents/CODEX_WORKER_GUIDE.md
      summary: プラットフォーム別トラブルシューティングと T-OS-WIN-3 wrapper 要件を追加
    - path: .ai/CODEX/RESULTS/T-OS-WIN-2.md
      summary: 実装結果、検証結果、handoff packet を記録
  assumptions:
    - statement: T-OS-WIN-1 の detect.sh enum を正とし、windows-msys も platform 分岐に含める
      confidence: 0.95
      source: file:scripts/platform/detect.sh
  decisions_made:
    - decision: windows-msys は windows-wsl wrapper 経由へ誘導する
      rationale: T-OS-WIN-1 の成果物が windows-msys を enum として出力し、Windows native 直接起動と同様に sandbox とパス解決の不安定さが想定されるため
      alternatives_considered:
        - windows-msys を windows-native と同じ非推奨文だけに含める
        - windows-msys を linux と同じ PATH 解決に任せる
    - decision: T-OS-WIN-3 wrapper の要件を両ドキュメントに明記する
      rationale: Manager 起動規約と Worker トラブルシューティングの双方から同じ wrapper 仕様へ到達できるようにするため
      alternatives_considered:
        - agent-coordination.md のみに記載する
  unresolved_questions:
    - question: Manager Quality Eval は現状 18/20 pass で critical_failure=true のため、既存 baseline と比較した正式な退行判定を Manager 側で確認する必要がある
      blocker: false
      suggested_owner: next_agent
  downstream_impacts:
    - target_task: T-OS-WIN-3
      impact_type: spec_update
      description: codex-wsl.sh は引数転送、Windows/WSL パス変換、auth.json 同期、ShellCheck 検証を満たす必要がある
  memory_updates: []
  verification:
    tests_run:
      - bash .claude/evals/check-refs.sh
      - bash .claude/evals/check-agent-defs.sh
      - python3 .claude/evals/manager-quality/report.py run --repo-root "$PWD" --output-dir /tmp/orgos-mq-T-OS-WIN-2 --json
      - scripts/platform/detect.sh --no-write
    eval_results:
      check_refs: pass
      check_agent_defs: pass
      platform_detect_stdout: macos
      manager_quality:
        exit_code: 1
        cases: 20
        passed: 18
        failed: 2
        critical_failure: true
        note: repo 外の /tmp 出力で実行。既存 suite が非ゼロ終了のため concern として引き継ぎ。
    self_check: 許可された3ファイルのみを編集し、禁止された共有台帳・CLAUDE.md・manager.md・secrets は編集していない
---

# Result: T-OS-WIN-2

## 1. 変更ファイル一覧

- `.claude/rules/agent-coordination.md`
- `.claude/agents/CODEX_WORKER_GUIDE.md`
- `.ai/CODEX/RESULTS/T-OS-WIN-2.md`

## 2. A1-A6 対応表

| AC | 対応 |
|----|------|
| A1 | `agent-coordination.md` の Codex 起動規約を `Codex CLI 起動規約 (プラットフォーム分岐)` に拡張し、`macos` / `linux` / `windows-wsl` / `windows-msys` / `windows-native` の起動方式を明記。 |
| A2 | Manager が起動前に `.ai/CONTROL.yaml` の `platform` を確認し、未設定時は `scripts/platform/detect.sh` で判定・記録してから platform 別 template を使う規約を追加。 |
| A3 | `CODEX_WORKER_GUIDE.md` に `プラットフォーム別トラブルシューティング` を追加し、Windows native sandbox、WSL auth.json、Linux CLI 未導入、Windows-MSYS の典型問題を記載。 |
| A4 | 既存の `/opt/homebrew/bin/codex exec --full-auto ...` Mac 例を保持し、`macos` 分岐の標準例として位置付け直した。 |
| A5 | `bash .claude/evals/check-refs.sh` は pass、`bash .claude/evals/check-agent-defs.sh` は pass。Manager Quality Eval は `/tmp` 出力で実行し、現状 `18/20 pass` / `critical_failure=true` のため concern として記録。 |
| A6 | `windows-wsl` と `Windows-WSL auth.json` セクションに T-OS-WIN-3 の `codex-wsl.sh` 要件として、引数転送、パス変換、auth.json 同期、`shellcheck .ai/CODEX/codex-wsl.sh` を明記。 |

## 3. プラットフォーム別起動コマンド一覧

### macos

```bash
/opt/homebrew/bin/codex exec --full-auto --skip-git-repo-check \
  --output-last-message .ai/CODEX/RESULTS/<TASK_ID>.txt \
  - < .ai/CODEX/ORDERS/<TASK_ID>.md
```

### linux

```bash
codex exec --full-auto --skip-git-repo-check \
  --output-last-message .ai/CODEX/RESULTS/<TASK_ID>.txt \
  - < .ai/CODEX/ORDERS/<TASK_ID>.md
```

### windows-wsl / windows-msys

```bash
bash .ai/CODEX/codex-wsl.sh exec --full-auto --skip-git-repo-check \
  --output-last-message .ai/CODEX/RESULTS/<TASK_ID>.txt \
  - < .ai/CODEX/ORDERS/<TASK_ID>.md
```

### windows-native

```text
非推奨。WSL Ubuntu へ移行し、platform を windows-wsl に変更してから Codex worker を起動する。
```

## 4. T-OS-WIN-3 への要件

- `.ai/CODEX/codex-wsl.sh` は `exec --full-auto ...` 以降の引数を欠落・再解釈せず WSL 側へ転送する。
- Windows パスと WSL パスを変換し、Work Order、結果ファイル、作業ディレクトリの参照を壊さない。
- Windows 側 `~/.codex/auth.json` を WSL 側 `~/.codex/auth.json` に同期する。
- `shellcheck .ai/CODEX/codex-wsl.sh` を検証対象に含める。

## 5. 検証

- `bash .claude/evals/check-refs.sh` → pass (`All 63 references valid.`)
- `bash .claude/evals/check-agent-defs.sh` → pass (`All 14 agent definitions valid.`)
- `scripts/platform/detect.sh --no-write` → `macos`
- `python3 .claude/evals/manager-quality/report.py run --repo-root "$PWD" --output-dir /tmp/orgos-mq-T-OS-WIN-2 --json` → `18/20 pass`, `critical_failure=true`, exit 1

## 6. ステータス

DONE_WITH_CONCERNS

Concern: Manager Quality Eval は現状の repository 状態で非ゼロ終了する。今回の静的検証と文書変更は通過済みだが、正式な「退行なし」判定は Manager 側で既存 baseline と比較してください。
