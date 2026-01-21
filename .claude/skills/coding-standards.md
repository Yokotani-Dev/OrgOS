# コーディング規約

> OrgOS プロジェクトで適用する開発標準

---

## 基本原則

| 原則 | 説明 |
|------|------|
| **KISS** | シンプルに保つ。複雑な解決策より単純な解決策を選ぶ |
| **DRY** | 繰り返しを避ける。ただし早すぎる抽象化も避ける |
| **YAGNI** | 必要になるまで作らない。仮説的な要件に対応しない |
| **可読性優先** | コードは書く時間より読む時間の方が長い |

---

## 命名規則

### 変数・関数

```typescript
// ✅ 良い例: 動詞+名詞、意図が明確
const fetchUserProfile = async (userId: string) => { ... }
const isValidEmail = (email: string): boolean => { ... }
const calculateTotalPrice = (items: Item[]) => { ... }

// ❌ 悪い例: 曖昧、省略しすぎ
const getData = async (id: string) => { ... }
const check = (str: string) => { ... }
const calc = (x: any[]) => { ... }
```

### ファイル・コンポーネント

| 種類 | 規則 | 例 |
|------|------|-----|
| コンポーネント | PascalCase | `UserProfile.tsx` |
| ユーティリティ | camelCase | `formatDate.ts` |
| 定数 | SCREAMING_SNAKE_CASE | `API_ENDPOINTS.ts` |
| 型定義 | PascalCase | `UserTypes.ts` |

---

## TypeScript

### 型安全性

```typescript
// ✅ 明示的な型定義
interface User {
  id: string;
  name: string;
  email: string;
  createdAt: Date;
}

const createUser = (data: Omit<User, 'id' | 'createdAt'>): User => { ... }

// ❌ any は使わない
const processData = (data: any) => { ... }  // 型情報が失われる
```

### イミュータビリティ

```typescript
// ✅ スプレッド演算子で新しいオブジェクトを作成
const updatedUser = { ...user, name: 'New Name' };
const updatedItems = [...items, newItem];

// ❌ 直接変更しない
user.name = 'New Name';  // 副作用の原因
items.push(newItem);     // 元の配列を変更
```

---

## 関数設計

### 単一責任

```typescript
// ✅ 1つの関数は1つのことだけ
const validateEmail = (email: string): boolean => { ... }
const sendVerificationEmail = async (email: string): Promise<void> => { ... }
const saveUser = async (user: User): Promise<User> => { ... }

// ❌ 1つの関数で複数のことをしない
const validateAndSaveUserAndSendEmail = async (...) => { ... }
```

### サイズの目安

| 指標 | 推奨 | 最大 |
|------|------|------|
| 関数の行数 | 20行以下 | 50行 |
| 引数の数 | 3個以下 | 5個（オブジェクトでまとめる） |
| ネストの深さ | 2レベル | 3レベル |

### 早期リターン

```typescript
// ✅ ガード節で早期リターン
const processOrder = (order: Order | null): Result => {
  if (!order) return { error: 'Order not found' };
  if (order.status === 'cancelled') return { error: 'Order cancelled' };
  if (!order.items.length) return { error: 'No items' };

  // メインロジック
  return { success: true, data: calculateTotal(order) };
};

// ❌ 深いネストは避ける
const processOrder = (order: Order | null): Result => {
  if (order) {
    if (order.status !== 'cancelled') {
      if (order.items.length > 0) {
        // ネストが深すぎる
      }
    }
  }
};
```

---

## エラーハンドリング

### 基本パターン

```typescript
// ✅ 具体的なエラーメッセージ
try {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`API error: ${response.status} ${response.statusText}`);
  }
  return await response.json();
} catch (error) {
  console.error('Failed to fetch user data:', error);
  throw error; // または適切なフォールバック
}

// ❌ エラーを握りつぶさない
try {
  await riskyOperation();
} catch (e) {
  // 何もしない = バグの温床
}
```

### Result 型パターン（推奨）

```typescript
type Result<T, E = Error> =
  | { success: true; data: T }
  | { success: false; error: E };

const fetchUser = async (id: string): Promise<Result<User>> => {
  try {
    const user = await db.users.findUnique({ where: { id } });
    if (!user) return { success: false, error: new Error('User not found') };
    return { success: true, data: user };
  } catch (error) {
    return { success: false, error: error as Error };
  }
};
```

---

## 非同期処理

### 並列実行

```typescript
// ✅ 独立した処理は並列で
const [users, orders, products] = await Promise.all([
  fetchUsers(),
  fetchOrders(),
  fetchProducts(),
]);

// ❌ 依存がないのに逐次実行しない
const users = await fetchUsers();
const orders = await fetchOrders();    // users を待つ必要がない
const products = await fetchProducts(); // 同上
```

### エラーハンドリング

```typescript
// 一部の失敗を許容する場合
const results = await Promise.allSettled([
  fetchUser(id1),
  fetchUser(id2),
  fetchUser(id3),
]);

const successfulUsers = results
  .filter((r): r is PromiseFulfilledResult<User> => r.status === 'fulfilled')
  .map(r => r.value);
```

---

## コメント

### 書くべきコメント

```typescript
// ✅ WHY を説明する
// RFC 7231 に従い、204 No Content ではボディを返さない
if (status === 204) return null;

// ✅ 非自明なビジネスロジック
// 30日以上経過した仮登録ユーザーは自動削除対象
const isExpired = daysSinceCreation > 30 && !user.isVerified;
```

### 書くべきでないコメント

```typescript
// ❌ コードを読めばわかること
// ユーザーIDを取得
const userId = user.id;

// ❌ 古くなる可能性が高い情報
// TODO: 来週修正予定
// Author: John (2024-01-01)
```

---

## プロジェクト構成

### 推奨ディレクトリ構造

```
src/
├── components/     # UI コンポーネント
│   ├── common/     # 共通コンポーネント
│   └── features/   # 機能別コンポーネント
├── hooks/          # カスタムフック
├── services/       # API・外部サービス連携
├── utils/          # ユーティリティ関数
├── types/          # 型定義
├── constants/      # 定数
└── lib/            # ライブラリ設定
```

---

## 参考資料

- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/)
- [React TypeScript Cheatsheet](https://react-typescript-cheatsheet.netlify.app/)
- [Clean Code JavaScript](https://github.com/ryanmcdermott/clean-code-javascript)
