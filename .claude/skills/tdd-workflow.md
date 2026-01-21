# TDD ワークフロー

> テスト駆動開発（Test-Driven Development）の実践ガイド

---

## 基本原則

**「テストがないコードは書かない」**

TDD は以下のサイクルで進める:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   🔴 Red → 🟢 Green → 🔵 Refactor → 🔴 Red → ...           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

| フェーズ | 説明 |
|----------|------|
| 🔴 Red | 失敗するテストを書く |
| 🟢 Green | テストを通す最小限のコードを書く |
| 🔵 Refactor | コードを改善する（テストは通ったまま） |

---

## ワークフロー

### Step 1: テストを先に書く（Red）

```typescript
// ❌ まだ実装していない機能のテスト
describe('calculateDiscount', () => {
  it('10%割引を適用する', () => {
    const result = calculateDiscount(1000, 0.1);
    expect(result).toBe(900);
  });

  it('割引率が0の場合は元の価格を返す', () => {
    const result = calculateDiscount(1000, 0);
    expect(result).toBe(1000);
  });

  it('負の割引率はエラーになる', () => {
    expect(() => calculateDiscount(1000, -0.1)).toThrow('Invalid discount rate');
  });
});
```

この時点でテストを実行 → **失敗することを確認**

### Step 2: テストを通す（Green）

```typescript
// 最小限の実装
const calculateDiscount = (price: number, rate: number): number => {
  if (rate < 0) throw new Error('Invalid discount rate');
  return price * (1 - rate);
};
```

テストを実行 → **全て通ることを確認**

### Step 3: リファクタリング（Refactor）

```typescript
// 改善: バリデーション追加、型安全性向上
interface DiscountParams {
  price: number;
  rate: number;
}

const calculateDiscount = ({ price, rate }: DiscountParams): number => {
  if (rate < 0 || rate > 1) {
    throw new Error('Discount rate must be between 0 and 1');
  }
  if (price < 0) {
    throw new Error('Price cannot be negative');
  }
  return Math.round(price * (1 - rate));
};
```

テストを実行 → **まだ全て通ることを確認**

---

## テストの種類と優先度

| 種類 | 割合目安 | 対象 |
|------|----------|------|
| Unit Tests | 70% | 個別の関数・クラス |
| Integration Tests | 20% | API エンドポイント、DB 操作 |
| E2E Tests | 10% | クリティカルなユーザーフロー |

### Unit Tests

```typescript
// 関数単体のテスト
describe('formatCurrency', () => {
  it('日本円形式でフォーマットする', () => {
    expect(formatCurrency(1234, 'JPY')).toBe('¥1,234');
  });

  it('小数点以下を四捨五入する', () => {
    expect(formatCurrency(1234.567, 'JPY')).toBe('¥1,235');
  });
});

// 外部依存はモック化
describe('UserService', () => {
  const mockUserRepo = {
    findById: jest.fn(),
    save: jest.fn(),
  };

  it('ユーザーを取得できる', async () => {
    mockUserRepo.findById.mockResolvedValue({ id: '1', name: 'Test' });

    const service = new UserService(mockUserRepo);
    const user = await service.getUser('1');

    expect(user.name).toBe('Test');
    expect(mockUserRepo.findById).toHaveBeenCalledWith('1');
  });
});
```

### Integration Tests

```typescript
// API エンドポイントのテスト
describe('POST /api/users', () => {
  it('ユーザーを作成できる', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: 'Test User', email: 'test@example.com' })
      .expect(201);

    expect(response.body.success).toBe(true);
    expect(response.body.data.name).toBe('Test User');
  });

  it('バリデーションエラーを返す', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: '' })  // email がない
      .expect(400);

    expect(response.body.success).toBe(false);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
  });
});
```

### E2E Tests

```typescript
// Playwright でのクリティカルフロー
test('ユーザー登録からログインまで', async ({ page }) => {
  // 登録
  await page.goto('/register');
  await page.fill('[name="email"]', 'new@example.com');
  await page.fill('[name="password"]', 'SecurePass123');
  await page.click('button[type="submit"]');

  // 確認メッセージ
  await expect(page.locator('.success-message')).toBeVisible();

  // ログイン
  await page.goto('/login');
  await page.fill('[name="email"]', 'new@example.com');
  await page.fill('[name="password"]', 'SecurePass123');
  await page.click('button[type="submit"]');

  // ダッシュボードに遷移
  await expect(page).toHaveURL('/dashboard');
});
```

---

## 必ずテストすべきケース

### エッジケース

```typescript
describe('parseUserInput', () => {
  // 正常系
  it('有効な入力を解析する', () => { ... });

  // 境界値
  it('空文字列を処理する', () => { ... });
  it('null/undefined を処理する', () => { ... });
  it('最大長の入力を処理する', () => { ... });

  // 異常系
  it('不正な型でエラーを返す', () => { ... });
  it('特殊文字を適切にエスケープする', () => { ... });
});
```

### 非同期処理

```typescript
describe('fetchWithRetry', () => {
  it('成功時はデータを返す', async () => { ... });
  it('一時的な失敗後にリトライして成功する', async () => { ... });
  it('最大リトライ回数を超えるとエラーを返す', async () => { ... });
  it('タイムアウトを処理する', async () => { ... });
});
```

### 状態遷移

```typescript
describe('OrderStateMachine', () => {
  it('pending → confirmed に遷移できる', () => { ... });
  it('confirmed → shipped に遷移できる', () => { ... });
  it('cancelled からは遷移できない', () => { ... });
  it('不正な遷移でエラーを返す', () => { ... });
});
```

---

## カバレッジ目標

| メトリクス | 目標 |
|------------|------|
| Statements | 80% 以上 |
| Branches | 80% 以上 |
| Functions | 80% 以上 |
| Lines | 80% 以上 |

### カバレッジ確認

```bash
# Jest の場合
npm test -- --coverage

# 出力例
---------------------------|---------|----------|---------|---------|
File                       | % Stmts | % Branch | % Funcs | % Lines |
---------------------------|---------|----------|---------|---------|
All files                  |   85.71 |    83.33 |   90.00 |   85.71 |
 src/services/user.ts      |   100   |    100   |   100   |   100   |
 src/utils/format.ts       |   75    |    66.67 |   80    |   75    |
---------------------------|---------|----------|---------|---------|
```

---

## テストの書き方

### AAA パターン

```typescript
it('ユーザーの年齢を計算する', () => {
  // Arrange: 準備
  const user = { birthDate: new Date('1990-01-15') };
  const today = new Date('2024-01-15');

  // Act: 実行
  const age = calculateAge(user.birthDate, today);

  // Assert: 検証
  expect(age).toBe(34);
});
```

### 説明的なテスト名

```typescript
// ✅ 良い例: 何をテストしているか明確
describe('UserService.register', () => {
  it('有効なデータでユーザーを作成し、確認メールを送信する', () => { ... });
  it('既存のメールアドレスで登録するとConflictErrorを返す', () => { ... });
  it('パスワードが8文字未満だとValidationErrorを返す', () => { ... });
});

// ❌ 悪い例: 曖昧
describe('register', () => {
  it('works', () => { ... });
  it('fails', () => { ... });
  it('test1', () => { ... });
});
```

### 独立したテスト

```typescript
// ✅ 各テストは独立して実行可能
describe('CartService', () => {
  let cart: Cart;

  beforeEach(() => {
    cart = new Cart();  // 毎回新しいインスタンス
  });

  it('商品を追加できる', () => {
    cart.add({ id: '1', quantity: 2 });
    expect(cart.items).toHaveLength(1);
  });

  it('商品を削除できる', () => {
    cart.add({ id: '1', quantity: 2 });
    cart.remove('1');
    expect(cart.items).toHaveLength(0);
  });
});

// ❌ 悪い例: テスト間で状態を共有
let sharedCart = new Cart();  // テスト順序に依存してしまう
```

---

## CI/CD 統合

### pre-commit フック

```json
// package.json
{
  "husky": {
    "hooks": {
      "pre-commit": "npm test -- --onlyChanged"
    }
  }
}
```

### GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm test -- --coverage
      - name: Check coverage threshold
        run: |
          coverage=$(cat coverage/coverage-summary.json | jq '.total.lines.pct')
          if (( $(echo "$coverage < 80" | bc -l) )); then
            echo "Coverage $coverage% is below 80%"
            exit 1
          fi
```

---

## OrgOS での適用

### TASKS.yaml での指定

```yaml
- id: T-003
  title: 認証機能の実装
  workflow: tdd           # TDD 強制
  coverage_target: 80%    # カバレッジ目標
  status: pending
```

### Work Order への記載

```markdown
## 技術要件

- ワークフロー: TDD
- カバレッジ目標: 80%
- 参照: .claude/skills/tdd-workflow.md

## 実装手順

1. テストファイルを作成
2. 失敗するテストを書く
3. 最小限の実装でテストを通す
4. リファクタリング
5. 次のテストへ
```

---

## 参考資料

- [Test-Driven Development by Example (Kent Beck)](https://www.amazon.com/Test-Driven-Development-Kent-Beck/dp/0321146530)
- [Jest Documentation](https://jestjs.io/)
- [Vitest Documentation](https://vitest.dev/)
- [Playwright Documentation](https://playwright.dev/)
