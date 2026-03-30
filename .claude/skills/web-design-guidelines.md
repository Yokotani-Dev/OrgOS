# Web デザインガイドライン

> UI 実装時に準拠すべきデザイン・アクセシビリティルール（Next.js + TypeScript プロジェクト向け）

> **注意**: このスキルは Next.js + TypeScript プロジェクト向けです。
> 別の技術スタックを使用する場合は、プロジェクトに合わせてカスタマイズしてください。

> **参照元**: Vercel Web Interface Guidelines (https://github.com/vercel-labs/web-interface-guidelines)

---

## アクセシビリティ

### 必須ルール

| # | ルール | 理由 |
|---|--------|------|
| 1 | アイコンのみのボタンには `aria-label` を付ける | スクリーンリーダーがボタンの目的を読み上げられない |
| 2 | フォームコントロールには `<label>` または `aria-label` を付ける | 入力フィールドの目的が不明になる |
| 3 | インタラクティブ要素には `onKeyDown`/`onKeyUp` を付ける | キーボードユーザーが操作できない |
| 4 | アクションには `<button>`、ナビゲーションには `<a>`/`<Link>` を使う | `<div onClick>` はアクセシビリティツリーに反映されない |
| 5 | 画像には `alt` を付ける（装飾的なら `alt=""`) | 画像の内容が伝わらない |
| 6 | 装飾アイコンには `aria-hidden="true"` を付ける | スクリーンリーダーが不要な情報を読み上げる |
| 7 | 非同期更新（トースト、バリデーション）には `aria-live="polite"` | 画面変更が通知されない |
| 8 | ARIA より前にセマンティック HTML を使う | `<button>`, `<a>`, `<label>`, `<table>` を優先 |
| 9 | 見出しは `<h1>`〜`<h6>` の階層を守る | スキップリンクと構造が壊れる |

```tsx
// ❌ 悪い例: div にクリックハンドラ
<div onClick={() => navigate('/home')}>ホームへ</div>

// ✅ 良い例: Link コンポーネント
<Link href="/home">ホームへ</Link>

// ❌ 悪い例: アイコンボタンにラベルなし
<button><SearchIcon /></button>

// ✅ 良い例: aria-label 付き
<button aria-label="検索"><SearchIcon aria-hidden="true" /></button>
```

---

## フォーカス状態

- `focus-visible:ring-*` で可視フォーカスを実装する
- `outline: none` を `focus-visible` の代替なしに使わない
- `:focus` より `:focus-visible` を使う（クリック時のリングを防ぐ）
- 複合コントロールには `:focus-within` を使う

```tsx
// ❌ 悪い例: フォーカスリングを削除
<button className="outline-none">送信</button>

// ✅ 良い例: focus-visible で代替
<button className="outline-none focus-visible:ring-2 focus-visible:ring-blue-500">
  送信
</button>
```

---

## フォーム

### 必須ルール

| # | ルール | 理由 |
|---|--------|------|
| 1 | `autocomplete` と意味のある `name` を付ける | ブラウザの自動入力が機能しない |
| 2 | 正しい `type` を使う（`email`, `tel`, `url`, `number`） | モバイルで適切なキーボードが表示されない |
| 3 | ペースト禁止（`onPaste` + `preventDefault`）にしない | ユーザビリティを著しく損なう |
| 4 | メール・コード・ユーザー名には `spellCheck={false}` | 赤い下線が表示される |
| 5 | 送信ボタンはリクエスト開始まで有効、リクエスト中はスピナー | 二重送信防止 + フィードバック |
| 6 | エラーはフィールドの横にインライン表示、送信時に最初のエラーにフォーカス | エラー位置が分からない |
| 7 | プレースホルダーは `…` で終わり、例のパターンを表示 | 入力形式が分からない |
| 8 | 未保存の変更がある場合、ナビゲーション前に警告する | データ消失を防ぐ |

```tsx
// ❌ 悪い例
<input type="text" placeholder="email" />

// ✅ 良い例
<input
  type="email"
  name="email"
  autoComplete="email"
  inputMode="email"
  spellCheck={false}
  placeholder="you@example.com"
  aria-invalid={!!errors.email}
  aria-describedby={errors.email ? "email-error" : undefined}
/>
{errors.email && (
  <span id="email-error" role="alert">{errors.email}</span>
)}
```

---

## アニメーション

- `prefers-reduced-motion` を尊重する（軽量版を提供するか無効化）
- `transform` / `opacity` のみアニメーションする（コンポジター最適化）
- `transition: all` は使わない — プロパティを明示的にリストする
- アニメーションは中断可能にする（ユーザー入力に応答）

```tsx
// ❌ 悪い例: transition: all
<div className="transition-all duration-300" />

// ✅ 良い例: プロパティを明示
<div className="transition-[transform,opacity] duration-300" />

// ✅ 良い例: reduced-motion 対応
<div className="motion-safe:animate-fadeIn motion-reduce:animate-none" />
```

---

## タイポグラフィ

- `…`（ellipsis）を使う、`...` ではなく
- カーリークォート `"` `"` を使う、ストレート `"` ではなく
- 数値列には `font-variant-numeric: tabular-nums` を使う
- 見出しには `text-wrap: balance` を使う（widow 防止）
- ノンブレークスペース: `10&nbsp;MB`, `⌘&nbsp;K`

---

## コンテンツ処理

- テキストコンテナは長いコンテンツに対応する: `truncate`, `line-clamp-*`, `break-words`
- Flex の子要素には `min-w-0` を付けてトランケーションを許可する
- 空の状態を処理する — 空文字列・空配列で壊れた UI を表示しない
- ユーザー生成コンテンツ: 短い・平均的・非常に長い入力を想定する

```tsx
// ❌ 悪い例: 長い名前でレイアウトが崩れる
<div className="flex gap-2">
  <span>{user.name}</span>
</div>

// ✅ 良い例: トランケーション対応
<div className="flex gap-2">
  <span className="min-w-0 truncate">{user.name}</span>
</div>

// ✅ 良い例: 空の状態
{items.length > 0 ? (
  <ItemList items={items} />
) : (
  <EmptyState message="アイテムがありません" />
)}
```

---

## 画像

- `<img>` には `width` と `height` を明示する（CLS 防止）
- Below-the-fold の画像: `loading="lazy"`
- Above-the-fold の重要画像: `priority` または `fetchpriority="high"`

---

## パフォーマンス

- 大きなリスト（50件超）: 仮想化する（`virtua`, `content-visibility: auto`）
- レンダリング中にレイアウト読み取りをしない（`getBoundingClientRect`, `offsetHeight`）
- DOM の読み書きをバッチ処理する — インターリーブしない
- CDN/アセットドメインには `<link rel="preconnect">` を付ける
- クリティカルフォントは `<link rel="preload" as="font">` + `font-display: swap`

---

## ナビゲーション & 状態

- URL が状態を反映する — フィルタ、タブ、ページネーション、展開パネルをクエリパラメータに
- リンクは `<a>`/`<Link>` を使う（Cmd/Ctrl+クリック、中クリック対応）
- `useState` を使う場合は URL 同期を検討する（nuqs 等）
- 破壊的アクションは確認モーダルまたは Undo ウィンドウを設ける — 即時実行しない

---

## タッチ & インタラクション

- `touch-action: manipulation`（ダブルタップズーム遅延を防止）
- モーダル/ドロワーには `overscroll-behavior: contain`
- ドラッグ中: テキスト選択を無効化

---

## ダークモード & テーマ

- ダークテーマでは `color-scheme: dark` を `<html>` に設定（スクロールバー、input が修正される）
- `<meta name="theme-color">` をページ背景色に合わせる
- ネイティブ `<select>` には明示的な `background-color` と `color` を設定（Windows ダークモード対策）

---

## i18n

- 日付/時刻: `Intl.DateTimeFormat` を使う、ハードコードしない
- 数値/通貨: `Intl.NumberFormat` を使う、ハードコードしない
- 言語検出: `Accept-Language` / `navigator.languages` を使う、IP ではなく

```tsx
// ❌ 悪い例: ハードコードされた日付フォーマット
const formatted = `${date.getMonth() + 1}/${date.getDate()}/${date.getFullYear()}`;

// ✅ 良い例: Intl API
const formatted = new Intl.DateTimeFormat('ja-JP', {
  year: 'numeric',
  month: 'long',
  day: 'numeric',
}).format(date);
```

---

## Hydration 安全性

- `value` のある input には `onChange` を付ける（または `defaultValue` で非制御にする）
- 日付/時刻レンダリング: hydration mismatch をガードする（サーバー vs クライアント）
- `suppressHydrationWarning` は本当に必要な場合のみ

---

## アンチパターン（検出すべき）

以下のパターンをコードレビューでフラグする:

| パターン | 問題 |
|----------|------|
| `user-scalable=no` / `maximum-scale=1` | ズーム無効化 |
| `onPaste` + `preventDefault` | ペースト禁止 |
| `transition: all` | パフォーマンス劣化 |
| `outline-none` without `focus-visible` | フォーカス消失 |
| `<div onClick>` でナビゲーション | アクセシビリティ欠如 |
| `<div>`/`<span>` + click handler | `<button>` を使うべき |
| 画像に dimensions なし | CLS の原因 |
| 大量配列 `.map()` without 仮想化 | パフォーマンス劣化 |
| フォーム input にラベルなし | アクセシビリティ欠如 |
| ハードコードされた日付/数値フォーマット | `Intl.*` を使うべき |

---

## チェックリスト

レビュー時に確認:

- [ ] すべてのインタラクティブ要素にキーボードアクセス可能
- [ ] フォームに適切なラベル・autocomplete・type が設定されている
- [ ] アニメーションが `prefers-reduced-motion` を尊重している
- [ ] 画像に width/height が設定されている
- [ ] 大量リストが仮想化されている
- [ ] URL が UI 状態を反映している
- [ ] ダークモードが正しく動作する
- [ ] i18n 対応（Intl API 使用）

---

## 参考資料

- [Web Interface Guidelines](https://github.com/vercel-labs/web-interface-guidelines)
- [WCAG 2.1](https://www.w3.org/WAI/standards-guidelines/wcag/)
- [Tailwind CSS Accessibility](https://tailwindcss.com/docs/accessibility)
