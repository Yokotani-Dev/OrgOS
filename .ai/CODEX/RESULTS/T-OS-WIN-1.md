# T-OS-WIN-1 Result

## 1. 変更ファイル一覧

- `scripts/platform/detect.sh`
- `.claude/commands/org-start.md`
- `.claude/commands/org-import.md`
- `.ai/CONTROL.example.yaml`
- `.ai/CODEX/RESULTS/T-OS-WIN-1.md`

## 2. A1-A8 対応表

| AC | 対応 |
|----|------|
| A1 | `scripts/platform/detect.sh` を追加。`uname` / `$OSTYPE` / Windows 環境変数 / WSL 環境変数で `macos` / `linux` / `windows-msys` / `windows-wsl` / `windows-native` を出力。Windows 系では `wsl --status` または `wsl.exe --status` を確認。 |
| A2 | `/org-start` のフローB Step B-0 と新規初期化後 Step 3-1 に platform 記録手順を追加。Windows 系では `OWNER_INBOX` へ WSL 案内を追記。 |
| A3 | `/org-import` の事前検出、`scripts/platform/detect.sh` コピー手順、`.ai/CONTROL.yaml` 作成後の platform 記録手順を追加。 |
| A4 | `.ai/CONTROL.example.yaml` を追加し、`platform` フィールドと enum コメントを追加。 |
| A5 | `platform` が既に設定済みの場合は上書きせず stderr 警告のみ。`--force` で上書き可能。一時 CONTROL で 2 回実行し diff なしを確認。 |
| A6 | Windows 検出時の WSL 推奨セットアップ文を stderr と OWNER_INBOX 追記に実装。 |
| A7 | macOS で `macos` 出力を確認。MSYS/Git Bash 分岐は `uname` / `wsl` のスタブで `windows-msys` 出力、stderr 案内、OWNER_INBOX 追記を確認。WSL 実機確認はこの環境では未実施。冪等性は一時 CONTROL で確認。 |
| A8 | `.ai/AUDIT/platform-YYYY-MM-DD.log` へ検出結果を追記。`.ai/AUDIT/` は既存 `.gitignore` 済み。 |

## 3. detect.sh 実行サンプル

実行コマンド:

```bash
scripts/platform/detect.sh --no-write
```

出力:

```text
macos
```

冪等性確認:

```text
first=macos second=macos
platform: "macos"
```

2 回目は以下の警告のみで、CONTROL の diff はなし:

```text
detect.sh: platform already set to 'macos'; not overwriting (use --force to replace)
```

Windows/MSYS 分岐のスタブ確認:

```text
stdout=windows-msys
platform: "windows-msys"
WSL status: available
```

## 4. T-OS-WIN-2 への示唆

- Codex 起動規約側では `platform` が `windows-msys` または `windows-native` の場合、Manager が通常の `codex exec --full-auto` を直接呼ばず、WSL ラッパーへ誘導する分岐が必要。
- `windows-wsl` は直接実行可能扱いにできるが、作業ディレクトリが `/mnt/c/...` の場合はパス・権限・改行の注意を表示した方がよい。
- `OWNER_INBOX` に追記する案内と T-OS-WIN-3 の `codex-wsl.sh` が同じ手順を指すよう、文言を揃える必要がある。

## 5. ステータス

completed

## Handoff Packet

```json
{
  "task_id": "T-OS-WIN-1",
  "status": "completed",
  "summary": "プラットフォーム検出スクリプトを追加し、/org-start と /org-import に CONTROL.yaml platform 記録手順を組み込みました。",
  "files_changed": [
    "scripts/platform/detect.sh",
    ".claude/commands/org-start.md",
    ".claude/commands/org-import.md",
    ".ai/CONTROL.example.yaml",
    ".ai/CODEX/RESULTS/T-OS-WIN-1.md"
  ],
  "tests_run": true,
  "tests_passed": true,
  "commits": [],
  "blockers": [],
  "notes": "WSL 実機検証はこの macOS 環境では未実施。MSYS/Git Bash 分岐はスタブで確認済み。実体の .ai/CONTROL.yaml は編集していません。"
}
```
