#!/bin/bash

# B2B Phase 1: Test Setup and Execution Script
# Sets up test data and runs all Phase 1 tests

set -e

echo "🔧 Setting up B2B Phase 1 test environment..."

# Configuration
SUPABASE_URL="http://127.0.0.1:54321"
SUPABASE_ANON_KEY=$(supabase status --output json | jq -r '.anon_key')
TEST_EMAIL="test@example.com"
TEST_PASSWORD="TestPassword123!"

echo "📝 Creating test user..."

# Create test user (will fail if already exists, that's okay)
curl -s -X POST "${SUPABASE_URL}/auth/v1/signup" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${TEST_EMAIL}\",\"password\":\"${TEST_PASSWORD}\"}" \
  > /dev/null 2>&1 || echo "  (User may already exist)"

echo "🗄️  Seeding test data..."

# Run seed script
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -f supabase/seed_b2b_test_data.sql \
  -q

echo "✅ Test environment ready!"
echo ""
echo "🧪 Running Phase 1 tests..."
echo ""

# Set environment variables for tests
export SUPABASE_URL
export SUPABASE_ANON_KEY

# Track test results
FAILED_TESTS=0

# Run validate-invite-code tests
echo "📋 Testing validate-invite-code Edge Function..."
if deno test --allow-net --allow-env supabase/functions/validate-invite-code/test.ts; then
  echo "✅ validate-invite-code tests passed"
else
  echo "❌ validate-invite-code tests failed"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
echo ""

# Run join-organization tests
echo "📋 Testing join-organization Edge Function..."
if deno test --allow-net --allow-env supabase/functions/join-organization/test.ts; then
  echo "✅ join-organization tests passed"
else
  echo "❌ join-organization tests failed"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAILED_TESTS -eq 0 ]; then
  echo "🎉 All Edge Function tests passed!"
else
  echo "⚠️  $FAILED_TESTS test suite(s) failed"
  exit 1
fi
