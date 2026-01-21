# バックエンドパターン

> Node.js / Express / Next.js API 開発のベストプラクティス

---

## API 設計

### RESTful 規約

| メソッド | 用途 | 例 |
|----------|------|-----|
| GET | リソース取得 | `GET /users/:id` |
| POST | リソース作成 | `POST /users` |
| PUT | リソース全体更新 | `PUT /users/:id` |
| PATCH | リソース部分更新 | `PATCH /users/:id` |
| DELETE | リソース削除 | `DELETE /users/:id` |

### URL 設計

```typescript
// ✅ 良い例: リソースベース、複数形
GET    /users              // 一覧取得
GET    /users/:id          // 単体取得
GET    /users/:id/orders   // 関連リソース
POST   /users              // 作成
PATCH  /users/:id          // 更新
DELETE /users/:id          // 削除

// ✅ クエリパラメータでフィルタ・ページネーション
GET /users?status=active&page=1&limit=20&sort=createdAt:desc

// ❌ 悪い例: 動詞を含む、単数形
GET /getUser/:id
POST /createNewUser
GET /user/list
```

### レスポンス形式

```typescript
// 成功時
interface SuccessResponse<T> {
  success: true;
  data: T;
  meta?: {
    page: number;
    limit: number;
    total: number;
  };
}

// エラー時
interface ErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

// 例
const response: SuccessResponse<User[]> = {
  success: true,
  data: users,
  meta: { page: 1, limit: 20, total: 100 }
};
```

---

## アーキテクチャパターン

### リポジトリパターン

データアクセスロジックをビジネスロジックから分離。

```typescript
// repository/userRepository.ts
interface UserRepository {
  findById(id: string): Promise<User | null>;
  findByEmail(email: string): Promise<User | null>;
  create(data: CreateUserData): Promise<User>;
  update(id: string, data: UpdateUserData): Promise<User>;
  delete(id: string): Promise<void>;
}

class SupabaseUserRepository implements UserRepository {
  constructor(private supabase: SupabaseClient) {}

  async findById(id: string): Promise<User | null> {
    const { data, error } = await this.supabase
      .from('users')
      .select('id, name, email, created_at')
      .eq('id', id)
      .single();

    if (error) throw new DatabaseError(error.message);
    return data;
  }
  // ... 他のメソッド
}
```

### サービス層

ビジネスロジックを集約。

```typescript
// services/userService.ts
class UserService {
  constructor(
    private userRepo: UserRepository,
    private emailService: EmailService
  ) {}

  async registerUser(data: RegisterData): Promise<User> {
    // バリデーション
    const existingUser = await this.userRepo.findByEmail(data.email);
    if (existingUser) {
      throw new ConflictError('Email already registered');
    }

    // ユーザー作成
    const user = await this.userRepo.create({
      ...data,
      password: await hashPassword(data.password),
    });

    // ウェルカムメール送信
    await this.emailService.sendWelcome(user.email);

    return user;
  }
}
```

### ミドルウェアパターン

横断的関心事を処理。

```typescript
// middleware/auth.ts
const authenticate = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const payload = verifyToken(token);
    req.user = payload;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};

// middleware/rateLimit.ts
const rateLimit = (limit: number, windowMs: number) => {
  const requests = new Map<string, number[]>();

  return (req: Request, res: Response, next: NextFunction) => {
    const key = req.ip;
    const now = Date.now();
    const windowStart = now - windowMs;

    const userRequests = (requests.get(key) || [])
      .filter(time => time > windowStart);

    if (userRequests.length >= limit) {
      return res.status(429).json({ error: 'Too many requests' });
    }

    userRequests.push(now);
    requests.set(key, userRequests);
    next();
  };
};
```

---

## データベース

### クエリ最適化

```typescript
// ✅ 必要なカラムだけ選択
const { data } = await supabase
  .from('users')
  .select('id, name, email')  // * ではなく必要なカラムのみ
  .eq('status', 'active');

// ✅ N+1 問題を避ける（バッチ取得）
const users = await supabase
  .from('users')
  .select('*, orders(*)')  // JOIN で一括取得
  .in('id', userIds);

// ❌ N+1 問題
for (const userId of userIds) {
  const orders = await supabase
    .from('orders')
    .select('*')
    .eq('user_id', userId);  // ループ内でクエリ = 遅い
}
```

### トランザクション

```typescript
// Supabase RPC でトランザクション
const { data, error } = await supabase.rpc('transfer_funds', {
  from_account: fromId,
  to_account: toId,
  amount: amount,
});

// PostgreSQL 関数側
// CREATE FUNCTION transfer_funds(from_account uuid, to_account uuid, amount numeric)
// RETURNS void AS $$
// BEGIN
//   UPDATE accounts SET balance = balance - amount WHERE id = from_account;
//   UPDATE accounts SET balance = balance + amount WHERE id = to_account;
// END;
// $$ LANGUAGE plpgsql;
```

---

## キャッシング

### Redis パターン

```typescript
// Cache-Aside パターン
class CacheService {
  constructor(private redis: Redis) {}

  async getOrSet<T>(
    key: string,
    fetcher: () => Promise<T>,
    ttl: number = 3600
  ): Promise<T> {
    // キャッシュ確認
    const cached = await this.redis.get(key);
    if (cached) {
      return JSON.parse(cached);
    }

    // キャッシュミス時はフェッチして保存
    const data = await fetcher();
    await this.redis.setex(key, ttl, JSON.stringify(data));
    return data;
  }

  async invalidate(pattern: string): Promise<void> {
    const keys = await this.redis.keys(pattern);
    if (keys.length > 0) {
      await this.redis.del(...keys);
    }
  }
}

// 使用例
const user = await cache.getOrSet(
  `user:${userId}`,
  () => userRepo.findById(userId),
  3600  // 1時間キャッシュ
);
```

---

## エラーハンドリング

### カスタムエラークラス

```typescript
class AppError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public code: string
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

class NotFoundError extends AppError {
  constructor(resource: string) {
    super(`${resource} not found`, 404, 'NOT_FOUND');
  }
}

class ValidationError extends AppError {
  constructor(message: string, public details?: unknown) {
    super(message, 400, 'VALIDATION_ERROR');
  }
}

class ConflictError extends AppError {
  constructor(message: string) {
    super(message, 409, 'CONFLICT');
  }
}
```

### 集中エラーハンドラ

```typescript
const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  console.error('Error:', err);

  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      success: false,
      error: {
        code: err.code,
        message: err.message,
        details: (err as ValidationError).details,
      },
    });
  }

  // 予期しないエラー
  return res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
    },
  });
};
```

### リトライロジック

```typescript
const withRetry = async <T>(
  fn: () => Promise<T>,
  options: { maxRetries?: number; delay?: number } = {}
): Promise<T> => {
  const { maxRetries = 3, delay = 1000 } = options;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (attempt === maxRetries) throw error;

      // 指数バックオフ
      const waitTime = delay * Math.pow(2, attempt - 1);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }

  throw new Error('Unreachable');
};
```

---

## 認証・認可

### JWT 検証

```typescript
import { jwtVerify } from 'jose';

const verifyToken = async (token: string): Promise<JWTPayload> => {
  const secret = new TextEncoder().encode(process.env.JWT_SECRET);
  const { payload } = await jwtVerify(token, secret);
  return payload;
};
```

### RBAC（ロールベースアクセス制御）

```typescript
type Role = 'admin' | 'editor' | 'viewer';
type Permission = 'read' | 'write' | 'delete';

const rolePermissions: Record<Role, Permission[]> = {
  admin: ['read', 'write', 'delete'],
  editor: ['read', 'write'],
  viewer: ['read'],
};

const requirePermission = (permission: Permission) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const userRole = req.user?.role as Role;

    if (!userRole || !rolePermissions[userRole].includes(permission)) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    next();
  };
};

// 使用例
app.delete('/users/:id', authenticate, requirePermission('delete'), deleteUser);
```

---

## バリデーション

### Zod スキーマ

```typescript
import { z } from 'zod';

const createUserSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
  password: z.string().min(8).regex(/[A-Z]/).regex(/[0-9]/),
  role: z.enum(['admin', 'editor', 'viewer']).default('viewer'),
});

type CreateUserInput = z.infer<typeof createUserSchema>;

const validateRequest = <T>(schema: z.Schema<T>) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse(req.body);

    if (!result.success) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Invalid request body',
          details: result.error.flatten(),
        },
      });
    }

    req.body = result.data;
    next();
  };
};
```

---

## 参考資料

- [RESTful API Design Best Practices](https://restfulapi.net/)
- [Node.js Best Practices](https://github.com/goldbergyoni/nodebestpractices)
- [Supabase Documentation](https://supabase.com/docs)
