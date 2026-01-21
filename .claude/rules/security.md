# セキュリティルール

> コードレビュー・実装時に必ず確認するセキュリティチェックリスト

---

## 必須チェック（コミット前）

| # | カテゴリ | チェック内容 |
|---|----------|--------------|
| 1 | シークレット | API キー、パスワード、トークンがハードコードされていない |
| 2 | 入力検証 | すべてのユーザー入力がバリデーションされている |
| 3 | SQL インジェクション | パラメータ化クエリを使用している |
| 4 | XSS | HTML 出力がサニタイズされている |
| 5 | CSRF | 状態変更リクエストに CSRF 対策がある |
| 6 | 認証・認可 | 適切なアクセス制御が実装されている |
| 7 | レートリミット | エンドポイントにレート制限がある |
| 8 | エラーメッセージ | エラーで機密情報が漏洩しない |

---

## OWASP Top 10 対応

### A01: アクセス制御の不備

```typescript
// ❌ 危険: ユーザーIDを信頼している
app.get('/users/:id/data', async (req, res) => {
  const data = await db.getData(req.params.id);  // 誰でも取得可能
  return res.json(data);
});

// ✅ 安全: 認証ユーザーと照合
app.get('/users/:id/data', authenticate, async (req, res) => {
  if (req.user.id !== req.params.id && req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden' });
  }
  const data = await db.getData(req.params.id);
  return res.json(data);
});
```

### A02: 暗号化の失敗

```typescript
// ❌ 危険: 平文でパスワード保存
await db.insert({ password: userInput.password });

// ✅ 安全: ハッシュ化して保存
import { hash } from 'bcrypt';
const hashedPassword = await hash(userInput.password, 12);
await db.insert({ password: hashedPassword });
```

### A03: インジェクション

```typescript
// ❌ 危険: 文字列結合でクエリ構築
const query = `SELECT * FROM users WHERE id = '${userId}'`;

// ✅ 安全: パラメータ化クエリ
const { data } = await supabase
  .from('users')
  .select('*')
  .eq('id', userId);

// ✅ 安全: Prepared Statement
const result = await db.query('SELECT * FROM users WHERE id = $1', [userId]);
```

### A07: XSS（クロスサイトスクリプティング）

```typescript
// ❌ 危険: ユーザー入力をそのまま表示
element.innerHTML = userInput;

// ✅ 安全: テキストとして挿入
element.textContent = userInput;

// ✅ 安全: React はデフォルトでエスケープ
return <div>{userInput}</div>;

// ⚠️ 注意: dangerouslySetInnerHTML は使用禁止
return <div dangerouslySetInnerHTML={{ __html: userInput }} />;  // NG
```

---

## シークレット管理

### 環境変数を使用

```typescript
// ✅ 正しい方法
const apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  throw new Error('OPENAI_API_KEY is not configured');
}

// ❌ 絶対にしない
const apiKey = 'sk-xxxxxxxxxxxxx';  // ハードコード禁止
```

### .env ファイルの扱い

```bash
# .gitignore に必ず追加
.env
.env.local
.env.*.local
```

### シークレット検出パターン

以下のパターンをコードに含めない:

| 種類 | パターン例 |
|------|-----------|
| AWS | `AKIA[0-9A-Z]{16}` |
| GitHub | `ghp_[a-zA-Z0-9]{36}` |
| OpenAI | `sk-[a-zA-Z0-9]{48}` |
| Stripe | `sk_live_[a-zA-Z0-9]{24}` |
| JWT | `eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*` |

---

## 認証・認可

### JWT 検証

```typescript
import { jwtVerify } from 'jose';

const verifyToken = async (token: string) => {
  const secret = new TextEncoder().encode(process.env.JWT_SECRET);

  try {
    const { payload } = await jwtVerify(token, secret);
    return payload;
  } catch (error) {
    throw new UnauthorizedError('Invalid token');
  }
};
```

### ロールベースアクセス制御

```typescript
type Role = 'admin' | 'editor' | 'viewer';

const permissions: Record<Role, string[]> = {
  admin: ['read', 'write', 'delete', 'admin'],
  editor: ['read', 'write'],
  viewer: ['read'],
};

const requirePermission = (permission: string) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const userRole = req.user?.role as Role;

    if (!userRole || !permissions[userRole]?.includes(permission)) {
      return res.status(403).json({ error: 'Forbidden' });
    }

    next();
  };
};
```

---

## 入力バリデーション

### Zod スキーマ

```typescript
import { z } from 'zod';

const userSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(8).max(128),
  name: z.string().min(1).max(100).regex(/^[\p{L}\s'-]+$/u),
});

// リクエスト検証
const validateRequest = <T>(schema: z.Schema<T>) => {
  return (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse(req.body);

    if (!result.success) {
      return res.status(400).json({
        error: 'Validation failed',
        details: result.error.flatten(),
      });
    }

    req.body = result.data;
    next();
  };
};
```

---

## セキュリティヘッダー

```typescript
// Next.js next.config.js
const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-XSS-Protection', value: '1; mode=block' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  {
    key: 'Content-Security-Policy',
    value: "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';",
  },
  {
    key: 'Strict-Transport-Security',
    value: 'max-age=31536000; includeSubDomains',
  },
];

module.exports = {
  async headers() {
    return [{ source: '/:path*', headers: securityHeaders }];
  },
};
```

---

## インシデント対応

脆弱性を発見した場合:

1. **即座に作業停止** - 脆弱なコードをデプロイしない
2. **専門家に相談** - org-security-reviewer を実行
3. **修正を優先** - 他の作業より優先して対応
4. **認証情報ローテーション** - 漏洩の可能性がある場合は即座に更新
5. **全体監査** - 類似の問題がないかコードベースを確認

---

## 参考資料

- [OWASP Top 10](https://owasp.org/Top10/)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [Node.js Security Best Practices](https://nodejs.org/en/docs/guides/security/)
