#!/bin/bash
# ============================================================================
# B2B Phase 1 Test Runner
# Run all tests for B2B Workplace Wellness infrastructure
# ============================================================================

set -e

echo "=============================================="
echo "B2B Phase 1: Core Infrastructure Tests"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Get database URL from environment or use local default
DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:54322/postgres}"
SUPABASE_URL="${SUPABASE_URL:-http://localhost:54321}"

echo "Using DATABASE_URL: ${DATABASE_URL:0:30}..."
echo "Using SUPABASE_URL: $SUPABASE_URL"
echo ""

# ============================================================================
# SQL SCHEMA TESTS
# ============================================================================
echo "=============================================="
echo "Running SQL Schema Tests..."
echo "=============================================="

run_sql_test() {
    local test_file=$1
    local test_name=$2
    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    echo -n "  Running $test_name... "

    if psql "$DATABASE_URL" -f "$test_file" > /tmp/test_output.txt 2>&1; then
        if grep -q "FAIL" /tmp/test_output.txt; then
            echo -e "${RED}FAIL${NC}"
            grep "FAIL" /tmp/test_output.txt
            FAILED_SUITES=$((FAILED_SUITES + 1))
        else
            echo -e "${GREEN}PASS${NC}"
            PASSED_SUITES=$((PASSED_SUITES + 1))
        fi
    else
        echo -e "${RED}ERROR${NC}"
        cat /tmp/test_output.txt
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
}

# Run SQL tests
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_sql_test "$SCRIPT_DIR/test_organizations_schema.sql" "Schema Tests"
run_sql_test "$SCRIPT_DIR/test_rls_forbidden_tables.sql" "RLS Policy Tests"
run_sql_test "$SCRIPT_DIR/test_saml_replay_prevention.sql" "SAML Replay Prevention Tests"
run_sql_test "$SCRIPT_DIR/test_metrics_privacy_threshold.sql" "Metrics Privacy Threshold Tests"

echo ""

# ============================================================================
# EDGE FUNCTION TESTS (Deno)
# ============================================================================
echo "=============================================="
echo "Running Edge Function Tests..."
echo "=============================================="

run_deno_test() {
    local test_file=$1
    local test_name=$2
    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    echo -n "  Running $test_name... "

    if deno test --allow-net --allow-env "$test_file" > /tmp/deno_output.txt 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        echo -e "${RED}FAIL${NC}"
        tail -20 /tmp/deno_output.txt
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
}

FUNCTIONS_DIR="$(dirname "$SCRIPT_DIR")/functions"

run_deno_test "$FUNCTIONS_DIR/validate-invite-code/test.ts" "Invite Code Validation Tests"
run_deno_test "$FUNCTIONS_DIR/join-organization/test.ts" "Join Organization Tests"
run_deno_test "$FUNCTIONS_DIR/b2b-stripe-webhook/test.ts" "Stripe Webhook Tests"

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "=============================================="
echo "TEST SUMMARY"
echo "=============================================="
echo ""
echo "Total Test Suites: $TOTAL_SUITES"
echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
echo -e "Failed: ${RED}$FAILED_SUITES${NC}"
echo ""

if [ $FAILED_SUITES -eq 0 ]; then
    echo -e "${GREEN}ALL TESTS PASSED!${NC}"
    echo "Phase 1 implementation is complete."
    exit 0
else
    echo -e "${YELLOW}NOTE: $FAILED_SUITES test suite(s) failed.${NC}"
    echo "This is EXPECTED if Phase 1 has not been implemented yet."
    echo ""
    echo "To complete Phase 1, implement:"
    echo "  1. Database migration with all 9 B2B tables"
    echo "  2. RLS policies for privacy protection"
    echo "  3. validate-invite-code Edge Function"
    echo "  4. join-organization Edge Function"
    echo "  5. b2b-stripe-webhook Edge Function"
    exit 1
fi
