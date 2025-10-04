# JWT Authentication 使用指南

## 概述

OpenCode Server 現已啟用 JWT (JSON Web Token) 認證。所有 API endpoints（除了 public endpoints）都需要有效的 JWT token 才能存取。

## 配置

### JWT Secret

預設 JWT Secret：
```
pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd
```

**自訂 Secret（推薦）：**
```bash
export JWT_SECRET="your-custom-secret-key-here"
```

### 相關檔案

- `src/auth/jwt.ts` - JWT 核心邏輯
- `src/server/server.ts` - Server 整合與 middleware

## 使用方式

### 1. 取得 JWT Token

**方法 A: 外部系統生成**

如果你的 user authentication 在其他系統，該系統應該生成包含以下 payload 的 JWT：

```json
{
  "userId": "user-123",
  "username": "john_doe",
  "email": "john@example.com",
  "iat": 1234567890,
  "exp": 1234567890
}
```

使用相同的 secret (`pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd`) 簽署。

**方法 B: 使用內建生成函數（可選）**

如果需要 server 端生成 token，可以使用：

```typescript
import { JWT } from "./src/auth/jwt"

const token = await JWT.createToken({
  userId: "user-123",
  username: "john_doe",
  email: "john@example.com"
}, "7d") // 7 天有效期
```

### 2. 發送請求

所有 protected endpoints 都需要在 `Authorization` header 中包含 JWT token：

```bash
curl http://localhost:64722/session \
  -H "Authorization: Bearer <your-jwt-token>"
```

或使用簡短格式：

```bash
curl http://localhost:64722/session \
  -H "Authorization: <your-jwt-token>"
```

### 3. Public Endpoints

以下 endpoints **不需要** JWT 驗證：

- `GET /doc` - OpenAPI 文件
- `GET /health` - Health check（如有實作）

### 4. 在 Handler 中取得 User 資訊

在任何 route handler 中，可以取得已驗證的 user 資訊：

```typescript
import { JWT } from "../auth/jwt"

app.get("/user/profile", async (c) => {
  const user = JWT.getPayload(c)

  console.log(user.userId)    // "user-123"
  console.log(user.username)  // "john_doe"
  console.log(user.email)     // "john@example.com"

  return c.json({ user })
})
```

## 測試範例

### 使用 Node.js 生成測試 Token

建立 `generate-token.js`：

```javascript
import { SignJWT } from 'jose'

const secret = new TextEncoder().encode(
  'pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd'
)

const token = await new SignJWT({
  userId: 'test-user-123',
  username: 'testuser',
  email: 'test@example.com'
})
  .setProtectedHeader({ alg: 'HS256' })
  .setIssuedAt()
  .setExpirationTime('7d')
  .sign(secret)

console.log('JWT Token:', token)
```

執行：
```bash
npm install jose
node generate-token.js
```

### 使用 Python 生成測試 Token

```python
import jwt
import datetime

secret = "pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd"

payload = {
    "userId": "test-user-123",
    "username": "testuser",
    "email": "test@example.com",
    "iat": datetime.datetime.utcnow(),
    "exp": datetime.datetime.utcnow() + datetime.timedelta(days=7)
}

token = jwt.encode(payload, secret, algorithm="HS256")
print(f"JWT Token: {token}")
```

### 測試 API 請求

```bash
# 儲存 token
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 測試 protected endpoint
curl http://localhost:64722/session \
  -H "Authorization: Bearer $TOKEN"

# 測試 public endpoint (不需要 token)
curl http://localhost:64722/doc

# 測試無效 token (應回傳 401)
curl http://localhost:64722/session \
  -H "Authorization: Bearer invalid-token"
```

## 錯誤回應

### 401 Unauthorized - Missing Token

```json
{
  "message": "Authorization header missing"
}
```

### 401 Unauthorized - Invalid Token

```json
{
  "message": "Invalid or expired token"
}
```

## 進階配置

### 自訂 Public Paths

編輯 `src/server/server.ts:133-136`：

```typescript
const publicPaths = [
  "/doc",
  "/health",
  "/public/*",           // 允許所有 /public/ 路徑
  "/api/v1/login",       // 允許登入 endpoint
]
```

### Optional Authentication

如果某些 endpoints 希望 "有 token 就驗證，沒有也放行"，可以使用：

```typescript
app.get("/content", JWT.optionalMiddleware(), async (c) => {
  const user = JWT.getPayload(c)

  if (user) {
    // 已登入用戶，顯示個人化內容
    return c.json({ message: `Hello ${user.username}` })
  } else {
    // 匿名用戶，顯示一般內容
    return c.json({ message: "Hello guest" })
  }
})
```

### 自訂 Token 過期時間

預設：7 天

修改 `src/auth/jwt.ts:29`：

```typescript
export async function createToken(payload: Payload, expiresIn: string = "24h")
```

支援格式：
- `"30s"` - 30 秒
- `"15m"` - 15 分鐘
- `"24h"` - 24 小時
- `"7d"` - 7 天

## 整合範例

### 與外部 Auth Service 整合

```typescript
// 在你的 auth service
import jwt from 'jsonwebtoken'

function generateTokenForUser(user) {
  return jwt.sign(
    {
      userId: user.id,
      username: user.username,
      email: user.email,
      roles: user.roles
    },
    process.env.JWT_SECRET,
    { expiresIn: '7d' }
  )
}

// User 登入成功後
const token = generateTokenForUser(authenticatedUser)
res.json({ token })
```

### 前端使用

```javascript
// 儲存 token
localStorage.setItem('token', response.token)

// 發送請求
fetch('http://localhost:64722/session', {
  headers: {
    'Authorization': `Bearer ${localStorage.getItem('token')}`
  }
})
```

## Troubleshooting

### Q: 為什麼一直收到 401?

檢查：
1. Token 是否過期？
2. Secret 是否一致？
3. Header 格式是否正確？`Authorization: Bearer <token>`
4. Token 是否被正確簽署？

### Q: 如何 debug JWT 問題?

1. 使用 [jwt.io](https://jwt.io) 解碼你的 token
2. 檢查 server logs：
   ```bash
   tail -f ~/.local/share/opencode/log/*.log
   ```
3. 測試驗證：
   ```typescript
   import { JWT } from "./src/auth/jwt"

   try {
     const payload = await JWT.verifyToken(yourToken)
     console.log("Valid token:", payload)
   } catch (e) {
     console.error("Invalid token:", e)
   }
   ```

### Q: 如何臨時停用 JWT?

註解掉 `src/server/server.ts` 的 JWT middleware (行 130-147)

## 安全建議

1. ✅ **使用環境變數** 設定 JWT_SECRET，不要 hardcode
2. ✅ **使用 HTTPS** 在生產環境中傳輸 token
3. ✅ **設定適當的過期時間** (建議不超過 24 小時)
4. ✅ **實作 token refresh** 機制
5. ✅ **記錄異常登入** 嘗試
6. ❌ **不要在 URL 中傳遞** JWT token
7. ❌ **不要在 client 端儲存敏感資訊** 到 JWT payload

## 相關資源

- [JWT.io](https://jwt.io) - JWT Debugger
- [Hono JWT Middleware](https://hono.dev/helpers/jwt)
- [RFC 7519 - JWT Spec](https://datatracker.ietf.org/doc/html/rfc7519)
