# リファクタリングパターン

> コードスメルの検出と修正パターン（TypeScript プロジェクト向け）

> **注意**: このスキルは TypeScript プロジェクト向けです。
> 別の技術スタックを使用する場合は、プロジェクトに合わせてカスタマイズしてください。

> **参照元**: GitHub awesome-copilot refactor skill

---

## リファクタリングの原則

1. **振る舞いを保持する** — リファクタリングは外部から見た振る舞いを変えない
2. **小さなステップで進める** — 1つの変更で1つの改善
3. **テストを先に書く** — リファクタリング前にテストがあることを確認
4. **コミットを細かく** — 各ステップごとにコミット

---

## コードスメル 10 種 + 修正パターン

### 1. Long Method（長すぎるメソッド）

**検出**: 関数が 50 行を超える、または複数の責務を持つ

```typescript
// ❌ 悪い例: 1つの関数に複数の責務
async function processOrder(order: Order) {
  // バリデーション（20行）
  if (!order.items.length) throw new Error('Empty order');
  if (!order.customer) throw new Error('No customer');
  for (const item of order.items) {
    if (item.quantity <= 0) throw new Error('Invalid quantity');
    if (item.price < 0) throw new Error('Invalid price');
  }

  // 合計計算（15行）
  let subtotal = 0;
  for (const item of order.items) {
    subtotal += item.price * item.quantity;
  }
  const tax = subtotal * 0.1;
  const shipping = subtotal > 10000 ? 0 : 500;
  const total = subtotal + tax + shipping;

  // DB保存（10行）
  const saved = await db.orders.create({ ...order, total });

  // メール送信（10行）
  await sendEmail(order.customer.email, `注文確認: ${saved.id}`);

  return saved;
}

// ✅ 良い例: Extract Method で分割
async function processOrder(order: Order) {
  validateOrder(order);
  const total = calculateTotal(order.items);
  const saved = await saveOrder(order, total);
  await notifyCustomer(saved);
  return saved;
}

function validateOrder(order: Order): void {
  if (!order.items.length) throw new Error('Empty order');
  if (!order.customer) throw new Error('No customer');
  order.items.forEach(validateItem);
}

function calculateTotal(items: OrderItem[]): OrderTotal {
  const subtotal = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const tax = subtotal * 0.1;
  const shipping = subtotal > 10000 ? 0 : 500;
  return { subtotal, tax, shipping, total: subtotal + tax + shipping };
}
```

### 2. Duplicated Code（重複コード）

**検出**: 同じロジックが 2 箇所以上に存在する

```typescript
// ❌ 悪い例: フォーマットロジックの重複
function displayUser(user: User) {
  const name = `${user.firstName} ${user.lastName}`.trim();
  return `<div>${name}</div>`;
}

function sendEmail(user: User) {
  const name = `${user.firstName} ${user.lastName}`.trim();
  return `Dear ${name},`;
}

// ✅ 良い例: 共通関数に抽出
function formatFullName(user: User): string {
  return `${user.firstName} ${user.lastName}`.trim();
}

function displayUser(user: User) {
  return `<div>${formatFullName(user)}</div>`;
}

function sendEmail(user: User) {
  return `Dear ${formatFullName(user)},`;
}
```

### 3. Large Class（大きすぎるクラス）

**検出**: 1 つのクラス/モジュールが 300 行を超える、または複数のドメインを扱う

**修正**: 単一責務の原則に従い、関心事ごとにモジュールを分割する

### 4. Long Parameter List（長すぎる引数リスト）

**検出**: 関数の引数が 4 つ以上

```typescript
// ❌ 悪い例: 引数が多すぎる
function createUser(
  name: string,
  email: string,
  age: number,
  role: string,
  department: string,
  isActive: boolean,
) { ... }

// ✅ 良い例: オブジェクト引数
interface CreateUserParams {
  name: string;
  email: string;
  age: number;
  role: string;
  department: string;
  isActive?: boolean;
}

function createUser(params: CreateUserParams) { ... }
```

### 5. Feature Envy（他クラスへの羨望）

**検出**: ある関数が自身のデータより他のオブジェクトのデータを多く参照する

```typescript
// ❌ 悪い例: order のデータを直接操作
function calculateDiscount(order: Order): number {
  if (order.customer.tier === 'gold') return order.total * 0.1;
  if (order.customer.tier === 'silver') return order.total * 0.05;
  return 0;
}

// ✅ 良い例: Customer にメソッドを移動
class Customer {
  getDiscountRate(): number {
    if (this.tier === 'gold') return 0.1;
    if (this.tier === 'silver') return 0.05;
    return 0;
  }
}
```

### 6. Primitive Obsession（プリミティブ型への執着）

**検出**: string や number をドメイン概念として直接使用

```typescript
// ❌ 悪い例: string でメールを扱う
function sendNotification(email: string) { ... }

// ✅ 良い例: ブランド型で型安全性を確保
type Email = string & { readonly __brand: 'Email' };

function parseEmail(value: string): Email {
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
    throw new Error('Invalid email');
  }
  return value as Email;
}

function sendNotification(email: Email) { ... }
```

### 7. Magic Numbers（マジックナンバー）

**検出**: コード中にリテラル値が直接使われている

```typescript
// ❌ 悪い例
if (password.length < 8) { ... }
if (retryCount > 3) { ... }
const timeout = 30000;

// ✅ 良い例: 名前付き定数
const MIN_PASSWORD_LENGTH = 8;
const MAX_RETRY_COUNT = 3;
const REQUEST_TIMEOUT_MS = 30_000;

if (password.length < MIN_PASSWORD_LENGTH) { ... }
if (retryCount > MAX_RETRY_COUNT) { ... }
```

### 8. Nested Conditionals（ネストされた条件分岐）

**検出**: if/else が 3 段以上ネストしている

```typescript
// ❌ 悪い例: 深いネスト
function processPayment(order: Order) {
  if (order.status === 'pending') {
    if (order.total > 0) {
      if (order.customer.hasPaymentMethod) {
        // 処理
      } else {
        throw new Error('No payment method');
      }
    } else {
      throw new Error('Invalid total');
    }
  } else {
    throw new Error('Order not pending');
  }
}

// ✅ 良い例: Early Return（ガード節）
function processPayment(order: Order) {
  if (order.status !== 'pending') throw new Error('Order not pending');
  if (order.total <= 0) throw new Error('Invalid total');
  if (!order.customer.hasPaymentMethod) throw new Error('No payment method');

  // 処理（ネストなし）
}
```

### 9. Dead Code（デッドコード）

**検出**: 呼び出されない関数、到達不能なコード、コメントアウトされたコード

**修正**: 削除する。バージョン管理に履歴がある。

### 10. Inappropriate Intimacy（不適切な親密さ）

**検出**: モジュール間で内部実装の詳細を直接参照している

**修正**: インターフェースを定義し、実装の詳細を隠蔽する

---

## デザインパターンの適用

### Strategy パターン

条件分岐をポリモーフィズムに置き換える。

```typescript
// ❌ 悪い例: 条件分岐の増殖
function calculateShipping(method: string, weight: number): number {
  if (method === 'standard') return weight * 100;
  if (method === 'express') return weight * 300 + 500;
  if (method === 'overnight') return weight * 500 + 1000;
  throw new Error('Unknown method');
}

// ✅ 良い例: Strategy パターン
interface ShippingStrategy {
  calculate(weight: number): number;
}

const shippingStrategies: Record<string, ShippingStrategy> = {
  standard: { calculate: (w) => w * 100 },
  express: { calculate: (w) => w * 300 + 500 },
  overnight: { calculate: (w) => w * 500 + 1000 },
};

function calculateShipping(method: string, weight: number): number {
  const strategy = shippingStrategies[method];
  if (!strategy) throw new Error('Unknown method');
  return strategy.calculate(weight);
}
```

### Chain of Responsibility パターン

複数の処理を連鎖させる。

```typescript
// ✅ バリデーションチェーンの例
type Validator<T> = (value: T) => string | null;

function chain<T>(...validators: Validator<T>[]): Validator<T> {
  return (value: T) => {
    for (const validate of validators) {
      const error = validate(value);
      if (error) return error;
    }
    return null;
  };
}

const validatePassword = chain<string>(
  (v) => (v.length < 8 ? '8文字以上必要です' : null),
  (v) => (!/[A-Z]/.test(v) ? '大文字を含めてください' : null),
  (v) => (!/[0-9]/.test(v) ? '数字を含めてください' : null),
);
```

---

## リファクタリング手順

```
1. PREPARE  — テストが通ることを確認、ブランチを作成
2. IDENTIFY — コードスメルを特定（上記10種を参照）
3. REFACTOR — 小さなステップで修正、各ステップでテスト
4. VERIFY   — 全テスト通過、カバレッジ維持、パフォーマンス確認
5. CLEAN UP — 不要なコメント削除、import 整理、フォーマット
```

---

## 一般的なリファクタリング操作

| 操作 | 説明 | 適用場面 |
|------|------|---------|
| Extract Method | 関数の一部を新しい関数に抽出 | Long Method |
| Inline Method | 1行の関数を呼び出し元に展開 | 不要な間接層 |
| Extract Variable | 複雑な式に名前を付ける | 可読性向上 |
| Rename | 変数・関数・クラスの名前を改善 | 意図が不明瞭 |
| Move Method | メソッドを適切なクラスに移動 | Feature Envy |
| Replace Conditional with Polymorphism | 条件分岐をポリモーフィズムに | 複雑な分岐 |
| Introduce Parameter Object | 引数群をオブジェクトにまとめる | Long Parameter List |
| Replace Magic Number with Constant | リテラルを名前付き定数に | Magic Numbers |
| Guard Clause | ネストを Early Return に変換 | Nested Conditionals |
| Extract Interface | 実装から契約を分離 | Inappropriate Intimacy |

---

## チェックリスト

リファクタリング完了時に確認:

- [ ] テストが全て通っている
- [ ] カバレッジが低下していない
- [ ] 外部から見た振る舞いが変わっていない
- [ ] コードスメルが解消されている
- [ ] 新しいコードスメルを導入していない
- [ ] import が整理されている
- [ ] デッドコードが削除されている

---

## 参考資料

- [Refactoring Guru](https://refactoring.guru/)
- Martin Fowler, "Refactoring: Improving the Design of Existing Code"
- [TypeScript Design Patterns](https://www.typescriptlang.org/docs/handbook/2/types-from-types.html)
