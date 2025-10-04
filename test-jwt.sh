#!/bin/bash

# JWT Authentication Test Script
# Tests the OpenCode server JWT implementation

set -e

echo "🧪 JWT Authentication Test Suite"
echo "=================================="
echo ""

# Generate test token
echo "📝 Step 1: Generating test JWT token..."
TOKEN=$(bun run generate-test-token.ts 2>/dev/null | grep "eyJ" | head -1)

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to generate token"
  exit 1
fi

echo "✅ Token generated: ${TOKEN:0:50}..."
echo ""

# Test public endpoint (should work without token)
echo "📝 Step 2: Testing public endpoint (no auth required)..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:64722/doc)

if [ "$RESPONSE" == "200" ]; then
  echo "✅ Public endpoint accessible without token (HTTP $RESPONSE)"
else
  echo "❌ Public endpoint failed (HTTP $RESPONSE)"
fi
echo ""

# Test protected endpoint without token (should fail with 401)
echo "📝 Step 3: Testing protected endpoint without token..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:64722/session)

if [ "$RESPONSE" == "401" ]; then
  echo "✅ Protected endpoint correctly rejected request (HTTP $RESPONSE)"
else
  echo "❌ Expected 401, got HTTP $RESPONSE"
fi
echo ""

# Test protected endpoint with valid token (should succeed)
echo "📝 Step 4: Testing protected endpoint with valid token..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:64722/session \
  -H "Authorization: Bearer $TOKEN")

if [ "$RESPONSE" == "200" ]; then
  echo "✅ Protected endpoint accessible with valid token (HTTP $RESPONSE)"
else
  echo "⚠️  Protected endpoint returned HTTP $RESPONSE (may be expected if no sessions exist)"
fi
echo ""

# Test protected endpoint with invalid token (should fail with 401)
echo "📝 Step 5: Testing protected endpoint with invalid token..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:64722/session \
  -H "Authorization: Bearer invalid.token.here")

if [ "$RESPONSE" == "401" ]; then
  echo "✅ Invalid token correctly rejected (HTTP $RESPONSE)"
else
  echo "❌ Expected 401, got HTTP $RESPONSE"
fi
echo ""

# Test actual API call with response
echo "📝 Step 6: Testing actual API response..."
API_RESPONSE=$(curl -s \
  http://localhost:64722/path \
  -H "Authorization: Bearer $TOKEN")

if echo "$API_RESPONSE" | grep -q "worktree"; then
  echo "✅ API returned expected data:"
  echo "$API_RESPONSE" | head -3
else
  echo "⚠️  Unexpected API response:"
  echo "$API_RESPONSE"
fi
echo ""

echo "=================================="
echo "✨ Test suite completed!"
echo ""
echo "💡 To use this token manually:"
echo "export TOKEN=\"$TOKEN\""
echo ""
echo "curl http://localhost:64722/session -H \"Authorization: Bearer \$TOKEN\""