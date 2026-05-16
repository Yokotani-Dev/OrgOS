# Codex Work Order — OrgOS 理想形批評 (T-OS-402)

> 宛先: codex-implementer (gpt-5.5, reasoning=high)
> 起動: `bash scripts/codex/run-in-worktree.sh T-OS-402`
> 出力: `.ai/REVIEW/T-OS-400/codex-response.md` (Handoff Packet 付き)
> 編集禁止: 本ドキュメント以外の OS ファイル

---

## Task Brief

OrgOS は Claude Code 上で動く「自律エージェント運営 OS」である。
Owner FB により、「問題が発生するたびに暫定対応が続いて理想形に近づいていない」状態を脱したい。

あなた (Codex) には、**実装エンジニアリングの視点から、OrgOS の現状を批評し、理想形を独立に提案**してほしい。
Manager (Claude) の視点とは独立に書くこと。Manager 視点 (`.ai/REVIEW/T-OS-400/manager-vision.md`) は意図的に提示しない。後で SYNTHESIS で突き合わせる。

---

## 読むべき入力ファイル

最低限以下を読み、必要に応じて grep で探索する。Manager 視点ドキュメントは**読まないこと** (bias を避けるため)。

### 構造把握 (必読)
- `CLAUDE.md` — OrgOS の自己紹介
- `AGENTS.md` — OS 保護ルール
- `.claude/rules/` — 30+ 個の rule ファイル一覧 (中身は要約で良いが、Iron Law と書かれているものは本文確認)
- `.claude/hooks/pretool_policy.py` — runtime enforcement の唯一の本格実装
- `.claude/agents/manager.md` — Manager 仕様
- `.claude/agents/CODEX_WORKER_GUIDE.md` — Codex 規約

### 状態ファイル (必読、構造のみ把握)
- `.ai/CONTROL.yaml`
- `.ai/TASKS.yaml` (先頭 100 行 + tail 50 行)
- `.ai/GOALS.yaml`
- `.ai/USER_PROFILE.yaml` (もし存在すれば、無ければ skip)
- `.ai/CAPABILITIES.yaml`
- `.ai/DECISIONS.md` (最新 5 PLAN-UPDATE のみ)

### scripts (実装の実態)
- `scripts/` 配下を `find` でツリー化
- 主要 script の役割を 1 行ずつ要約

### 直近事故 (背景理解)
- `.ai/DECISIONS.md` から PLAN-UPDATE-022 (本日追加) を読む
- 事故の概要は: 2026-05-10 に 並列 Claude Code セッション + 並列 Codex により main / develop 両方に add/add 衝突 7 ファイル発生、cherry-pick で回避

---

## 提出物: `.ai/REVIEW/T-OS-400/codex-response.md`

### 必須セクション

#### 1. Inventory (現状の機械的計測)
- `.claude/rules/` のファイル数 / 総行数
- Iron Law を宣言している rule の数
- runtime check が存在する rule の数 (pretool_policy.py / scripts/* で実装されているもの)
- TASKS.yaml の task 数 (status 別)
- TASKS_ARCHIVE.yaml の task 数
- DECISIONS.md の PLAN-UPDATE 数
- scripts/ の shell script 数 / 総行数
- 直近 30 日のコミット数

#### 2. Code-Level 構造的負債の指摘
実装エンジニアの視点で、以下を具体的に挙げる:
- **重複/類似コード**: 同じことを違う場所でやっている script 等
- **dead code**: 参照されていない rule / script / agent prompt
- **schema drift**: TASKS.yaml と GOALS.yaml と DECISIONS.md の整合性が崩れている箇所
- **rule vs runtime gap**: 「やってはいけない」と markdown で書かれているが runtime で止められない事象 (具体例を挙げる)
- **error handling の poverty**: script の `set -euo pipefail` 漏れ、Python の例外処理漏れ、等
- **テスト不在**: rule / script / agent のうち自動テストが存在しないものの割合

各指摘は **ファイルパス + 行番号 + 該当コードスニペット** を付ける。"ぼんやり指摘" は禁止。

#### 3. Pattern 分析 — patch-on-patch の機械的兆候
- 同一ファイル (例: `pretool_policy.py`) に何回 amendment が入ったか (git log)
- TASKS.yaml の "follow-up" "fix" "patch" "v2" を含む task の比率
- rule ファイルのうち「複数 issue を経て生まれた」ものの比率
- SELFREVIEW-001 → 002 → 002b 等の連鎖の長さ

#### 4. 代替アーキテクチャ提案 (Codex 独自視点)
以下のいずれか、または複合で:
- A. **event sourcing**: 状態を log + projection で表現
- B. **typed core**: YAML を typed schema (JSON Schema / Protobuf / Pydantic) に置換
- C. **micro-kernel**: kernel と userspace の物理分離
- D. **policy engine**: rule を OPA / Cedar のような policy 言語で表現
- E. **state machine**: phase 遷移を FSM として実装
- F. **その他**: Codex が知る別パターン

各案について:
- 実装難度 (S/M/L) と工数見積もり (日 or 週)
- 既存資産の流用度 (%)
- 期待される改善効果 (定量、定性)
- リスクと反対意見

#### 5. 「Manager の責務を削るとしたら何を削るか」
Codex の視点で、Manager が現状やっていることのうち
- (a) 機械化できるもの
- (b) LLM 判断が必要だが構造化できるもの
- (c) 真に Manager の柔軟判断が必要なもの
の 3 分類で列挙。

#### 6. 直接的反対意見
Manager 視点に縛られず、以下のいずれかを **正直に**:
- 「OrgOS は overengineered。半分は捨てて単純な script + checklist に戻すべき」
- 「現状の構成は妥当。問題は実装品質であって設計ではない」
- 「Owner の運用負荷が高すぎる。OrgOS を使うこと自体が患者」
- 「LLM Manager の限界。状態管理は外部 DB に出すべき」
- 等

**Manager や Owner に忖度しないこと**。あなたは社外の review engineer の立場で書く。

#### 7. 短期 / 中期 / 長期 アクション提案
Codex 視点で、優先順に最大 10 件のアクションを提案。各アクションに:
- 目的
- 実装方針 (具体的に)
- 工数
- 期待効果

---

## Output Format

```markdown
# Codex 視点: OrgOS 理想形批評 (T-OS-402)

## 1. Inventory
(machine-counted facts)

## 2. Code-Level 構造的負債
(specific findings with file:line)

## 3. Patch-on-patch の機械的兆候
(git-log-based evidence)

## 4. 代替アーキテクチャ提案
### A. event sourcing
...
### B. typed core
...
(or chosen subset)

## 5. Manager 責務分解
| 責務 | 分類 (a/b/c) | 機械化案 |
|...|...|...|

## 6. 直接的反対意見
(honest critique, may contradict Manager assumptions)

## 7. アクション提案 (優先順)
1. ...
2. ...

## Handoff Packet
(per .claude/schemas/handoff-packet.yaml)
```

---

## Iron Law (Codex 向け)

1. 本タスクでは **コード変更を一切行わない**。`.ai/REVIEW/T-OS-400/codex-response.md` のみ作成。
2. Manager 視点ドキュメント (`manager-vision.md`) は読まないこと (bias 回避)。
3. `git add` / `git commit` / `git push` 禁止 (T-OS-391 先取り)。
4. 自己報告ではなく、ファイルパスと行番号で証拠を残す。
5. 「忖度せず」「実装エンジニアの視点で」書く。Manager の判断を覆す提案も歓迎。

---

## Handoff Packet 要求

完了報告には:
- `status: DONE` または `DONE_WITH_CONCERNS`
- `changed_files: [.ai/REVIEW/T-OS-400/codex-response.md]`
- `verification.self_check`: 上記 7 セクション全てを埋めたか / 証拠 (file:line) を 20 件以上提示したか
- `assumptions`: 解釈が分かれそうな箇所をすべて明記
- `unresolved_questions`: 確信が持てない論点
