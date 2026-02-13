# Work Order: T-INT-007

## Task
- ID: T-INT-007
- Title: Intelligence 品質修正: Gemini API スコアリング復旧 + OIP 生成修正
- Role: implementer

## Repository
orgos-intelligence (/Users/youyokotani/Dev/Private/orgos-intelligence)

## Problem Analysis

### Problem 1: Gemini API スコアリングが全件 medium/要調査にフォールバック

`src/analyzer/filter.ts:116-126` の catch ブロックで、Gemini API エラー時に全記事を medium/要調査 に設定している。
本日のレポート（2026-02-13）で全22トピックが medium / orgosImpact: "要調査" になっていることから、Gemini API 呼び出しが毎回失敗していると推定。

**原因候補:**
1. Gemini API の JSON レスポンスのパースが失敗している（`filter.ts:97-104` で `JSON.parse(jsonStr)` が例外）
   - Gemini がマークダウンコードブロック以外の形式で返す場合、`replace(/```json?\n?/g, "")` では除去しきれない
2. バッチサイズ10件が大きすぎて、出力が truncate されて不完全な JSON になる
3. `evaluations.find((e) => e.id === article.id)` の id マッピングが一致しない

**修正内容:**
1. `scoreBatch` の JSON パーサーをロバスト化:
   - レスポンスから JSON 配列を抽出するロジックを強化（`[` と `]` の間を抽出）
   - パース前に余分なテキスト・マークダウン記法を除去
2. バッチ失敗時のリトライ戦略:
   - バッチ全体が失敗したら、1件ずつリトライするフォールバック
   - 最終フォールバックは medium（現行と同じ）だが、ログにエラー詳細を出力
3. エラーログの改善:
   - catch ブロックで `error` の種類（API エラー / JSON パースエラー / マッピングエラー）を区別してログ出力
4. バッチサイズを 10 → 5 に下げる（レスポンス安定性向上）

### Problem 2: OIP 生成が0件

Problem 1 の波及で high 記事が0件 → Deep Research 対象0件 → OIP 生成の入力が貧弱。
加えて、`src/analyzer/oip-generator.ts:104-108` と `src/reporter/index.ts` の Claude Sonnet モデル名 `claude-sonnet-4-5-20250929` が有効なモデルかどうか確認が必要。

**修正内容:**
1. モデル名の確認: `claude-sonnet-4-5-20250929` が Anthropic API で有効か確認。無効なら最新の有効なモデル名に修正
   - 有効なモデル名: claude-sonnet-4-5-20250929 (これは正しいはず)
2. OIP 生成の catch ブロックのエラーログを強化（API エラーの詳細を出力）
3. Deep Research の対象選定を改善:
   - `deep-research.ts:17-18` で `orgosImpact === "あり"` のみから、`"要調査"` も対象に含める条件追加
   - ただし最大3件制限は維持

## Acceptance Criteria
- Gemini Flash API によるスコアリングが正常動作（HIGH/MEDIUM/LOW が適切に判定される）
- JSON パースのロバスト化（エンティティ除去、バッチリトライ）
- OIP-AUTO が OrgOS 影響ありの記事から生成される
- TypeScript ビルド通過

## Files to Modify
- src/analyzer/filter.ts (JSON パーサー強化、バッチリトライ、エラーログ改善)
- src/analyzer/oip-generator.ts (モデル名確認、エラーログ強化)
- src/analyzer/deep-research.ts (対象選定改善)
- src/reporter/index.ts (モデル名確認)

## Reference
- 現在のレポート: curl https://orgos-intelligence.dev-2b7.workers.dev/report/2026-02-13
- 設計書: OrgOS リポジトリの .ai/DESIGN/ORGOS_INTELLIGENCE.md Section 4.4, 9.2
