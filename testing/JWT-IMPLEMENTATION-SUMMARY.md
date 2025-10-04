# JWT Authentication 實作總結

## ✅ 已完成

成功為 OpenCode Server 加入 JWT authentication 功能。

## 📁 修改/新增的檔案

### 核心實作

1. **`opencode_v2/packages/opencode/src/auth/jwt.ts`** (新增)
   - JWT 核心邏輯
   - Token 驗證與生成
   - Hono middleware 實作
   - 可選的 authentication middleware

2. **`opencode_v2/packages/opencode/src/server/server.ts`** (修改)
   - 加入 JWT middleware
   - 新增 401 錯誤處理
   - 設定 public endpoints (不需要驗證)
   - 整合 HTTPException 處理

### 文件與測試

3. **`opencode_v2/JWT-AUTHENTICATION.md`** (新增)
   - 完整使用指南
   - API 範例
   - 測試方法
   - Troubleshooting

4. **`opencode_v2/generate-test-token.ts`** (新增)
   - 測試 token 生成工具
   - 支援自訂 payload

5. **`opencode_v2/test-jwt.sh`** (新增)
   - 自動化測試腳本
   - 驗證所有情境

## 🔑 配置資訊

### JWT Secret
```
pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd
```

可透過環境變數覆蓋：
```bash
export JWT_SECRET="your-secret-key"
```

### Public Endpoints (不需要驗證)

- `GET /doc` - OpenAPI 文件
- `GET /health` - Health check

### Protected Endpoints (需要驗證)

除 public endpoints 外的所有 API endpoints。

## 🚀 快速開始

### 1. 生成測試 Token

```bash
cd opencode_v2
bun run generate-test-token.ts
```

輸出範例：
```
✅ Token generated successfully!

JWT Token:
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

📋 Copy-paste for curl:
export TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### 2. 測試 API

```bash
# 設定 token
export TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 測試 protected endpoint
curl http://localhost:64722/session \
  -H "Authorization: Bearer $TOKEN"

# 測試 public endpoint (不需要 token)
curl http://localhost:64722/doc
```

### 3. 執行自動化測試

```bash
cd opencode_v2
./test-jwt.sh
```

## 🔧 使用方式

### 在 Handler 中取得 User 資訊

```typescript
import { JWT } from "../auth/jwt"

app.get("/some-endpoint", async (c) => {
  // 取得已驗證的 user
  const user = JWT.getPayload(c)

  console.log(user?.userId)
  console.log(user?.username)
  console.log(user?.email)

  return c.json({ user })
})
```

### 外部系統整合

外部 auth service 應使用相同的 secret 生成 JWT：

```javascript
// Node.js 範例
import jwt from 'jsonwebtoken'

const token = jwt.sign(
  {
    userId: user.id,
    username: user.username,
    email: user.email
  },
  'pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd',
  { expiresIn: '7d' }
)
```

## 📊 架構說明

```
Client Request
     ↓
[CORS Middleware]
     ↓
[JWT Middleware] ← 檢查 Authorization header
     ↓
  ┌──────────────┐
  │ Public path? │
  └──────┬───────┘
    Yes ↓     ↓ No
  [Skip Auth] [Verify Token]
         ↓         ↓
    [Route Handler]
         ↓
    [Response]
```

### Middleware 執行順序

1. **Error Handler** - 捕捉所有錯誤 (包括 401)
2. **Logging** - 記錄請求/回應
3. **Instance Provider** - 設定工作目錄
4. **CORS** - 處理跨域請求
5. **JWT Auth** ← 新增的 middleware
   - 檢查是否為 public path
   - 驗證 JWT token
   - 設定 user context
6. **Route Handlers** - 處理實際請求

## 🔍 錯誤回應

### 401 - Missing Authorization Header
```json
{
  "message": "Authorization header missing"
}
```

### 401 - Invalid Token
```json
{
  "message": "Invalid or expired token"
}
```

### 401 - Token Verification Failed
```json
{
  "message": "Token verification failed"
}
```

## ⚙️ 自訂配置

### 新增 Public Endpoints

編輯 `src/server/server.ts:133-136`：

```typescript
const publicPaths = [
  "/doc",
  "/health",
  "/public/*",        // 新增：允許所有 /public/ 路徑
]
```

### 使用 Optional Auth

某些 endpoints 可能希望「有 token 就驗證，沒有也放行」：

```typescript
// 在特定 route 使用
app.get("/content", JWT.optionalMiddleware(), async (c) => {
  const user = JWT.getPayload(c)
  // user 可能是 undefined
})
```

### 修改 Token 過期時間

編輯 `src/auth/jwt.ts:29`：

```typescript
export async function createToken(
  payload: Payload,
  expiresIn: string = "24h"  // 改為 24 小時
)
```

## 🧪 測試情境覆蓋

測試腳本 (`test-jwt.sh`) 涵蓋：

- ✅ Public endpoint 無需 token 可訪問
- ✅ Protected endpoint 沒有 token 回傳 401
- ✅ Protected endpoint 有效 token 可訪問
- ✅ Protected endpoint 無效 token 回傳 401
- ✅ API 實際回應資料正確

## 📝 待辦事項（可選）

如果需要更完整的功能，可考慮：

- [ ] Token refresh endpoint
- [ ] Token revocation (黑名單)
- [ ] Role-based access control (RBAC)
- [ ] Rate limiting per user
- [ ] Audit logging
- [ ] Multi-tenant support

## 🔒 安全建議

1. ✅ **已實作：** 使用環境變數設定 SECRET
2. ✅ **已實作：** Token 過期機制
3. ✅ **已實作：** Bearer token 格式
4. ⚠️  **建議：** 生產環境使用 HTTPS
5. ⚠️  **建議：** 實作 token refresh
6. ⚠️  **建議：** 記錄失敗的驗證嘗試

## 📚 相關文件

- [JWT-AUTHENTICATION.md](opencode_v2/JWT-AUTHENTICATION.md) - 完整使用指南
- [opencode-agent-analysis.md](opencode-agent-analysis.md) - Agent 架構分析
- [JWT.io](https://jwt.io) - Token debugger

## 💡 常見問題

**Q: 如何暫時停用 JWT 驗證？**

註解掉 `src/server/server.ts` 第 130-147 行的 JWT middleware。

**Q: Token 過期了怎麼辦？**

重新生成一個新的 token：
```bash
bun run generate-test-token.ts
```

**Q: 如何在前端儲存 token？**

```javascript
// 儲存
localStorage.setItem('token', response.token)

// 使用
fetch(url, {
  headers: {
    'Authorization': `Bearer ${localStorage.getItem('token')}`
  }
})
```

**Q: 如何驗證 token 是否有效？**

使用 [jwt.io](https://jwt.io) 或：

```typescript
import { JWT } from "./src/auth/jwt"

try {
  const payload = await JWT.verifyToken(token)
  console.log("Valid:", payload)
} catch (e) {
  console.log("Invalid token")
}
```

## ✨ 完成！

JWT authentication 已成功整合到 OpenCode Server。所有 API endpoints（除了 `/doc` 和 `/health`）現在都需要有效的 JWT token 才能訪問。
