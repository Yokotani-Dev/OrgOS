# Work Order: T-INT-010

## Task
- ID: T-INT-010
- Title: Intelligence 品質修正: 重複排除の強化
- Role: implementer

## Repository
orgos-intelligence (/Users/youyokotani/Dev/Private/orgos-intelligence)

## Problem Analysis

`src/collector/index.ts` の重複排除が不十分で、同一ニュースが複数ソースから重複して表示される。

### 具体例:
GPT-5.3-Codex-Spark が以下3件で重複:
1. OpenAI Blog (Tier 1): "Introducing GPT-5.3-Codex-Spark"
2. Simon Willison (Tier 3): "Introducing GPT‑5.3‑Codex‑Spark"
3. Hacker News (Tier 2): "GPT‑5.3‑Codex‑Spark"

### 問題箇所:

1. **URL 完全一致のみ** (collector/index.ts:74): 同じ記事でもソースによって URL が異なる
   - `https://openai.com/index/introducing-gpt-5-3-codex-spark/` (直接)
   - `https://simonwillison.net/2026/Feb/12/codex-spark/#atom-everything` (ブログ引用)
   - `https://openai.com/index/introducing-gpt-5-3-codex-spark/` (HN リンク先)

2. **タイトル類似度の閾値が厳しすぎ** (collector/index.ts:78-81): bigram Jaccard 係数 > 0.7
   - 正規化後でも言い回しの違いで 0.7 未満になりうる
   - 文字レベルの bigram は英語タイトルで語順変更に弱い

3. **normalizeTitle が不十分** (collector/index.ts:107-113):
   - 基本的な正規化（小文字化、特殊文字除去）はしているが、接頭辞("introducing" 等)の除去がない

### 修正内容:

1. **URL 正規化を追加**:
   - クエリパラメータ除去（`utm_*`, `ref`, `source` 等のトラッキングパラメータ）
   - `www.` 除去
   - 末尾スラッシュの統一
   - フラグメント（`#...`）の除去

2. **タイトル類似度の改善**:
   - **単語レベル Jaccard 係数に変更**（文字 bigram → 単語ベース）
   - 閾値を 0.5 に引き下げ（0.7 → 0.5）
   - ストップワード除去（"a", "the", "an", "introducing", "new", "how" 等）

3. **ソース URL の同一記事検出**:
   - HN/ブログ記事が元記事の URL を含む場合（sourceUrl が同じドメイン+パス）、重複として扱う

4. **Tier 優先度の尊重**:
   - 同一記事が複数ソースにある場合、Tier が高い方を残す（Tier 1 > Tier 2 > Tier 3）
   - 現行の実装は先に処理されたソースが残る → Tier 順に処理されていれば OK だが、明示的に Tier 優先のロジックに変更

## Acceptance Criteria
- 同一ニュースが複数ソースから重複して表示されない
- URL 正規化（utm 除去、www 除去、末尾スラッシュ統一）が実装されている
- タイトル類似度の閾値が調整されている（0.7→0.5 or 単語レベル Jaccard）
- TypeScript ビルド通過

## Files to Modify
- src/collector/index.ts (重複排除ロジックの強化)

## Reference
- 設計書: OrgOS リポジトリの .ai/DESIGN/ORGOS_INTELLIGENCE.md Section 4
