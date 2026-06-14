---
description: Owner の修正・自分の誤り・思想を「反省」として記録し、適切な恒久ホームへ還元する
---

# /org-reflect - 振り返り・知見統合ループ

Owner の指示・修正、自分の間違い、全体思想を散逸させず、OrgOS の振る舞いに還元する。
すべての反省はまず **REFLECTIONS 台帳に 1 件落ち**、そこから正しい恒久ホームへ振り分ける。

設計書: [.ai/DESIGN/OBSERVABILITY_LEARNING_V2.md](../../.ai/DESIGN/OBSERVABILITY_LEARNING_V2.md)（課題 #4）

---

## 使い方

```
/org-reflect "<反省/学びの内容>" [--trigger owner_correction|self_error|principle]
```

`--trigger`: `owner_correction`（Owner の修正） / `self_error`（自分の誤り） / `principle`（全体思想）。省略時は内容から推定。

---

## Manager の動作

### (a) 台帳に記録

```bash
python3 scripts/org/append-reflection.py --text "<反省の内容>" --trigger owner_correction
```

`status=open` / `category=unclassified` で `.ai/REFLECTIONS.jsonl` に追記され、`id`（例: `REF-20260614-001`）が返る。

### (b) 分類する（reasoning を添えて、なぜそう分類したかを 1 行で示す）

### (c) 昇格する（下表のポリシーに従う）— 完了後に台帳を更新

```bash
python3 scripts/org/append-reflection.py --id REF-20260614-001 \
  --set-category behavioral --integrated-into memory --set-status integrated
```

- **behavioral → memory（自動可）**: feedback memory を 1 件書き、`integrated_into=memory` / `status=integrated`。
- **systemic → rule/skill（rule 変更は Owner 確定）**: 編集案を提示 → 承認後に適用 → `integrated`。
- **philosophical → OIP + Owner 承認（必須）**: OIP（`.ai/OIP/OIP-NNN-*.md`）を起票。承認・反映まで `open`、反映後 `integrated`。
- **one_off → 記録のみ**: `--set-category one_off`。昇格しない。

---

## 分類の指針

| category | 何か（例） | 還元先（恒久ホーム） | Owner 確定 |
|---|---|---|---|
| `behavioral` | 振る舞いの癖（「選択肢で聞くな、自律実行しろ」） | USER_PROFILE feedback memory | 不要（自動可） |
| `systemic` | 手順/スクリプトの穴（「gitignore で junk を拾った」） | 該当 rule / skill を更新（or 新設） | rule 変更は必須 |
| `philosophical` | OS 全体の思想（「人間用/機械用を分離」） | OIP 化 → 反映 | **必須** |
| `one_off` | その場限り（「この PoC は捨てる前提」） | 記録のみ | 不要 |

---

## エスカレーションポリシー（authority-layer 準拠）

> Owner 確定（2026-06-14）: philosophical / rule 級の昇格は **Owner 確定必須**。behavioral の memory 昇格は **自動適用可**。

| 昇格先 | 権限 |
|---|---|
| memory（behavioral） | **自動可** — Manager が feedback memory を書いて即 integrated |
| rule / skill（systemic） | **Owner 確定必須** — 編集案を提示し承認後に適用 |
| CLAUDE/AGENTS 級 思想（philosophical） | **Owner 確定必須** — OIP 化して承認（kernel ファイルは承認なしに触らない） |

私が勝手に思想・ルールを書き換えてはいけない。kernel/思想級は必ず Owner を通す。

---

## bootstrap 連携

セッション起動時、`scripts/session/bootstrap.sh` が `.ai/REFLECTIONS.jsonl` から `status=integrated`、または
`status=open` かつ behavioral/philosophical の反省を最大 5 件「## Reflections（踏まえるべき反省）」に注入する。過去の反省を毎回踏まえて行動する。

---

## 注意事項

- secret（APIキー等）を反省本文に書かない。
- 反省は必ず台帳に落としてから昇格する（散逸防止の 1 入口）。既存 memory / rule と重複しないか確認。
