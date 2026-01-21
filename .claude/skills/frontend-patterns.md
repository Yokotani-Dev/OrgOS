# フロントエンドパターン

> React / Next.js 開発のベストプラクティス

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

## 参考資料

- [React Documentation](https://react.dev/)
- [Next.js Documentation](https://nextjs.org/docs)
- [Patterns.dev](https://www.patterns.dev/)
- [Web Accessibility Guidelines (WCAG)](https://www.w3.org/WAI/standards-guidelines/wcag/)
