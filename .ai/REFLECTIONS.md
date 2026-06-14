# Reflection Loop — 振り返り・知見統合

> Owner の指示・修正、私（Manager）の間違い、全体思想を **散逸させず、OrgOS の振る舞いに還元する** ための1入口ループ。
> 設計の詳細は [.ai/DESIGN/OBSERVABILITY_LEARNING_V2.md](DESIGN/OBSERVABILITY_LEARNING_V2.md)（課題 #4）を参照。

---

## ループ: 捕捉 → 分類 → 昇格

```
反省の発生（Owner修正 / 私の誤り / 思想）
   ↓  捕捉（capture）
REFLECTIONS 台帳 (.ai/REFLECTIONS.jsonl) に1件記録   ← すべての反省はまずここに落ちる（1入口）
   ↓  分類（classify）— どの恒久ホームへ還元するか
   ↓  昇格（promote）— 該当ホームへ反映し status=integrated にする
次セッションで bootstrap が integrated な反省を踏まえて行動
```

- **捕捉 (capture)**: 反省を 1 件、台帳に記録する。`status=open`、`category=unclassified` で始まってよい。
- **分類 (classify)**: 4 カテゴリのどれかに振り分ける（下表）。
- **昇格 (promote)**: 恒久ホームへ反映し、`--set-status integrated --integrated-into <path>` で台帳を更新する。

---

## 4 カテゴリと昇格先（promotion homes）

| category | 意味 | 昇格先（恒久ホーム） | Owner 確認 |
|---|---|---|---|
| `behavioral` | 振る舞いの癖（例:「選択肢で聞くな」） | `USER_PROFILE` feedback memory | 自動昇格可 |
| `systemic` | ルール/手順の穴 | 該当 rule / skill を更新（or 新設） | 必要（rule 級は Owner 確認） |
| `philosophical` | 全体思想（CLAUDE.md / AGENTS.md 級） | OIP 化 → Owner 承認 → CLAUDE/AGENTS | **必須** |
| `one_off` | その場限り | 記録のみ（昇格しない） | 不要 |
| `unclassified` | 未分類（既定） | — （分類待ち） | — |

> **昇格ポリシー（Owner 確定 2026-06-14）**: philosophical / rule 級の昇格は **Owner 確認必須**。
> behavioral の memory 昇格は自動適用してよい。`authority-layer.md` 準拠で、私が勝手に思想を書き換えない。

---

## 台帳 (.ai/REFLECTIONS.jsonl)

`.ai/REFLECTIONS.jsonl` は **raw ログ**（1 行 1 JSON）。`.ai/_machine/`（gitignore のランタイム状態）ではなく
`.ai` 直下に置く human-facing かつ per-repo の恒久知見である。直接編集せず、必ず org-tool 経由で更新する。

### スキーマ

```json
{
  "id": "REF-YYYYMMDD-NNN",
  "ts": "<UTC ISO8601>",
  "trigger": "owner_correction | self_error | principle",
  "text": "<反省の本文>",
  "category": "behavioral | systemic | philosophical | one_off | unclassified",
  "status": "open | integrated | discarded",
  "integrated_into": "<昇格先のパス。integrated 時のみ>",
  "notes": ""
}
```

### org-tool（正規書込パス）

捕捉（append）:

```bash
python3 scripts/org/append-reflection.py \
  --text "選択肢で聞くな。自律的に判断して実行し結果を報告する。" \
  --trigger owner_correction --category behavioral --note "owner feedback"
```

昇格 / 分類更新（update）:

```bash
python3 scripts/org/append-reflection.py --id REF-20260614-001 \
  --set-status integrated --integrated-into "USER_PROFILE feedback memory"

python3 scripts/org/append-reflection.py --id REF-20260614-002 \
  --set-category systemic --set-status discarded --note "重複のため破棄"
```

- `--trigger`: `owner_correction`（Owner の指示・修正）/ `self_error`（私の誤り）/ `principle`（全体思想）
- enum は厳格検証（不正値は非ゼロ終了・書込なし）。id は当日内で自動採番（冪等）。
- 捕捉時は中央 activity 台帳（`orgos-activity.v1`）へ best-effort で `thought` イベントをミラーする（失敗は無視）。

---

## 関連

- 設計: [.ai/DESIGN/OBSERVABILITY_LEARNING_V2.md](DESIGN/OBSERVABILITY_LEARNING_V2.md)（課題 #4 / T-OS-505）
- 正規書込パス: [.claude/rules/kernel-write-path.md](../.claude/rules/kernel-write-path.md)
- 既存の受け皿: `USER_PROFILE` feedback memory / `DECISIONS.md` / evolution engine（Reflection Loop は Owner との対話から学ぶ補完関係）
