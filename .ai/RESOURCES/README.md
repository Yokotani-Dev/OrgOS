# RESOURCES - 参照資料格納ディレクトリ

> プロジェクトで参照する既存リソース・資料を格納する場所。

---

## ディレクトリ構成

```
RESOURCES/
  README.md       # この説明
  docs/           # 参照ドキュメント（仕様書、API仕様等）
  designs/        # デザイン資料（Figma export, ワイヤーフレーム等）
  references/     # 外部参照資料（論文、ベンチマーク等）
  code-samples/   # 流用・参考コードサンプル
```

---

## 使い方

### 1. 資料を格納

適切なサブディレクトリに資料を配置する：

```bash
# ドキュメント
cp ~/Downloads/api-spec.pdf .ai/RESOURCES/docs/

# デザイン
cp ~/Downloads/mockup.png .ai/RESOURCES/designs/

# 参考コード
cp -r ~/old-project/utils .ai/RESOURCES/code-samples/
```

### 2. BRIEF.md で参照

`.ai/BRIEF.md` の「既存資産」セクションで参照を明記：

```markdown
## 既存資産
- ドキュメント: `.ai/RESOURCES/docs/api-spec.pdf`
- デザイン: `.ai/RESOURCES/designs/mockup.png`
- 流用コード: `.ai/RESOURCES/code-samples/utils/`
```

### 3. Manager/Worker が参照

キックオフ時やタスク実行時に Manager/Worker がこのディレクトリを参照する。

---

## 注意事項

- **秘匿情報を含むファイルは配置しない**（.env, credentials 等）
- 大きなバイナリファイルは Git LFS の利用を検討
- 外部URLで参照可能なものは URL のみ記載でも可

---

## 推奨ファイル形式

| 種類 | 推奨形式 |
|------|----------|
| ドキュメント | Markdown, PDF |
| デザイン | PNG, SVG, Figma URL |
| コード | そのまま配置 |
| データ | JSON, CSV |
