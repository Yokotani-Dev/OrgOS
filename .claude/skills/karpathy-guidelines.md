---
name: karpathy-guidelines
description: コードを書く・レビューする・リファクタするときに使う。過剰実装・暗黙の仮定・不要な変更を防ぎ、変更を最小限かつ検証可能にする実装者向けの行動規範。
---

# Karpathy Guidelines（実装者向け行動規範）

> 出典: [Andrej Karpathy の LLM coding pitfalls](https://x.com/karpathy/status/2015883857489522876) /
> [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)（MIT）。
> OrgOS の実装者（Codex worker / 実装系 subagent）が、Work Order を実装するときに従う 4 原則。

**トレードオフ**: この規範は「速さ」より「慎重さ」に寄せている。typo 修正や自明な 1 行など些末な作業では judgment で省略してよい。OrgOS の MVP→確認→拡張サイクルと矛盾しない（投機的拡張を MVP に混ぜない、という意味で補強する）。

---

## 1. Think Before Coding（書く前に考える）

**仮定で進めない。混乱を隠さない。トレードオフを表に出す。**

実装に入る前に:

- 仮定は明示する。不確かなら聞く。
- 解釈が複数あるなら、黙って 1 つ選ばず提示する。
- もっと単純な方法があるなら、そう言う。妥当なら push back する。
- 不明点があれば止まる。何が不明かを名指しして聞く。

**OrgOS 連携**: ここで出した仮定・未解決点は `handoff_packet` の `assumptions` / `unresolved_questions` に必ず残す（[handoff-protocol.md](../rules/handoff-protocol.md)）。Owner への問い合わせ要否は Manager 側の [request-intake-loop.md](../rules/request-intake-loop.md) Step 6 / [authority-layer.md](../rules/authority-layer.md) が判定するため、実装者は「仮定を可視化して返す」までを担う。

## 2. Simplicity First（まず単純に）

**問題を解く最小のコード。投機的なものは書かない。**

- 依頼されていない機能は足さない。
- 単発利用のコードに抽象化を入れない。
- 求められていない「柔軟性」「設定可能性」を作らない。
- 起こり得ないシナリオへの error handling を書かない。
- 200 行書いて 50 行で済むなら、書き直す。

問いかけ: **「シニアエンジニアはこれを過剰だと言うか？」** Yes なら単純化する。

**OrgOS 連携**: [coding-standards.md](coding-standards.md) の KISS / YAGNI / DRY を運用レベルに落としたもの。「どこまで作るか」のスコープ境界は Quality Contract（`scope_boundary.out_of_scope`）が定める。本原則はその境界 *内側* での過剰設計を止める。

## 3. Surgical Changes（外科的な変更）

**触るべき所だけ触る。自分が出した散らかりだけ片付ける。**

既存コードを編集するとき:

- 隣接するコード・コメント・整形を「改善」しない。
- 壊れていないものをリファクタしない。
- 自分なら別の書き方でも、既存スタイルに合わせる。
- 無関係な dead code に気づいても、消さず指摘するに留める。

自分の変更が orphan を生んだとき:

- 自分の変更で未使用になった import / 変数 / 関数は消す。
- 元からあった dead code は、依頼されない限り消さない。

判定基準: **変更した全行が、依頼に直接辿れること。**

**OrgOS 連携**: `allowed_paths` は「どのファイルを触ってよいか」のファイル境界を定める。本原則はその *行レベル* の規律で、許可ファイル内でも依頼に無関係な変更を禁じる。

## 4. Goal-Driven Execution（ゴール駆動の実行）

**成功条件を定義する。検証されるまでループする。**

命令を検証可能なゴールに変換する:

- 「バリデーション追加」→「不正入力のテストを書き、通す」
- 「バグ修正」→「再現テストを書き、通す」
- 「X をリファクタ」→「前後でテストが通ることを確認」

複数ステップのタスクでは、短い plan を宣言する:

```
1. [手順] → verify: [確認方法]
2. [手順] → verify: [確認方法]
3. [手順] → verify: [確認方法]
```

強い成功条件があれば自律的にループできる。弱い条件（「動くようにして」）は確認の往復を増やす。

**OrgOS 連携**: 既に Work Order の Acceptance Criteria と [tdd-workflow.md](tdd-workflow.md) が担う領域。本原則は実装者がそれを「検証可能なゴール + verify 手順」として実行に移すための言い換え。検証結果は `handoff_packet.verification` に残す。

---

## 効いているサイン

- diff に不要な変更が出ない（依頼した変更だけが現れる）
- 過剰実装による書き直しが減る
- 確認質問が「実装の後」ではなく「実装の前」に来る
- レビューが小さく最小限になる（ついで refactor がない）
