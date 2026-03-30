# skills.sh 調査結果 (2026-03-29)

> T-OS-050: 公式スキル精査 + OrgOS ギャップ分析

---

## 調査対象

| ソース | スキル数 | 総 installs | 品質 |
|--------|---------|------------|------|
| Anthropic 公式 | 17 | 918K | 高（プロダクションスキル含む） |
| Vercel 公式 | 7 | 672K | 非常に高（優先度付きルール、BAD/GOOD例） |
| GitHub/Community | 260+ | 1.6M | 混在（厳選20件を精査済み） |

---

## 精査したスキル一覧（品質評価付き）

### Tier S（非常に高品質、OrgOS に直接価値がある）

| スキル | ソース | installs | OrgOS 関連度 | 概要 |
|--------|--------|---------|-------------|------|
| vercel-react-best-practices | Vercel | 259K | **frontend-patterns** | 65ルール/8カテゴリ、優先度付き。Waterfall排除、Bundle最適化、Re-render最適化、SSR パフォーマンス |
| web-design-guidelines | Vercel | 209K | **frontend-patterns** | 100+ルール。Accessibility、Forms、Animation、Typography、Dark Mode、i18n、Anti-patterns |
| refactor | GitHub | 11K | **新規** | 10種コードスメル + 修正パターン、Strategy/Chain of Responsibility パターン |
| codeql | GitHub | 8K | **security** | CodeQL セキュリティスキャン完全ガイド、GitHub Actions/CLI 両対応 |
| skill-creator | Anthropic | - | **OrgOS メタ** | スキル設計の哲学、Progressive Disclosure、評価ループ |

### Tier A（高品質、特定領域で価値がある）

| スキル | ソース | installs | OrgOS 関連度 | 概要 |
|--------|--------|---------|-------------|------|
| webapp-testing | Anthropic | - | **testing** | Playwright Reconnaissance-Then-Action パターン、サーバーライフサイクル管理 |
| vercel-composition-patterns | Vercel | 105K | **frontend-patterns** | state/actions/meta の3部構成 Context、React 19 APIs |
| agentic-eval | GitHub | 8K | **eval-loop** | Reflection/Evaluator-Optimizer パターン、ルーブリック評価 |
| sql-optimization | GitHub | 8K | **backend-patterns** | MySQL/PostgreSQL/SQL Server/Oracle 対応、BAD/GOOD パターン |
| frontend-design | Anthropic | 216K | **新規** | プロダクショングレード UI 生成、Typography/Color/Motion/Spatial ガイド |
| architecture-blueprint-generator | GitHub | 8K | **design-documentation** | C4/UML図生成、ADR生成 |

### Tier B（中品質、参考レベル）

| スキル | ソース | installs | OrgOS 関連度 | 概要 |
|--------|--------|---------|-------------|------|
| git-commit | GitHub | 19K | **既存で十分** | Conventional Commits（OrgOS は独自コミット規約あり） |
| prd | GitHub | 12K | **org-planner** | PRD生成（OrgOS は BRIEF.md + PROJECT.md で代替） |
| documentation-writer | GitHub | 12K | **参考** | Diataxis Framework（Tutorial/How-to/Reference/Explanation） |
| playwright-generate-test | GitHub | 8K | **testing** | MCP経由テスト生成（webapp-testing の方が上質） |
| javascript-typescript-jest | GitHub | 8K | **testing** | Jest パターン（OrgOS 既存で十分カバー） |

---

## ギャップ分析：OrgOS 既存 vs 外部スキル

### GAP-1: フロントエンドパフォーマンス（CRITICAL）

**現状**: frontend-patterns.md は基本パターン（memo, lazy, virtual scroll）のみ
**外部**: Vercel の react-best-practices は **65ルール/優先度付き** で以下をカバー:

| カテゴリ | OrgOS | Vercel | ギャップ |
|----------|-------|--------|---------|
| Waterfall 排除 | なし | CRITICAL（5ルール） | Promise.all, Suspense boundaries, defer await |
| Bundle Size | なし | CRITICAL（5ルール） | barrel import 回避, dynamic import, third-party defer |
| SSR パフォーマンス | なし | HIGH（9ルール） | React.cache(), LRU cache, after(), parallel fetching |
| Client-Side Data | なし | MEDIUM-HIGH（4ルール） | SWR dedup, passive event listeners |
| Re-render 最適化 | 基本のみ | MEDIUM（15ルール） | derived state, useDeferredValue, startTransition |
| Rendering | 基本のみ | MEDIUM（11ルール） | content-visibility, hydration mismatch prevention |
| JS パフォーマンス | なし | LOW-MEDIUM（14ルール） | Set/Map O(1), flatMap, requestIdleCallback |

**推奨**: frontend-patterns.md に「パフォーマンス最適化」セクションを大幅拡充

### GAP-2: Web デザイン / アクセシビリティ（HIGH）

**現状**: frontend-patterns.md にキーボードナビゲーション + フォーカス管理の2例のみ
**外部**: Vercel の web-design-guidelines は **100+ルール** で以下をカバー:

- Accessibility（aria-label, semantic HTML, keyboard handlers）
- Forms（autocomplete, validation, paste blocking prohibition）
- Animation（prefers-reduced-motion, compositor-friendly transforms）
- Typography（curly quotes, ellipsis, tabular-nums）
- Dark Mode / Theming（color-scheme, theme-color meta）
- i18n（Intl.DateTimeFormat, Intl.NumberFormat）
- Hydration Safety（suppressHydrationWarning）
- Anti-patterns リスト

**推奨**: 新規スキル `web-design-guidelines.md` を作成

### GAP-3: リファクタリングパターン（HIGH）

**現状**: なし（review-criteria.md に品質指摘はあるが、修正パターンがない）
**外部**: GitHub の refactor スキルが以下をカバー:
- 10種のコードスメル + 具体的な修正パターン（diff 形式）
- デザインパターン適用（Strategy, Chain of Responsibility）
- チェックリスト付き

**推奨**: 新規スキル `refactoring-patterns.md` を作成

### GAP-4: Playwright E2E テスト詳細パターン（MEDIUM）

**現状**: testing.md に基本的な Playwright 例（3行）のみ
**外部**: Anthropic の webapp-testing が以下をカバー:
- Reconnaissance-Then-Action パターン（先に DOM 検査、次にアクション）
- サーバーライフサイクル管理（with_server.py）
- networkidle 待機の徹底
- セレクタ戦略

**推奨**: testing.md の E2E セクションを拡充

### GAP-5: セキュリティスキャン自動化（MEDIUM）

**現状**: security.md は手動チェックリスト + OWASP コード例
**外部**: GitHub の codeql スキルが以下をカバー:
- CodeQL CLI / GitHub Actions 両対応
- SARIF 出力
- カスタムクエリ作成
- セキュリティアラート管理

**推奨**: security.md に「自動スキャン」セクションを追加

### GAP-6: SQL / データベース最適化（MEDIUM）

**現状**: backend-patterns.md に N+1 防止 + クエリ最適化の基本のみ
**外部**: GitHub の sql-optimization が以下をカバー:
- MySQL/PostgreSQL/SQL Server/Oracle 個別パターン
- BAD/GOOD 形式の具体例多数
- INDEX 設計、JOIN 最適化、サブクエリ改善

**推奨**: backend-patterns.md の「データベース最適化」セクションを拡充

### GAP-7: コンポーネント構成パターン（LOW）

**現状**: frontend-patterns.md に Compound Components の例あり
**外部**: Vercel の composition-patterns が以下を追加:
- state/actions/meta の3部構成 Context Interface
- boolean prop 回避パターン
- React 19 APIs（use(), forwardRef 廃止）

**推奨**: frontend-patterns.md に React 19 対応を追記

---

## 統合計画

### Phase 1: 既存スキル強化（差分マージ）

| 対象ファイル | 追加内容 | ソース | 優先度 |
|-------------|---------|--------|--------|
| frontend-patterns.md | パフォーマンス最適化セクション（Waterfall排除、Bundle最適化、Re-render最適化） | Vercel react-best-practices | CRITICAL |
| frontend-patterns.md | React 19 APIs（use(), forwardRef廃止） | Vercel composition-patterns | LOW |
| testing.md | Playwright E2E 詳細パターン（Reconnaissance-Then-Action） | Anthropic webapp-testing | MEDIUM |
| security.md | 自動スキャン（CodeQL / SAST） | GitHub codeql | MEDIUM |
| backend-patterns.md | SQL 最適化パターン拡充 | GitHub sql-optimization | MEDIUM |

### Phase 2: 新規スキル作成

| 新規ファイル | 内容 | ソース | 優先度 |
|-------------|------|--------|--------|
| web-design-guidelines.md | アクセシビリティ、フォーム、アニメーション、i18n、ダークモード | Vercel web-design-guidelines | HIGH |
| refactoring-patterns.md | コードスメル10種 + 修正パターン + デザインパターン適用 | GitHub refactor | HIGH |

### Phase 3: OrgOS メタ改善（スキル設計自体の改善）

Anthropic の skill-creator から学んだベストプラクティスを OrgOS スキル全体に適用:
- Progressive Disclosure（メタデータ → 本文 → 参照ファイルの3層）
- 「ALWAYS/NEVER より WHY を説明」
- 500行以下の制約
- BAD/GOOD パターン形式の統一

---

## 導入しない判断をしたスキル

| スキル | 理由 |
|--------|------|
| git-commit | OrgOS は独自のコミット規約を持つ |
| prd | BRIEF.md + PROJECT.md で代替済み |
| frontend-design (Anthropic) | UI生成特化で、OrgOS のスキル（開発規約）とは性質が異なる |
| vercel-react-native-skills | React Native はスコープ外 |
| deploy-to-vercel | デプロイ先固有のスキル |
| documentation-writer | 参考になるが、OrgOS の設計ドキュメントルールで十分 |

---

## 参考: スキル設計のベストプラクティス（skill-creator より）

1. **SKILL.md は 500 行以下** -- 長すぎるとコンテキストを圧迫
2. **Description がトリガー** -- いつこのスキルが使われるべきかを明記
3. **WHY を説明** -- ALWAYS/NEVER の羅列より理由を示す方が効果的
4. **Progressive Disclosure** -- 全情報を1ファイルに詰め込まない
5. **BAD/GOOD パターン** -- コード例は必ず「悪い例 → 良い例」の対比で
6. **チェックリスト** -- 適用確認用のチェックリストを末尾に
