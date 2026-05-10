# RESOURCES - 参照資料格納ディレクトリ

> プロジェクトで参照する既存リソース・資料を格納する場所。

---

## 外部インプットファイル管理台帳

Owner から受領したファイルを記録します。AI は本台帳を読まずにファイルを編集してはなりません。

| ファイル名 | 配置先 | 提供元 | 用途 | 受領日 |
|-----------|--------|--------|------|--------|
| (entries) | | | | |

---

## ディレクトリ構成

```
RESOURCES/
  README.md       # この説明
  docs/           # 参照ドキュメント（仕様書、API仕様等）
    inputs/       # Owner から受領したインプット文書
    outputs/      # AI が生成したアウトプット控え
  designs/        # デザイン資料（Figma export, ワイヤーフレーム等）
  skills/         # カスタムスキル素材
  references/     # 外部参照資料（論文、ベンチマーク等）
  code-samples/   # 流用・参考コードサンプル
```

---

## サブディレクトリ構成

- `docs/inputs/`  - Owner から受領したインプット文書
- `docs/outputs/` - AI が生成したアウトプット (但し正式な outputs/ は別途プロジェクトルートに)
- `designs/`     - デザイン関連 (Figma エクスポート等)
- `skills/`      - カスタムスキル素材

---

## 使い方

### 1. 資料を格納

Owner から受領した資料は、台帳登録後に適切なサブディレクトリへ配置する：

```bash
# ドキュメント
cp ~/Downloads/api-spec.pdf .ai/RESOURCES/docs/inputs/

# デザイン
cp ~/Downloads/mockup.png .ai/RESOURCES/designs/

# スキル素材
cp ~/Downloads/skill-reference.md .ai/RESOURCES/skills/
```

### 2. BRIEF.md で参照

`.ai/BRIEF.md` の「既存資産」セクションで参照を明記：

```markdown
## 既存資産
- ドキュメント: `.ai/RESOURCES/docs/inputs/api-spec.pdf`
- デザイン: `.ai/RESOURCES/designs/mockup.png`
- スキル素材: `.ai/RESOURCES/skills/skill-reference.md`
```

### 3. Manager/Worker が参照

キックオフ時やタスク実行時に Manager/Worker がこのディレクトリを参照する。AI は `.ai/RESOURCES/` を参照元として Read するだけで、編集・上書きしない。

---

## 注意事項

- `.ai/RESOURCES/` 配下は read-only として扱う
- 成果物を修正する場合は `outputs/` にバージョンを上げて出力する
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
