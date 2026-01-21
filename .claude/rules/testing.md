# テストルール

> テスト品質基準と TDD ワークフローのルール

---

## カバレッジ要件

| メトリクス | 最低基準 | 目標 |
|------------|----------|------|
| Statements | 80% | 90% |
| Branches | 80% | 85% |
| Functions | 80% | 90% |
| Lines | 80% | 90% |

**80% を下回るとマージ不可**

---

## 必須テストの種類

### Unit Tests

- すべての関数・メソッドに対してテストを書く
- 外部依存はモック化する
- エッジケース・境界値を必ずカバー

```typescript
describe('calculateDiscount', () => {
  // 正常系
  it('10%割引を正しく計算する', () => { ... });

  // 境界値
  it('割引率0%で元の価格を返す', () => { ... });
  it('割引率100%で0を返す', () => { ... });

  // 異常系
  it('負の割引率でエラーを投げる', () => { ... });
  it('100%超の割引率でエラーを投げる', () => { ... });
});
```

### Integration Tests

- API エンドポイントの動作確認
- データベース操作のテスト
- 外部サービス連携のテスト

```typescript
describe('POST /api/users', () => {
  it('有効なデータでユーザーを作成する', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: 'Test', email: 'test@example.com' })
      .expect(201);

    expect(response.body.data.id).toBeDefined();
  });

  it('重複メールで409エラーを返す', async () => { ... });
  it('無効なデータで400エラーを返す', async () => { ... });
});
```

### E2E Tests

- クリティカルなユーザーフローのテスト
- Playwright を使用
- 最低限以下をカバー:
  - 認証フロー（登録・ログイン・ログアウト）
  - 主要な業務フロー
  - 決済フロー（該当する場合）

```typescript
test('ユーザー登録からダッシュボード表示まで', async ({ page }) => {
  await page.goto('/register');
  await page.fill('[name="email"]', 'new@example.com');
  await page.fill('[name="password"]', 'SecurePass123');
  await page.click('button[type="submit"]');

  await expect(page).toHaveURL('/dashboard');
  await expect(page.locator('h1')).toContainText('Welcome');
});
```

---

## TDD ワークフロー

### 新機能開発時は必ず TDD

```
1. 🔴 テストを書く（失敗することを確認）
2. 🟢 最小限のコードでテストを通す
3. 🔵 リファクタリング（テストは通ったまま）
4. → 1 に戻る
```

### TDD チェックリスト

- [ ] 実装前にテストを書いた
- [ ] テストが失敗することを確認した
- [ ] 最小限のコードでテストを通した
- [ ] リファクタリング後もテストが通る
- [ ] カバレッジ 80% 以上

---

## テストの書き方

### AAA パターン

```typescript
it('ユーザー名を更新する', async () => {
  // Arrange: 準備
  const user = await createTestUser({ name: 'Old Name' });

  // Act: 実行
  const updated = await userService.updateName(user.id, 'New Name');

  // Assert: 検証
  expect(updated.name).toBe('New Name');
});
```

### 説明的なテスト名

```typescript
// ✅ 良い例
it('無効なメールアドレスでValidationErrorを返す', () => { ... });
it('管理者権限がない場合403エラーを返す', () => { ... });

// ❌ 悪い例
it('エラーになる', () => { ... });
it('test case 1', () => { ... });
```

### 独立したテスト

```typescript
// ✅ 各テストは独立
beforeEach(async () => {
  await db.reset();  // テスト間でDBをリセット
});

// ❌ テスト間で状態を共有しない
let sharedUser;  // グローバル状態 = テストの順序依存
```

---

## テスト失敗時の対応

### デバッグ手順

1. **エラーメッセージを読む** - 何が期待と違うか確認
2. **テストの独立性を確認** - 他のテストの影響がないか
3. **モックを確認** - モックが正しく設定されているか
4. **実装を修正** - テストではなく実装を直す

### テストを修正してよいケース

- テストの期待値が間違っている場合
- 仕様変更が正式に承認された場合
- テストが不安定（flaky）な場合

### テストを修正してはいけないケース

- テストを通すためだけに期待値を変える
- 実装の都合でテストを緩める
- カバレッジを上げるために空のテストを追加

---

## CI/CD 統合

### pre-commit

```bash
# 変更されたファイルに関連するテストのみ実行
npm test -- --onlyChanged
```

### Pull Request

```bash
# 全テスト実行 + カバレッジレポート
npm test -- --coverage --coverageReporters=text-summary
```

### マージ条件

- [ ] 全テストが通っている
- [ ] カバレッジ 80% 以上
- [ ] 新規コードにテストがある
- [ ] E2E テストが通っている

---

## OrgOS での適用

### TASKS.yaml での指定

```yaml
- id: T-003
  title: 認証機能の実装
  workflow: tdd           # TDD 強制
  coverage_target: 80%    # カバレッジ目標
```

### Work Order への記載

```markdown
## 技術要件

- ワークフロー: TDD
- カバレッジ目標: 80%
- 必須テスト: Unit + Integration

## 成果物

- [ ] 実装コード
- [ ] Unit テスト
- [ ] Integration テスト
- [ ] カバレッジレポート
```

---

## 参考資料

- [.claude/skills/tdd-workflow.md](.claude/skills/tdd-workflow.md)
- [Jest Documentation](https://jestjs.io/)
- [Vitest Documentation](https://vitest.dev/)
- [Playwright Documentation](https://playwright.dev/)
