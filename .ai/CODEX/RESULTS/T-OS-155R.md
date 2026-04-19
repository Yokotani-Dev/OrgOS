# T-OS-155R Review Report

## 総合判定
- × (差し戻し)

## 観点別評価
### R1: schema 妥当性
- 判定: ×
- 確認内容:
  - `handoff_packet` 配下で必須フィールド群、主要 enum、入れ子構造自体は定義されている（`.claude/schemas/handoff-packet.yaml:14-214`）。
  - `status` / `operation` / `impact_type` / `target` の列挙値は Acceptance Criteria の範囲を満たしている（`.claude/schemas/handoff-packet.yaml:40-47`, `.claude/schemas/handoff-packet.yaml:151-157`, `.claude/schemas/handoff-packet.yaml:173-186`）。
- 問題点:
  - actual YAML parse が失敗する。`ruby -e 'require "yaml"; YAML.load_file(".claude/schemas/handoff-packet.yaml")'` で `mapping values are not allowed in this context at line 39 column 34` が出る。少なくとも `note:` 値に未クォートの `:` を含む箇所があり、schema として利用不能（`.claude/schemas/handoff-packet.yaml:39`, `.claude/schemas/handoff-packet.yaml:92`）。
  - required / optional の境界は top-level では見えるが、`content: any` と `scope: string` が極端に緩く、機械適用前提の `memory_updates` としては必須制約が不足している（`.claude/schemas/handoff-packet.yaml:161-193`）。

### R2: Iron Law 厳格性
- 判定: △
- 確認内容:
  - protocol 冒頭で「完了時に必ず返却、例外なし」と明示し、欠損時は `NEEDS_CONTEXT` 扱いとする流れも書かれている（`.claude/rules/handoff-protocol.md:3`, `.claude/rules/handoff-protocol.md:11-28`, `.claude/rules/handoff-protocol.md:50-57`）。
  - violation 条件として `status` enum 外、`trace_id` 欠損、`memory_updates.scope` 未登録を列挙している（`.claude/rules/handoff-protocol.md:107-119`, `.claude/schemas/handoff-packet.yaml:215-220`）。
- 問題点:
  - 「Red Flag が具体的か」という観点では弱い。`assumptions` が空でも暗黙仮定があれば不備、など人手判断に依存する規則はあるが、機械可読な違反条件へ落ちていない（`.claude/rules/handoff-protocol.md:121-126`）。
  - Iron Law 違反時の Manager 動作も「再送要求」「問題として記録」までで、どこにどう記録し、次段をどう停止するかの deterministic な状態遷移が不足している（`.claude/rules/handoff-protocol.md:52-57`, `.claude/rules/handoff-protocol.md:116-119`）。

### R3: Request Intake Loop との統合
- 判定: △
- 確認内容:
  - Step 9 の 6 ステップ統合案は protocol 側に明記されている（`.claude/rules/handoff-protocol.md:72-87`）。
  - `request-intake-loop.md` 側も Step 9 で「Handoff Packet 受信時は memory_updates を反映する」「T-OS-155 で実装する前提」と接続している（`.claude/rules/request-intake-loop.md:306-321`）。
- 問題点:
  - `memory_updates -> USER_PROFILE / CAPABILITIES / DECISIONS` の反映ロジックは宛先名レベルで止まっており、payload の shape 検証、重複時の merge ルール、失敗時の quarantine がない。Manager が安全に機械適用する仕様としては不足（`.claude/rules/handoff-protocol.md:76-85`, `.claude/schemas/handoff-packet.yaml:187-193`）。
  - `downstream_impacts` を `TASKS.yaml` に反映すると書く一方、どのフィールドへどう反映するかが未定義で、Step 9 の「更新手順」としては抽象度が高い（`.claude/rules/handoff-protocol.md:83-85`）。

### R4: trace_id 伝播
- 判定: △
- 確認内容:
  - 発行主体、Work Order への伝播、packet での返却、グルーピング用途は明示されている（`.claude/rules/handoff-protocol.md:89-96`）。
  - Step 7/8/9 をつなぐ監査キーとしての役割も整理されている（`.claude/rules/handoff-protocol.md:87`, `.claude/rules/request-intake-loop.md:246-274`）。
- 問題点:
  - `UUID または semantic ID (T-OS-XXX-<timestamp>)` を許可するだけで、一意性条件、timestamp 粒度、clock skew、再実行時の扱いが未定義。並列タスクや retry で collision / 誤グルーピングが起こり得る（`.claude/rules/handoff-protocol.md:91-96`）。
  - request-level trace と packet-level identity が分かれていない。OpenAI Agents SDK / LangGraph 的な span / run / attempt 区別がなく、durable retry 時の再現性が弱い。

### R5: 後方互換
- 判定: △
- 確認内容:
  - 既存 `.ai/CODEX/RESULTS/*.md` が非構造化 Markdown であることを認識し、新形式として frontmatter と fenced YAML block の 2 形式を定義している（`.claude/rules/handoff-protocol.md:98-105`）。
- 問題点:
  - 「既存 Result Markdown 形式との互換保証」には届いていない。現行非構造 Markdown をどう解釈するかではなく、新しい packet 埋め込み形式を 2 つ許可しているだけで、移行期間中に packet 非搭載の既存結果を Manager がどう扱うかが未定義（`.claude/rules/handoff-protocol.md:98-105`）。
  - self-report では「Parser は両形式をサポート」とあるが、独立事実としては parser 方針の粒度が足りず、後方互換の運用条件までは確認できない（`.ai/CODEX/RESULTS/T-OS-155.md:15-37`）。

### R6: 未解決リスク
- 判定: ×
- 確認内容:
  - 3 回連続 retry、`memory_updates.scope` 未登録 violation、`trace_id` 欠損 violation、自発参照期間の存在など、論点自体には触れている（`.claude/rules/handoff-protocol.md:50-57`, `.claude/rules/handoff-protocol.md:107-119`, `.claude/rules/handoff-protocol.md:128-137`）。
- 問題点:
  - 3 回 retry の設計妥当性がない。backoff、human escalation、部分 packet salvage、同一欠陥の連続時に何を止めるかが定義されていない（`.claude/rules/handoff-protocol.md:52-57`, `.claude/rules/handoff-protocol.md:118-119`）。
  - `memory_updates` の `content:any` と `scope:string` を Manager が機械適用する前提は破壊的リスクが高い。誤 scope / 誤 payload を受けた際の reject-only ルールがない（`.claude/schemas/handoff-packet.yaml:161-193`, `.claude/rules/handoff-protocol.md:78-82`）。
  - schema evolution 耐性が弱い。ファイル見出しに `v1.0` はあるが `schema_version` フィールド、unknown field policy、v1/v2 coexistence rule がない（`.claude/schemas/handoff-packet.yaml:1`, `.claude/rules/handoff-protocol.md:98-105`）。

### R7: T-OS-155b への示唆
- 判定: △
- 確認内容:
  - retrofit 対象ファイル群は列挙されている（`.claude/rules/handoff-protocol.md:128-137`）。
  - self-report にも `manager.md` / subagent 定義 / `CODEX_WORKER_GUIDE.md` へどう広げるかの方向性はある（`.ai/CODEX/RESULTS/T-OS-155.md:38-43`）。
- 問題点:
  - 「既存 agent retrofit の具体手順」は不足。各 agent prompt に何を追記し、未返却時にどう fail-fast させ、reviewer/implementer の既存結果フォーマットとどう両立させるかが書かれていない（`.claude/rules/handoff-protocol.md:128-137`）。
  - Manager parser 実装方針も「frontmatter / fenced YAML の両対応」に留まり、抽出順序、frontmatter 優先順位、複数 packet 混在時の扱いが未定義。

### R8: OpenAI Agents SDK / LangGraph 互換性
- 判定: △
- 確認内容:
  - `trace_id` を基軸に tracing を残す設計思想自体は、OpenAI Agents SDK の tracing や LangGraph の durable execution を参照した方向として妥当（`.ai/CODEX/ORDERS/T-OS-155.md:31-33`, `.claude/rules/handoff-protocol.md:89-96`）。
- 問題点:
  - 粒度は単一 `trace_id` に寄りすぎており、span / handoff / retry attempt / state resume の区別がない。比較対象 framework に寄せるなら `trace_id` だけでは不十分。
  - durable execution への移行経路も未記述。resume 時に同一 trace を継続するのか、新 attempt を切るのか、packet の idempotency をどう担保するのかが抜けている。

## 発見した問題 (重要度別)
### CRITICAL
- なし

### HIGH
- `.claude/schemas/handoff-packet.yaml:39` - schema が YAML として parse できない。実測で `YAML.load_file` が失敗し、handoff packet schema の SSOT として使えない - `note:` 値など `:` を含む文字列をクォートし、CI で parse test を追加する。
- `.claude/schemas/handoff-packet.yaml:161-193` と `.claude/rules/handoff-protocol.md:76-85` - `memory_updates` を機械適用すると言いながら `content:any` / `scope:string` しかなく、宛先別 payload 制約・reject 条件・quarantine 動作がない。誤 packet で shared memory/decision ledger を壊し得る - target ごとの payload schema、scope registry、apply 前 validation failure 時の discard/quarantine ルールを定義する。

### MEDIUM
- `.claude/rules/handoff-protocol.md:91-96` - `trace_id` が UUID または `T-OS-XXX-<timestamp>` としか決まっておらず、並列起動・retry・resume 時の collision / 誤グルーピング条件が残る - request trace と packet/run/attempt ID を分離する。
- `.claude/rules/handoff-protocol.md:98-105` - 後方互換の説明が「新形式 2 種を許可」に留まり、packet 非搭載の既存 Markdown 結果を移行期間にどう扱うかがない - `legacy_result` fallback と migration sunset ルールを追加する。
- `.claude/rules/handoff-protocol.md:52-57` と `.claude/rules/handoff-protocol.md:118-119` - 3 回 retry は定義されているが、再送の停止条件、owner escalation、部分 salvage、backoff がなく設計が浅い - retry policy を状態遷移として明文化する。
- `.claude/rules/handoff-protocol.md:128-137` - T-OS-155b への示唆は対象ファイル列挙に留まり、agent retrofit と parser 実装の具体手順が不足 - 各 agent への追加文言、失敗時挙動、parser 抽出優先順位を設計メモとして分離する。
- `.claude/rules/handoff-protocol.md:121-126` - review / audit expectations の一部は人手判断依存で、機械可読な violation detection としては弱い - empty array 許容条件や evidence 必須条件を schema/lint へ落とす。

### LOW
- `.claude/schemas/handoff-packet.yaml:1` - 文書見出しに `v1.0` はあるが packet 自体に `schema_version` がなく、v1/v2 共存の移行がしづらい - packet field として `schema_version` を追加する。
- `.claude/rules/handoff-protocol.md:89-96` - tracing の設計思想はあるが OpenAI Agents SDK / LangGraph にある span tree や durable resume との対応表がない - 将来の execution metadata 拡張ポイントを追記する。

## 実装者自己報告との照合
- 一致:
  - A2, A3, A4, A7 は文書上は概ね実装されている。
  - protocol に Iron Law、Step 9 統合節、trace_id 節、T-OS-155b 節が存在する点は自己報告どおり。
- 不一致:
  - A1 の「schema 定義」は存在するが、actual YAML parse に失敗するため「利用可能な schema」とは評価できない。
  - A5 の「後方互換要件」は文言上あるが、既存 Markdown 結果の移行運用が未定義なため「保証済み」とは言えない。
  - A6 の「違反検出」は列挙されているが、R2 観点でみると機械可読性は不十分。

## 検証内容
- 読了:
  - `.claude/rules/handoff-protocol.md`
  - `.claude/schemas/handoff-packet.yaml`
  - `.claude/rules/request-intake-loop.md`
  - `.ai/CODEX/ORDERS/T-OS-155.md`
  - `.ai/CODEX/RESULTS/T-OS-155.md`
- 実施テスト:
  - `ruby -e 'require "yaml"; YAML.load_file(".claude/schemas/handoff-packet.yaml")'`
  - 結果: `Psych::SyntaxError: mapping values are not allowed in this context at line 39 column 34`

## ステータス
- CHANGES_REQUESTED
