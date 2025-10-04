#!/usr/bin/env bun
/**
 * JWT Token Generator for Testing
 *
 * Usage:
 *   bun run generate-test-token.ts
 *   bun run generate-test-token.ts --userId=custom-id --username=john
 */

import { sign } from "hono/jwt"

const SECRET = process.env.JWT_SECRET || "pR4wE_f5o2lVX97Qh1L3z8DgHYmKu6aC0wBJqxn2S9tFzM1kN4vU7rGpOeZiAbEd"

// Parse command line arguments
const args = process.argv.slice(2)
const options: Record<string, string> = {}

for (const arg of args) {
  const match = arg.match(/^--(\w+)=(.+)$/)
  if (match) {
    options[match[1]] = match[2]
  }
}

// Default payload
const payload = {
  userId: options.userId || "test-user-123",
  username: options.username || "testuser",
  email: options.email || "test@example.com",
  iat: Math.floor(Date.now() / 1000),
  exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 7, // 7 days
}

console.log("🔐 Generating JWT Token...\n")
console.log("Payload:")
console.log(JSON.stringify(payload, null, 2))
console.log()

const token = await sign(payload, SECRET)

console.log("✅ Token generated successfully!\n")
console.log("JWT Token:")
console.log(token)
console.log()
console.log("📋 Copy-paste for curl:")
console.log(`export TOKEN="${token}"`)
console.log()
console.log("🧪 Test with:")
console.log(`curl http://localhost:64722/session -H "Authorization: Bearer $TOKEN"`)
console.log()
console.log("🔍 Decode at: https://jwt.io")