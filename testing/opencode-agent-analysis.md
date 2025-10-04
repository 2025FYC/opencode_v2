# OpenCode Agent 與 Session 架構分析

## 目錄
- [Agent 實作架構](#agent-實作架構)
- [Session/Message 記憶機制](#sessionmessage-記憶機制)
- [Storage 配置](#storage-配置)
- [Auth 配置](#auth-配置)

---

## Agent 實作架構

### 1. Agent 核心定義
**位置：** `src/agent/agent.ts`

Agent 使用 **namespace** 模式組織，內建三種類型：

```typescript
{
  general: {
    mode: "subagent",
    description: "複雜查詢、程式碼搜尋、多步驟任務",
    permission: { edit: "allow", bash: "*:allow", webfetch: "allow" },
    tools: { todoread: false, todowrite: false }
  },
  build: {
    mode: "primary",
    permission: { edit: "allow", bash: "*:allow", webfetch: "allow" }
  },
  plan: {
    mode: "primary",
    permission: { edit: "deny", bash: "ask", webfetch: "allow" }
  }
}
```

### 2. Agent 資料結構

```typescript
Agent.Info {
  name: string
  description?: string
  mode: "subagent" | "primary" | "all"
  builtIn: boolean

  // 模型配置
  model?: { modelID: string, providerID: string }
  topP?: number
  temperature?: number

  // 權限控制
  permission: {
    edit: "allow" | "deny" | "ask"
    bash: Record<string, Permission>
    webfetch?: Permission
  }

  // 工具與選項
  prompt?: string
  tools: Record<string, boolean>
  options: Record<string, any>
}
```

### 3. Agent 狀態管理

**實作方式：**
- 使用 `Instance.state()` 管理全局 agent 狀態
- 從 `Config.get()` 動態載入配置
- 支援用戶自定義 agent 覆蓋內建設定

**權限合併策略：**
```typescript
mergeAgentPermissions(basePermission, overridePermission)
// 1. 合併 bash 權限（支援 string | object）
// 2. 預設值：edit="allow", webfetch="allow"
// 3. granular permissions 預設為 "ask"
```

### 4. 如何自定義 Agent

**修改位置：** 專案根目錄 `opencode.json`

```json
{
  "agent": {
    "my-custom-agent": {
      "description": "自訂 Agent 描述",
      "mode": "all",
      "model": "anthropic:claude-3-5-sonnet-20241022",
      "temperature": 0.7,
      "top_p": 0.9,
      "prompt": "你是一個專門的助手...",
      "tools": {
        "bash": true,
        "read": true,
        "write": false
      },
      "permission": {
        "edit": "ask",
        "bash": {
          "git *": "allow",
          "rm *": "deny",
          "*": "ask"
        }
      }
    }
  }
}
```

---

## Session/Message 記憶機制

### 1. 資料階層架構

```
Session (會話層)
  ├─ MessageV2.Info (訊息元資料)
  └─ MessageV2.Part[] (訊息片段)
       ├─ TextPart
       ├─ ToolPart (工具呼叫)
       ├─ FilePart (檔案)
       ├─ ReasoningPart (推理過程)
       ├─ SnapshotPart (快照)
       └─ PatchPart (變更記錄)
```

### 2. Session 資料結構

**位置：** `src/session/index.ts`

```typescript
Session.Info {
  id: string                    // 降序 ID (Identifier.descending)
  projectID: string
  directory: string
  parentID?: string             // 支援子 session
  title: string
  version: string

  time: {
    created: number
    updated: number
    compacting?: number         // 壓縮時間
  }

  share?: {
    url: string                 // 分享連結
  }

  revert?: {                    // 回退資訊
    messageID: string
    partID?: string
    snapshot?: string
    diff?: string
  }
}
```

### 3. Message 版本化系統

**位置：** `src/session/message-v2.ts`

#### User Message
```typescript
{
  role: "user",
  id: string,
  sessionID: string,
  time: { created: number }
}
```

#### Assistant Message
```typescript
{
  role: "assistant",
  id: string,
  sessionID: string,

  // 執行環境
  system: string[]
  modelID: string
  providerID: string
  mode: string                  // agent 名稱
  path: { cwd: string, root: string }

  // 資源使用
  cost: number
  tokens: {
    input: number
    output: number
    reasoning: number
    cache: { read: number, write: number }
  }

  // 狀態
  time: { created: number, completed?: number }
  error?: ErrorInfo
  summary?: boolean             // 是否為摘要訊息
}
```

### 4. Part 狀態管理

**ToolPart 狀態機：**
```
pending → running → completed
                 → error
```

**實作範例：**
```typescript
ToolPart {
  type: "tool",
  callID: string,
  tool: string,
  state: {
    status: "pending" | "running" | "completed" | "error",
    input?: any,
    output?: string,
    title?: string,
    metadata?: any,
    time: { start: number, end?: number }
  }
}
```

### 5. 記憶管理策略

**位置：** `src/session/prompt.ts`

#### Context 壓縮機制

```typescript
// 1. 過濾已摘要的訊息
MessageV2.filterSummarized(msgs)
// → 只保留最後一個 summary 之後的訊息

// 2. 檢查 token 是否溢出
SessionCompaction.isOverflow({
  tokens: lastAssistant.info.tokens,
  model: model.info
})

// 3. 觸發壓縮
await SessionCompaction.run({
  sessionID,
  providerID,
  modelID
})
// → 生成 summary message
// → 清除舊訊息的 tool output
```

#### 訊息處理流程

```typescript
async function prompt(input: PromptInput) {
  // 1. 建立 User Message
  const userMsg = await createUserMessage(input)

  // 2. 鎖定 Session (防止並行)
  using abort = lock(sessionID)

  // 3. 載入歷史訊息
  let msgs = await getMessages({ sessionID })

  // 4. Stream 處理
  while (true) {
    const stream = streamText({ messages: msgs, tools })

    // 5. 即時更新 Part 狀態
    for await (const value of stream.fullStream) {
      switch (value.type) {
        case "text-delta":
          currentText.text += value.text
          await Session.updatePart(currentText)
          break
        case "tool-call":
          toolPart.state = { status: "running", ... }
          await Session.updatePart(toolPart)
          break
      }
    }

    // 6. 檢查是否需要繼續
    if (finishReason !== "tool-calls") break
  }

  // 7. 釋放鎖定
  // using 自動呼叫 [Symbol.dispose]()
}
```

### 6. Queue 系統

**並行請求處理：**
```typescript
// Session busy 時將請求加入 queue
if (isBusy(sessionID)) {
  return new Promise((resolve) => {
    state().queued.get(sessionID).push({
      messageID: userMsg.info.id,
      callback: resolve
    })
  })
}

// 處理完成後執行 queue
for (const item of queued) {
  item.callback(result)
}
```

### 7. 事件驅動更新

**位置：** `src/session/index.ts`, `src/session/message-v2.ts`

```typescript
// Session 事件
Bus.publish(Session.Event.Updated, { info: session })
Bus.publish(Session.Event.Deleted, { info: session })
Bus.publish(Session.Event.Error, { sessionID, error })

// Message 事件
Bus.publish(MessageV2.Event.Updated, { info: msg })
Bus.publish(MessageV2.Event.PartUpdated, { part })
Bus.publish(MessageV2.Event.Removed, { sessionID, messageID })
```

---

## Storage 配置

### 1. Storage 架構

**位置：** `src/storage/storage.ts`

#### 儲存路徑結構
```
Global.Path.data/storage/
  ├─ session/{projectID}/{sessionID}.json
  ├─ message/{sessionID}/{messageID}.json
  ├─ part/{messageID}/{partID}.json
  ├─ project/{projectID}.json
  └─ share/{sessionID}.json
```

#### Key-based 存取模式
```typescript
// 讀取
await Storage.read<T>(["message", sessionID, messageID])
// → ${data}/storage/message/${sessionID}/${messageID}.json

// 寫入
await Storage.write(["part", messageID, partID], part)

// 更新 (帶鎖)
await Storage.update<T>(key, (draft) => { draft.foo = "bar" })

// 列表
await Storage.list(["message", sessionID])
// → 回傳所有 messageID
```

### 2. 預設儲存位置

**位置：** `src/global/index.ts`

```typescript
import { xdgData, xdgCache, xdgConfig, xdgState } from "xdg-basedir"

Global.Path = {
  data:   `${xdgData}/opencode`,      // 主要資料
  cache:  `${xdgCache}/opencode`,     // 快取
  config: `${xdgConfig}/opencode`,    // 設定
  state:  `${xdgState}/opencode`,     // 狀態
  log:    `${xdgData}/opencode/log`,
  bin:    `${xdgData}/opencode/bin`
}
```

#### 平台對應路徑

| 平台 | data | config | cache |
|------|------|--------|-------|
| **Linux** | `~/.local/share/opencode` | `~/.config/opencode` | `~/.cache/opencode` |
| **macOS** | `~/Library/Application Support/opencode` | `~/Library/Preferences/opencode` | `~/Library/Caches/opencode` |
| **Windows** | `%LOCALAPPDATA%\opencode` | `%APPDATA%\opencode` | `%TEMP%\opencode` |

### 3. 如何修改 Storage 路徑

#### 方法 1: 環境變數覆蓋 (推薦)
```bash
# Linux/macOS
export XDG_DATA_HOME="/custom/data/path"
export XDG_CONFIG_HOME="/custom/config/path"
export XDG_CACHE_HOME="/custom/cache/path"

# 啟動 OpenCode
opencode
```

#### 方法 2: 修改程式碼
**檔案：** `src/global/index.ts`

```typescript
// 替換為自訂路徑
const data = "/your/custom/data/path"
const cache = "/your/custom/cache/path"
const config = "/your/custom/config/path"

export namespace Global {
  export const Path = {
    data,
    bin: path.join(data, "bin"),
    log: path.join(data, "log"),
    cache,
    config,
    state: "/your/custom/state/path"
  } as const
}
```

#### 方法 3: 符號連結
```bash
# 將預設路徑連結到自訂位置
ln -s /your/custom/storage ~/.local/share/opencode
```

### 4. Migration 系統

Storage 包含版本遷移機制：

```typescript
const MIGRATIONS: Migration[] = [
  async (dir) => {
    // Migration 0: 從舊格式轉換到新格式
    // 自動將 storage/session/info/* 移動到 session/*
  }
]

// 遷移狀態記錄在
// ${data}/storage/migration
```

### 5. Lock 機制

Storage 使用檔案鎖避免競爭條件：

```typescript
// 讀取鎖 (共享)
using _ = await Lock.read(target)

// 寫入鎖 (獨占)
using _ = await Lock.write("storage")
```

---

## Auth 配置

### 1. Auth 架構

**位置：** `src/auth/index.ts`

#### 認證類型

```typescript
Auth.Info =
  | { type: "oauth", refresh: string, access: string, expires: number }
  | { type: "api", key: string }
  | { type: "wellknown", key: string, token: string }
```

### 2. 預設儲存位置

**檔案：** `${Global.Path.data}/auth.json`

```json
{
  "anthropic": {
    "type": "api",
    "key": "sk-ant-..."
  },
  "openai": {
    "type": "oauth",
    "refresh": "...",
    "access": "...",
    "expires": 1234567890
  },
  "github-copilot": {
    "type": "oauth",
    "refresh": "ghu_...",
    "access": "gho_...",
    "expires": 1234567890
  }
}
```

**權限：** 檔案自動設為 `0o600` (僅擁有者可讀寫)

### 3. 如何修改 Auth 路徑

#### 方法 1: 修改程式碼
**檔案：** `src/auth/index.ts:34`

```typescript
// 原始
const filepath = path.join(Global.Path.data, "auth.json")

// 自訂
const filepath = "/your/custom/path/credentials.json"
```

#### 方法 2: 環境變數 (需自行實作)

在 `src/auth/index.ts` 加入：

```typescript
const filepath = process.env.OPENCODE_AUTH_FILE
  || path.join(Global.Path.data, "auth.json")
```

使用：
```bash
export OPENCODE_AUTH_FILE="/secure/vault/opencode-auth.json"
opencode
```

### 4. CLI 管理指令

**位置：** `src/cli/cmd/auth.ts`

```bash
# 列出所有認證
opencode auth list

# 登入 provider
opencode auth login

# 登出
opencode auth logout

# 使用 wellknown endpoint
opencode auth login https://your-auth-server.com
```

### 5. 支援的 Provider

#### 內建優先順序
```typescript
{
  opencode: 0,         // 推薦
  anthropic: 1,        // 推薦
  "github-copilot": 2,
  openai: 3,
  google: 4,
  openrouter: 5,
  vercel: 6
}
```

#### 環境變數優先級
Auth 會優先檢查環境變數，例如：
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `AWS_BEARER_TOKEN_BEDROCK`
- `GITHUB_TOKEN`

**實作位置：** `src/cli/cmd/auth.ts:41-64`

### 6. OAuth 流程

**位置：** `src/cli/cmd/auth.ts:159-226`

```typescript
// 1. Plugin 提供 OAuth 方法
const plugin = await Plugin.list()
  .then(x => x.find(x => x.auth?.provider === provider))

// 2. 取得授權 URL
const authorize = await method.authorize()
// → { url: "...", method: "auto" | "code" }

// 3. 等待 callback
const result = await authorize.callback(code)

// 4. 儲存 token
if (result.type === "success") {
  await Auth.set(provider, {
    type: "oauth",
    refresh: result.refresh,
    access: result.access,
    expires: result.expires
  })
}
```

### 7. 安全性考量

1. **檔案權限：** auth.json 自動設為 `0o600`
2. **敏感資訊：** 密碼輸入使用 `prompts.password()` (不顯示)
3. **Token 刷新：** OAuth 支援自動刷新機制
4. **環境隔離：** 每個 provider 獨立儲存

### 8. 自訂 Auth Provider

**修改 `opencode.json`：**

```json
{
  "provider": {
    "my-llm": {
      "type": "openai",
      "baseURL": "https://api.my-llm.com/v1",
      "models": {
        "my-model": {
          "id": "my-model-v1",
          "input": 0.001,
          "output": 0.002
        }
      }
    }
  }
}
```

**登入：**
```bash
opencode auth login
# 選擇 "Other"
# 輸入 provider id: my-llm
# 輸入 API key
```

---

## 附錄：相關檔案索引

### Agent 相關
- `src/agent/agent.ts` - Agent 定義與管理
- `src/agent/generate.txt` - Agent 生成提示詞

### Session/Message 相關
- `src/session/index.ts` - Session 管理
- `src/session/message.ts` - Message v1 (舊版)
- `src/session/message-v2.ts` - Message v2 (新版)
- `src/session/prompt.ts` - 提示處理與 streaming
- `src/session/compaction.ts` - Context 壓縮
- `src/session/revert.ts` - 回退機制
- `src/session/system.ts` - System prompt

### Storage 相關
- `src/storage/storage.ts` - 儲存層實作
- `src/global/index.ts` - 全局路徑配置
- `src/util/lock.ts` - 檔案鎖

### Auth 相關
- `src/auth/index.ts` - 認證核心
- `src/auth/github-copilot.ts` - GitHub Copilot OAuth
- `src/cli/cmd/auth.ts` - CLI 認證指令

---

## 快速參考

### 修改 Storage 路徑
```bash
export XDG_DATA_HOME="/my/data"
```

### 修改 Auth 檔案
編輯 `src/auth/index.ts:34`

### 自訂 Agent
編輯 `opencode.json` 的 `agent` 欄位

### 清除快取
```bash
rm -rf ~/.cache/opencode
# 或
rm -rf ~/Library/Caches/opencode  # macOS
```

### 備份 Session
```bash
cp -r ~/.local/share/opencode/storage ~/backup/
```
