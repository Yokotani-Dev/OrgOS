# /org-export

OrgOSのリリースフローを案内する。通常はGitHub Actionsで自動リリースされる。

## 通常のリリースフロー

1. **変更を完了**
   - 機能追加・修正をコミット

2. **バージョン更新**
   - `.ai/VERSION.yaml` の `current` を更新
   - `.ai/CHANGELOG.md` に変更内容を日本語で追記

3. **タグを打ってプッシュ**
   ```bash
   git add -A
   git commit -m "Release v0.x.x"
   git tag v0.x.x
   git push origin main --tags
   ```

4. **自動リリース**
   - GitHub Actions がトリガー
   - `orgos-v0.x.x.tar.gz` が自動生成
   - GitHub Releases に添付される

## 手動エクスポート（ローカルテスト用）

ローカルでバンドルを作成したい場合：

```bash
VERSION=$(grep 'current:' .ai/VERSION.yaml | cut -d'"' -f2)
tar -czf orgos-v${VERSION}.tar.gz \
  .ai/VERSION.yaml \
  .ai/CHANGELOG.md \
  .ai/RESOURCES/README.md \
  .ai/RESOURCES/BRIEF_TEMPLATE.md \
  .claude/commands/org-*.md \
  .orgos-manifest.yaml \
  CLAUDE.md
```

## リリースURL

https://github.com/Yokotani-Dev/OrgOS-Dev/releases

## 別プロジェクトでの使用

```
/org-import v0.1.0
```

GitHub Releases から自動でダウンロード・展開されます。
