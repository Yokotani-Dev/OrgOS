# 共通パターン

> プロジェクト全体で使用する共通パターンとテンプレート

---

## API レスポンス形式

### 統一フォーマット

```typescript
// 成功レスポンス
interface SuccessResponse<T> {
  success: true;
  data: T;
  meta?: {
    total: number;
    page: number;
    limit: number;
    hasMore: boolean;
  };
}

// エラーレスポンス
interface ErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

// 統合型
type ApiResponse<T> = SuccessResponse<T> | ErrorResponse;
```

### 使用例

```typescript
// 成功
return res.status(200).json({
  success: true,
  data: user,
});

// ページネーション付き
return res.status(200).json({
  success: true,
  data: users,
  meta: {
    total: 100,
    page: 1,
    limit: 20,
    hasMore: true,
  },
});

// エラー
return res.status(400).json({
  success: false,
  error: {
    code: 'VALIDATION_ERROR',
    message: 'Invalid email format',
    details: { field: 'email' },
  },
});
```

---

## リポジトリパターン

### インターフェース定義

```typescript
interface Repository<T, ID = string> {
  findAll(options?: FindOptions): Promise<T[]>;
  findById(id: ID): Promise<T | null>;
  create(data: Omit<T, 'id' | 'createdAt' | 'updatedAt'>): Promise<T>;
  update(id: ID, data: Partial<T>): Promise<T>;
  delete(id: ID): Promise<void>;
}

interface FindOptions {
  page?: number;
  limit?: number;
  orderBy?: string;
  order?: 'asc' | 'desc';
  filters?: Record<string, unknown>;
}
```

### 実装例

```typescript
class SupabaseUserRepository implements Repository<User> {
  constructor(private supabase: SupabaseClient) {}

  async findAll(options: FindOptions = {}): Promise<User[]> {
    const { page = 1, limit = 20, orderBy = 'createdAt', order = 'desc' } = options;

    const { data, error } = await this.supabase
      .from('users')
      .select('*')
      .order(orderBy, { ascending: order === 'asc' })
      .range((page - 1) * limit, page * limit - 1);

    if (error) throw new DatabaseError(error.message);
    return data;
  }

  async findById(id: string): Promise<User | null> {
    const { data, error } = await this.supabase
      .from('users')
      .select('*')
      .eq('id', id)
      .single();

    if (error && error.code !== 'PGRST116') throw new DatabaseError(error.message);
    return data;
  }

  // ... 他のメソッド
}
```

---

## カスタムフックパターン

### useDebounce

```typescript
function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => clearTimeout(handler);
  }, [value, delay]);

  return debouncedValue;
}

// 使用例
const [search, setSearch] = useState('');
const debouncedSearch = useDebounce(search, 300);

useEffect(() => {
  if (debouncedSearch) {
    fetchResults(debouncedSearch);
  }
}, [debouncedSearch]);
```

### useFetch

```typescript
interface UseFetchResult<T> {
  data: T | null;
  isLoading: boolean;
  error: Error | null;
  refetch: () => void;
}

function useFetch<T>(url: string, options?: RequestInit): UseFetchResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(url, options);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const json = await response.json();
      setData(json);
    } catch (e) {
      setError(e instanceof Error ? e : new Error('Unknown error'));
    } finally {
      setIsLoading(false);
    }
  }, [url, JSON.stringify(options)]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data, isLoading, error, refetch: fetchData };
}
```

### useLocalStorage

```typescript
function useLocalStorage<T>(key: string, initialValue: T): [T, (value: T) => void] {
  const [storedValue, setStoredValue] = useState<T>(() => {
    if (typeof window === 'undefined') return initialValue;

    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = useCallback((value: T) => {
    setStoredValue(value);
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(key, JSON.stringify(value));
    }
  }, [key]);

  return [storedValue, setValue];
}
```

---

## エラーハンドリングパターン

### カスタムエラークラス

```typescript
class AppError extends Error {
  constructor(
    message: string,
    public statusCode: number,
    public code: string,
    public details?: unknown
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

class NotFoundError extends AppError {
  constructor(resource: string, id?: string) {
    super(
      `${resource}${id ? ` with id ${id}` : ''} not found`,
      404,
      'NOT_FOUND'
    );
  }
}

class ValidationError extends AppError {
  constructor(message: string, details?: unknown) {
    super(message, 400, 'VALIDATION_ERROR', details);
  }
}

class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized') {
    super(message, 401, 'UNAUTHORIZED');
  }
}

class ForbiddenError extends AppError {
  constructor(message = 'Forbidden') {
    super(message, 403, 'FORBIDDEN');
  }
}

class ConflictError extends AppError {
  constructor(message: string) {
    super(message, 409, 'CONFLICT');
  }
}
```

### Result 型パターン

```typescript
type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

// ヘルパー関数
const ok = <T>(value: T): Result<T, never> => ({ ok: true, value });
const err = <E>(error: E): Result<never, E> => ({ ok: false, error });

// 使用例
async function parseConfig(path: string): Promise<Result<Config, string>> {
  try {
    const content = await fs.readFile(path, 'utf-8');
    const config = JSON.parse(content);
    return ok(config);
  } catch (e) {
    return err(`Failed to parse config: ${e}`);
  }
}

// 呼び出し側
const result = await parseConfig('./config.json');
if (result.ok) {
  console.log(result.value);
} else {
  console.error(result.error);
}
```

---

## バリデーションパターン

### Zod スキーマ

```typescript
import { z } from 'zod';

// 共通スキーマ
const emailSchema = z.string().email().max(255);
const passwordSchema = z.string().min(8).max(128);
const uuidSchema = z.string().uuid();

// エンティティスキーマ
const userSchema = z.object({
  id: uuidSchema,
  email: emailSchema,
  name: z.string().min(1).max(100),
  role: z.enum(['admin', 'editor', 'viewer']),
  createdAt: z.date(),
  updatedAt: z.date(),
});

// 入力スキーマ（作成用）
const createUserSchema = userSchema.omit({
  id: true,
  createdAt: true,
  updatedAt: true,
}).extend({
  password: passwordSchema,
});

// 入力スキーマ（更新用）
const updateUserSchema = createUserSchema.partial().omit({
  password: true,
});

// 型の自動生成
type User = z.infer<typeof userSchema>;
type CreateUserInput = z.infer<typeof createUserSchema>;
type UpdateUserInput = z.infer<typeof updateUserSchema>;
```

---

## 状態管理パターン

### Context + useReducer

```typescript
// 型定義
interface State {
  user: User | null;
  isLoading: boolean;
  error: Error | null;
}

type Action =
  | { type: 'SET_USER'; payload: User }
  | { type: 'LOGOUT' }
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_ERROR'; payload: Error };

// Reducer
function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'SET_USER':
      return { ...state, user: action.payload, isLoading: false };
    case 'LOGOUT':
      return { ...state, user: null };
    case 'SET_LOADING':
      return { ...state, isLoading: action.payload };
    case 'SET_ERROR':
      return { ...state, error: action.payload, isLoading: false };
    default:
      return state;
  }
}

// Context
const AuthContext = createContext<{
  state: State;
  dispatch: React.Dispatch<Action>;
} | null>(null);

// Provider
function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(reducer, {
    user: null,
    isLoading: true,
    error: null,
  });

  return (
    <AuthContext.Provider value={{ state, dispatch }}>
      {children}
    </AuthContext.Provider>
  );
}

// Hook
function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
```

---

## 参考資料

- [.claude/skills/backend-patterns.md](../skills/backend-patterns.md)
- [.claude/skills/frontend-patterns.md](../skills/frontend-patterns.md)
- [.claude/skills/coding-standards.md](../skills/coding-standards.md)
