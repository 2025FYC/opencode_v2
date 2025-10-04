import { createMiddleware } from "hono/factory"
import { sign, verify } from "hono/jwt"
import type { JWTPayload } from "hono/utils/jwt/types"
import { HTTPException } from "hono/http-exception"

export namespace JWT {
  // JWT Secret - 可以透過環境變數覆蓋
  export const SECRET =
    process.env.JWT_SECRET || "pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd"

  export interface Payload extends JWTPayload {
    userId?: string
    username?: string
    email?: string
    [key: string]: any
  }

  /**
   * 驗證 JWT token
   */
  export async function verifyToken(token: string): Promise<Payload> {
    try {
      const payload = await verify(token, SECRET)
      return payload as Payload
    } catch (error) {
      throw new HTTPException(401, { message: "Invalid or expired token" })
    }
  }

  /**
   * 生成 JWT token (可選，如果需要 server 端生成 token)
   */
  export async function createToken(payload: Payload, expiresIn: string = "7d"): Promise<string> {
    const now = Math.floor(Date.now() / 1000)
    const exp = now + parseExpiration(expiresIn)

    return await sign(
      {
        ...payload,
        iat: now,
        exp,
      },
      SECRET,
    )
  }

  /**
   * Hono middleware for JWT authentication
   *
   * 使用方式：
   * app.use('/protected/*', JWT.middleware())
   */
  export function middleware() {
    return createMiddleware(async (c, next) => {
      const authHeader = c.req.header("Authorization")

      if (!authHeader) {
        throw new HTTPException(401, { message: "Authorization header missing" })
      }

      // 支援 "Bearer <token>" 格式
      const token = authHeader.startsWith("Bearer ")
        ? authHeader.substring(7)
        : authHeader

      try {
        const payload = await verifyToken(token)

        // 將 payload 儲存到 context 中，後續 handler 可以使用
        c.set("jwtPayload", payload)

        await next()
      } catch (error) {
        if (error instanceof HTTPException) {
          throw error
        }
        throw new HTTPException(401, { message: "Token verification failed" })
      }
    })
  }

  /**
   * Optional middleware - 如果有 token 就驗證，沒有也放行
   */
  export function optionalMiddleware() {
    return createMiddleware(async (c, next) => {
      const authHeader = c.req.header("Authorization")

      if (authHeader) {
        const token = authHeader.startsWith("Bearer ")
          ? authHeader.substring(7)
          : authHeader

        try {
          const payload = await verifyToken(token)
          c.set("jwtPayload", payload)
        } catch {
          // Token 無效但不阻擋請求
        }
      }

      await next()
    })
  }

  /**
   * 從 context 取得 JWT payload
   */
  export function getPayload(c: any): Payload | undefined {
    return c.get("jwtPayload")
  }

  /**
   * Helper: 解析過期時間字串
   */
  function parseExpiration(exp: string): number {
    const unit = exp.slice(-1)
    const value = parseInt(exp.slice(0, -1))

    switch (unit) {
      case "s":
        return value
      case "m":
        return value * 60
      case "h":
        return value * 60 * 60
      case "d":
        return value * 60 * 60 * 24
      default:
        return 60 * 60 * 24 * 7 // 預設 7 天
    }
  }
}