# フロントエンドパターン

> React / Next.js 開発のベストプラクティス（Next.js + TypeScript プロジェクト向け）

> **注意**: このスキルは Next.js + TypeScript + Supabase プロジェクト向けです。
> 別の技術スタックを使用する場合は、プロジェクトに合わせてカスタマイズしてください。

---

## コンポーネント設計

### コンポジション優先

```tsx
// ✅ 良い例: 小さなコンポーネントを組み合わせる
const Card = ({ children }: { children: React.ReactNode }) => (
  <div className="rounded-lg border p-4 shadow-sm">{children}</div>
);

const CardHeader = ({ children }: { children: React.ReactNode }) => (
  <div className="border-b pb-2 mb-4">{children}</div>
);

const CardBody = ({ children }: { children: React.ReactNode }) => (
  <div>{children}</div>
);

// 使用例
<Card>
  <CardHeader>タイトル</CardHeader>
  <CardBody>コンテンツ</CardBody>
</Card>

// ❌ 悪い例: 1つの巨大コンポーネントに全部詰め込む
const Card = ({ title, content, footer, showBorder, ...manyMoreProps }) => (
  // 100行以上のJSX
);
```

### Compound Components

関連するコンポーネントをまとめて提供。

```tsx
interface TabsContextType {
  activeTab: string;
  setActiveTab: (id: string) => void;
}

const TabsContext = createContext<TabsContextType | null>(null);

const Tabs = ({ children, defaultTab }: { children: React.ReactNode; defaultTab: string }) => {
  const [activeTab, setActiveTab] = useState(defaultTab);

  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab }}>
      <div className="tabs">{children}</div>
    </TabsContext.Provider>
  );
};

const TabList = ({ children }: { children: React.ReactNode }) => (
  <div className="tab-list" role="tablist">{children}</div>
);

const Tab = ({ id, children }: { id: string; children: React.ReactNode }) => {
  const context = useContext(TabsContext);
  if (!context) throw new Error('Tab must be used within Tabs');

  return (
    <button
      role="tab"
      aria-selected={context.activeTab === id}
      onClick={() => context.setActiveTab(id)}
    >
      {children}
    </button>
  );
};

const TabPanel = ({ id, children }: { id: string; children: React.ReactNode }) => {
  const context = useContext(TabsContext);
  if (!context) throw new Error('TabPanel must be used within Tabs');
  if (context.activeTab !== id) return null;

  return <div role="tabpanel">{children}</div>;
};

// 使用例
<Tabs defaultTab="tab1">
  <TabList>
    <Tab id="tab1">タブ1</Tab>
    <Tab id="tab2">タブ2</Tab>
  </TabList>
  <TabPanel id="tab1">コンテンツ1</TabPanel>
  <TabPanel id="tab2">コンテンツ2</TabPanel>
</Tabs>
```

---

## カスタムフック

### データフェッチング

```tsx
interface UseFetchResult<T> {
  data: T | null;
  isLoading: boolean;
  error: Error | null;
  refetch: () => void;
}

function useFetch<T>(url: string): UseFetchResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const json = await response.json();
      setData(json);
    } catch (e) {
      setError(e instanceof Error ? e : new Error('Unknown error'));
    } finally {
      setIsLoading(false);
    }
  }, [url]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  return { data, isLoading, error, refetch: fetchData };
}
```

### トグル状態

```tsx
function useToggle(initialValue = false) {
  const [value, setValue] = useState(initialValue);

  const toggle = useCallback(() => setValue(v => !v), []);
  const setTrue = useCallback(() => setValue(true), []);
  const setFalse = useCallback(() => setValue(false), []);

  return { value, toggle, setTrue, setFalse };
}

// 使用例
const { value: isOpen, toggle, setFalse: close } = useToggle();
```

### デバウンス

```tsx
function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}

// 使用例: 検索入力
const [search, setSearch] = useState('');
const debouncedSearch = useDebounce(search, 300);

useEffect(() => {
  if (debouncedSearch) {
    searchAPI(debouncedSearch);
  }
}, [debouncedSearch]);
```

---

## 状態管理

### Context + useReducer

外部ライブラリなしで型安全な状態管理。

```tsx
// types
interface AppState {
  user: User | null;
  theme: 'light' | 'dark';
  notifications: Notification[];
}

type AppAction =
  | { type: 'SET_USER'; payload: User | null }
  | { type: 'SET_THEME'; payload: 'light' | 'dark' }
  | { type: 'ADD_NOTIFICATION'; payload: Notification }
  | { type: 'REMOVE_NOTIFICATION'; payload: string };

// reducer
const appReducer = (state: AppState, action: AppAction): AppState => {
  switch (action.type) {
    case 'SET_USER':
      return { ...state, user: action.payload };
    case 'SET_THEME':
      return { ...state, theme: action.payload };
    case 'ADD_NOTIFICATION':
      return { ...state, notifications: [...state.notifications, action.payload] };
    case 'REMOVE_NOTIFICATION':
      return {
        ...state,
        notifications: state.notifications.filter(n => n.id !== action.payload),
      };
    default:
      return state;
  }
};

// context
const AppContext = createContext<{
  state: AppState;
  dispatch: React.Dispatch<AppAction>;
} | null>(null);

// provider
const AppProvider = ({ children }: { children: React.ReactNode }) => {
  const [state, dispatch] = useReducer(appReducer, initialState);
  return (
    <AppContext.Provider value={{ state, dispatch }}>
      {children}
    </AppContext.Provider>
  );
};

// hook
const useApp = () => {
  const context = useContext(AppContext);
  if (!context) throw new Error('useApp must be used within AppProvider');
  return context;
};
```

---

## Next.js パフォーマンス最適化

> Vercel react-best-practices (259K installs) に基づく Next.js 固有の最適化パターン

### CRITICAL: Waterfall の排除

データフェッチの連鎖（Waterfall）はパフォーマンスの最大の敵。

```tsx
// ❌ 悪い例: 直列フェッチ（Waterfall）
async function Page() {
  const user = await getUser();        // 200ms
  const posts = await getPosts(user.id); // 300ms → 合計 500ms
  return <Feed user={user} posts={posts} />;
}

// ✅ 良い例: 並列フェッチ
async function Page() {
  const userPromise = getUser();
  const postsPromise = getPosts(); // user.id が不要なら並列化
  const [user, posts] = await Promise.all([userPromise, postsPromise]);
  return <Feed user={user} posts={posts} />;
}

// ✅ 良い例: Suspense で段階的表示
async function Page() {
  const user = await getUser();
  return (
    <>
      <UserHeader user={user} />
      <Suspense fallback={<PostsSkeleton />}>
        <PostsList userId={user.id} />
      </Suspense>
    </>
  );
}
```

### CRITICAL: Bundle Size の最適化

```tsx
// ❌ 悪い例: barrel import（ツリーシェイキング不可）
import { Button, Icon, Modal } from '@/components';

// ✅ 良い例: 直接 import
import { Button } from '@/components/Button';
import { Icon } from '@/components/Icon';
import { Modal } from '@/components/Modal';

// ❌ 悪い例: 重いライブラリを同期 import
import { format } from 'date-fns';
import lodash from 'lodash';

// ✅ 良い例: 動的 import + 軽量代替
import { format } from 'date-fns/format'; // サブパス import
// lodash の代わりにネイティブメソッド or 個別 import
import groupBy from 'lodash/groupBy';

// ✅ 良い例: サードパーティを動的ロード
const HeavyChart = dynamic(() => import('@/components/Chart'), {
  loading: () => <ChartSkeleton />,
  ssr: false,
});
```

### HIGH: サーバーサイドパフォーマンス

```tsx
// ✅ React.cache() でリクエスト内のデータ重複排除
import { cache } from 'react';

const getUser = cache(async (id: string) => {
  return db.user.findUnique({ where: { id } });
});

// 同じリクエスト内で複数回呼んでも1回しか実行されない
async function Layout() {
  const user = await getUser(userId); // DB クエリ 1回目
  return <Nav user={user}><Slot /></Nav>;
}

async function Page() {
  const user = await getUser(userId); // キャッシュヒット（DB クエリなし）
  return <Profile user={user} />;
}

// ✅ after() でレスポンス後に非同期処理
import { after } from 'next/server';

export async function POST(request: Request) {
  const data = await request.json();
  const result = await saveData(data);

  after(async () => {
    await logAnalytics(result); // レスポンス後に実行
    await sendNotification(result);
  });

  return Response.json(result); // 先にレスポンスを返す
}
```

### MEDIUM: Re-render の最適化

```tsx
// ❌ 悪い例: 派生値を state にする（無駄な re-render の原因）
const [items, setItems] = useState<Item[]>([]);
const [filteredItems, setFilteredItems] = useState<Item[]>([]);
const [filter, setFilter] = useState('');

useEffect(() => {
  setFilteredItems(items.filter(item => item.name.includes(filter)));
}, [items, filter]);

// ✅ 良い例: useMemo で派生値を計算（state を減らす）
const [items, setItems] = useState<Item[]>([]);
const [filter, setFilter] = useState('');

const filteredItems = useMemo(
  () => items.filter(item => item.name.includes(filter)),
  [items, filter],
);

// ✅ 良い例: 重い更新を useDeferredValue で遅延
function SearchResults({ query }: { query: string }) {
  const deferredQuery = useDeferredValue(query);
  const results = useMemo(() => search(deferredQuery), [deferredQuery]);
  return <List items={results} />;
}

// ✅ 良い例: startTransition で低優先度更新
function handleTabChange(tab: string) {
  startTransition(() => {
    setActiveTab(tab); // UI のブロックなしに更新
  });
}
```

---

## パフォーマンス最適化

### メモ化

```tsx
// useMemo: 計算結果のキャッシュ
const expensiveValue = useMemo(() => {
  return items.filter(item => item.active).sort((a, b) => b.score - a.score);
}, [items]);

// useCallback: 関数参照の安定化
const handleClick = useCallback((id: string) => {
  setSelectedId(id);
}, []);  // 依存がないので関数は安定

// React.memo: コンポーネントの再レンダリング防止
const ListItem = React.memo(({ item, onClick }: ListItemProps) => {
  return <li onClick={() => onClick(item.id)}>{item.name}</li>;
});
```

### 遅延ローディング

```tsx
// コンポーネントの遅延ローディング
const HeavyComponent = lazy(() => import('./HeavyComponent'));

const Page = () => (
  <Suspense fallback={<Loading />}>
    <HeavyComponent />
  </Suspense>
);

// 条件付きローディング
const Modal = lazy(() => import('./Modal'));

const Page = () => {
  const [showModal, setShowModal] = useState(false);

  return (
    <>
      <button onClick={() => setShowModal(true)}>Open</button>
      {showModal && (
        <Suspense fallback={<Loading />}>
          <Modal onClose={() => setShowModal(false)} />
        </Suspense>
      )}
    </>
  );
};
```

### 仮想スクロール

大量リストの効率的なレンダリング。

```tsx
import { useVirtualizer } from '@tanstack/react-virtual';

const VirtualList = ({ items }: { items: Item[] }) => {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 50,
  });

  return (
    <div ref={parentRef} style={{ height: '400px', overflow: 'auto' }}>
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map(virtualRow => (
          <div
            key={virtualRow.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              height: `${virtualRow.size}px`,
              transform: `translateY(${virtualRow.start}px)`,
            }}
          >
            {items[virtualRow.index].name}
          </div>
        ))}
      </div>
    </div>
  );
};
```

---

## フォーム

### 制御コンポーネント + バリデーション

```tsx
interface FormData {
  name: string;
  email: string;
  message: string;
}

interface FormErrors {
  name?: string;
  email?: string;
  message?: string;
}

const ContactForm = () => {
  const [data, setData] = useState<FormData>({ name: '', email: '', message: '' });
  const [errors, setErrors] = useState<FormErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  const validate = (): boolean => {
    const newErrors: FormErrors = {};

    if (!data.name.trim()) {
      newErrors.name = '名前は必須です';
    }

    if (!data.email.match(/^[^\s@]+@[^\s@]+\.[^\s@]+$/)) {
      newErrors.email = '有効なメールアドレスを入力してください';
    }

    if (data.message.length > 500) {
      newErrors.message = 'メッセージは500文字以内で入力してください';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;

    setIsSubmitting(true);
    try {
      await submitForm(data);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <input
          value={data.name}
          onChange={e => setData(d => ({ ...d, name: e.target.value }))}
          aria-invalid={!!errors.name}
        />
        {errors.name && <span className="error">{errors.name}</span>}
      </div>
      {/* 他のフィールド */}
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? '送信中...' : '送信'}
      </button>
    </form>
  );
};
```

---

## エラーバウンダリ

```tsx
interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

class ErrorBoundary extends Component<
  { children: React.ReactNode; fallback?: React.ReactNode },
  ErrorBoundaryState
> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('ErrorBoundary caught:', error, errorInfo);
    // エラーログサービスに送信
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback || (
        <div className="error-container">
          <h2>エラーが発生しました</h2>
          <p>{this.state.error?.message}</p>
          <button onClick={() => this.setState({ hasError: false, error: null })}>
            再試行
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

// 使用例
<ErrorBoundary fallback={<ErrorFallback />}>
  <RiskyComponent />
</ErrorBoundary>
```

---

## アクセシビリティ

### キーボードナビゲーション

```tsx
const Dropdown = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [focusIndex, setFocusIndex] = useState(-1);
  const options = ['Option 1', 'Option 2', 'Option 3'];

  const handleKeyDown = (e: React.KeyboardEvent) => {
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        setFocusIndex(i => Math.min(i + 1, options.length - 1));
        break;
      case 'ArrowUp':
        e.preventDefault();
        setFocusIndex(i => Math.max(i - 1, 0));
        break;
      case 'Enter':
      case ' ':
        if (focusIndex >= 0) {
          selectOption(options[focusIndex]);
        }
        break;
      case 'Escape':
        setIsOpen(false);
        break;
    }
  };

  return (
    <div onKeyDown={handleKeyDown}>
      <button
        aria-haspopup="listbox"
        aria-expanded={isOpen}
        onClick={() => setIsOpen(!isOpen)}
      >
        選択
      </button>
      {isOpen && (
        <ul role="listbox">
          {options.map((option, index) => (
            <li
              key={option}
              role="option"
              aria-selected={focusIndex === index}
              tabIndex={focusIndex === index ? 0 : -1}
            >
              {option}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
};
```

### フォーカス管理

```tsx
const Modal = ({ isOpen, onClose, children }: ModalProps) => {
  const modalRef = useRef<HTMLDivElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (isOpen) {
      previousFocus.current = document.activeElement as HTMLElement;
      modalRef.current?.focus();
    } else {
      previousFocus.current?.focus();
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      ref={modalRef}
      role="dialog"
      aria-modal="true"
      tabIndex={-1}
    >
      {children}
      <button onClick={onClose}>閉じる</button>
    </div>
  );
};
```

---

## React 19 対応

### forwardRef の廃止

```tsx
// ❌ React 18 以前: forwardRef が必要
const Input = forwardRef<HTMLInputElement, InputProps>((props, ref) => (
  <input ref={ref} {...props} />
));

// ✅ React 19: ref は通常の prop
function Input({ ref, ...props }: InputProps & { ref?: React.Ref<HTMLInputElement> }) {
  return <input ref={ref} {...props} />;
}
```

### use() API

```tsx
// ❌ 以前: useContext() のみ
const theme = useContext(ThemeContext);

// ✅ React 19: use() は条件付きで使える
function Component({ isLoggedIn }: { isLoggedIn: boolean }) {
  if (isLoggedIn) {
    const user = use(UserContext); // 条件分岐内で使用可能
    return <Dashboard user={user} />;
  }
  return <LoginPage />;
}
```

---

## 参考資料

- [React Documentation](https://react.dev/)
- [Next.js Documentation](https://nextjs.org/docs)
- [Patterns.dev](https://www.patterns.dev/)
- [Web Accessibility Guidelines (WCAG)](https://www.w3.org/WAI/standards-guidelines/wcag/)
