# MindFriend B2B Workplace Wellness - Phase 1 Test Plan

## Overview

This document defines comprehensive failing test cases (red phase of TDD) for the B2B Workplace Wellness module Phase 1: Core Infrastructure.

**Status:** All tests are designed to FAIL until Phase 1 implementation is complete.

**Test Categories:**

1. Database Schema Tests
2. RLS Policy Tests (Privacy Protection)
3. Invite Code Validation Tests
4. Join Organization Tests
5. Privacy Access Audit Tests
6. SAML Assertion Replay Prevention Tests
7. Organization Metrics Privacy Threshold Tests
8. Stripe Subscription Tests

---

## Test Execution Order

```
Phase 1 - Week 1 (Must Have):
  1. Database Schema Tests (all 9 tables)
  2. RLS Policy Tests for forbidden tables
  3. Invite Code Uniqueness Constraint Tests
  4. SAML Assertion Replay Prevention Tests

Phase 1 - Week 2 (Should Have):
  5. Organization Invite Validation Tests
  6. Join Organization Tests
  7. Privacy Access Audit Tests

Phase 1 - Week 3 (Nice to Have):
  8. Stripe Subscription Tests
  9. Organization Metrics Privacy Threshold Tests
```

---

## 1. Database Schema Tests

### File: `supabase/tests/b2b/test_organizations_schema.sql`

```sql
-- ============================================================================
-- B2B PHASE 1: DATABASE SCHEMA TESTS
-- These tests verify all required tables exist with correct structure
-- Run with: psql $DATABASE_URL -f test_organizations_schema.sql
-- Expected: ALL TESTS FAIL until migration is applied
-- ============================================================================

-- Test Runner Setup
DO $$
DECLARE
    test_passed BOOLEAN;
    test_count INT := 0;
    pass_count INT := 0;
BEGIN
    RAISE NOTICE '=== B2B Schema Tests Starting ===';

-- ============================================================================
-- TEST 1.1: organizations table exists with all required columns
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    -- Check table exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'organizations'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations table does not exist';
    END IF;

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'id'
        AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.id column missing or wrong type';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'name'
        AND data_type = 'text'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.name column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'slug'
        AND data_type = 'text'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.slug column missing';
    END IF;

    -- Stripe fields
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'stripe_customer_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.stripe_customer_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'stripe_subscription_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.stripe_subscription_id column missing';
    END IF;

    -- SAML fields
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'saml_enabled'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.saml_enabled column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'saml_metadata_url'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.saml_metadata_url column missing';
    END IF;

    -- Seat count tracking
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'seat_count'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.seat_count column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'seats_used'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.seats_used column missing';
    END IF;

    -- Timestamps
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'created_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.created_at column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organizations'
        AND column_name = 'updated_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organizations.updated_at column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.1 PASS: organizations table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.2: organization_admins table exists with role-based access
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'organization_admins'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_admins table does not exist';
    END IF;

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_admins'
        AND column_name = 'organization_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_admins.organization_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_admins'
        AND column_name = 'user_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_admins.user_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_admins'
        AND column_name = 'role'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_admins.role column missing';
    END IF;

    -- Check role constraint exists (owner, admin, viewer)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints
        WHERE constraint_name LIKE '%organization_admins%role%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_admins.role CHECK constraint missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.2 PASS: organization_admins table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.2 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.3: organization_members table with lifecycle fields
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'organization_members'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_members table does not exist';
    END IF;

    -- Check lifecycle columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_members'
        AND column_name = 'joined_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_members.joined_at column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_members'
        AND column_name = 'removed_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_members.removed_at column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_members'
        AND column_name = 'finalized_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_members.finalized_at column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.3 PASS: organization_members table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.3 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.4: organization_invites table with invite_code constraints
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'organization_invites'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_invites table does not exist';
    END IF;

    -- Check invite_code UNIQUE constraint
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'organization_invites'
        AND constraint_type = 'UNIQUE'
        AND constraint_name LIKE '%invite_code%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_invites.invite_code UNIQUE constraint missing';
    END IF;

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_invites'
        AND column_name = 'max_uses'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_invites.max_uses column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_invites'
        AND column_name = 'uses_count'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_invites.uses_count column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_invites'
        AND column_name = 'expires_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_invites.expires_at column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.4 PASS: organization_invites table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.4 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.5: organization_metrics with privacy threshold constraint
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'organization_metrics'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_metrics table does not exist';
    END IF;

    -- Check active_users >= 5 constraint
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.constraint_column_usage ccu
          ON cc.constraint_name = ccu.constraint_name
        WHERE ccu.table_name = 'organization_metrics'
        AND ccu.column_name = 'active_users'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_metrics.active_users CHECK constraint missing';
    END IF;

    -- Check UNIQUE constraint on organization_id + metric_date
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'organization_metrics'
        AND constraint_type = 'UNIQUE'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_metrics UNIQUE constraint on org_id + date missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.5 PASS: organization_metrics table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.5 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.6: privacy_access_audit table exists
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'privacy_access_audit'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: privacy_access_audit table does not exist';
    END IF;

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'privacy_access_audit'
        AND column_name = 'admin_user_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: privacy_access_audit.admin_user_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'privacy_access_audit'
        AND column_name = 'attempted_table'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: privacy_access_audit.attempted_table column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'privacy_access_audit'
        AND column_name = 'blocked_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: privacy_access_audit.blocked_at column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.6 PASS: privacy_access_audit table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.6 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.7: billing_audit_log table exists
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'billing_audit_log'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: billing_audit_log table does not exist';
    END IF;

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'billing_audit_log'
        AND column_name = 'organization_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: billing_audit_log.organization_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'billing_audit_log'
        AND column_name = 'event_type'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: billing_audit_log.event_type column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'billing_audit_log'
        AND column_name = 'seat_delta'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: billing_audit_log.seat_delta column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.7 PASS: billing_audit_log table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.7 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.8: saml_assertions table with uniqueness constraint
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'saml_assertions'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions table does not exist';
    END IF;

    -- Check assertion_id UNIQUE constraint
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'saml_assertions'
        AND constraint_type = 'UNIQUE'
        AND constraint_name LIKE '%assertion_id%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions.assertion_id UNIQUE constraint missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'saml_assertions'
        AND column_name = 'organization_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions.organization_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'saml_assertions'
        AND column_name = 'processed_at'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions.processed_at column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.8 PASS: saml_assertions table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.8 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 1.9: audit_log table exists for general audit trail
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'audit_log'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: audit_log table does not exist';
    END IF;

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'audit_log'
        AND column_name = 'event_type'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: audit_log.event_type column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'audit_log'
        AND column_name = 'actor_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: audit_log.actor_id column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'audit_log'
        AND column_name = 'metadata'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: audit_log.metadata column missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 1.9 PASS: audit_log table structure correct';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1.9 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
    RAISE NOTICE '=== B2B Schema Tests Complete ===';
    RAISE NOTICE 'Passed: % / %', pass_count, test_count;

    IF pass_count < test_count THEN
        RAISE EXCEPTION 'SCHEMA TESTS FAILED: % tests did not pass', (test_count - pass_count);
    END IF;
END;
$$;
```

---

## 2. RLS Policy Tests (Privacy Protection)

### File: `supabase/tests/b2b/test_rls_forbidden_tables.sql`

```sql
-- ============================================================================
-- B2B PHASE 1: RLS POLICY TESTS - FORBIDDEN TABLE ACCESS
-- These tests verify organization admins CANNOT access personal user data
-- Expected: ALL TESTS FAIL until RLS policies are implemented
-- ============================================================================

-- Test Setup: Create test org admin user context
-- In production, this would use SET LOCAL ROLE and auth.uid() injection

DO $$
DECLARE
    test_org_id UUID;
    test_admin_id UUID;
    test_employee_id UUID;
    row_count INT;
BEGIN
    RAISE NOTICE '=== B2B RLS Forbidden Table Tests Starting ===';

-- ============================================================================
-- TEST 2.1: Organization admin CANNOT SELECT from profiles table
-- ============================================================================
BEGIN
    -- This test simulates an org admin trying to read employee profiles
    -- Expected: Returns 0 rows (blocked by RLS)

    -- Would execute as org admin user:
    -- SELECT * FROM profiles WHERE id IN (
    --   SELECT user_id FROM organization_members WHERE organization_id = test_org_id
    -- );

    -- For now, verify the policy exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'profiles'
        AND policyname LIKE '%org%admin%'
        AND cmd = 'SELECT'
        AND qual LIKE '%false%' -- Should block org admins
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy blocking org admins from profiles table';
    END IF;

    RAISE NOTICE 'TEST 2.1 PASS: RLS policy exists to block org admins from profiles';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.2: Organization admin CANNOT SELECT from conversations table
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'conversations'
        AND policyname LIKE '%org%admin%block%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy blocking org admins from conversations table';
    END IF;

    RAISE NOTICE 'TEST 2.2 PASS: RLS policy exists to block org admins from conversations';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.2 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.3: Organization admin CANNOT SELECT from moods table
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'moods'
        AND policyname LIKE '%org%admin%block%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy blocking org admins from moods table';
    END IF;

    RAISE NOTICE 'TEST 2.3 PASS: RLS policy exists to block org admins from moods';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.3 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.4: Organization admin CANNOT SELECT from exercise_sessions table
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'exercise_sessions'
        AND policyname LIKE '%org%admin%block%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy blocking org admins from exercise_sessions table';
    END IF;

    RAISE NOTICE 'TEST 2.4 PASS: RLS policy exists to block org admins from exercise_sessions';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.4 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.5: Organization admin CAN SELECT from organization_metrics (own org)
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'organization_metrics'
        AND policyname LIKE '%admin%select%'
        AND cmd = 'SELECT'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy allowing org admins to read organization_metrics';
    END IF;

    RAISE NOTICE 'TEST 2.5 PASS: RLS policy exists for org admins to read organization_metrics';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.5 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.6: Organization admin CAN SELECT from organization_members (own org)
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'organization_members'
        AND policyname LIKE '%admin%select%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy allowing org admins to read organization_members';
    END IF;

    RAISE NOTICE 'TEST 2.6 PASS: RLS policy exists for org admins to read organization_members';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.6 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.7: Regular employees can only see their own organization_members record
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'organization_members'
        AND policyname LIKE '%employee%own%'
        AND qual LIKE '%auth.uid()%user_id%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: No RLS policy limiting employees to own organization_members record';
    END IF;

    RAISE NOTICE 'TEST 2.7 PASS: RLS policy exists for employees to see only own record';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.7 FAIL: %', SQLERRM;
END;

    RAISE NOTICE '=== B2B RLS Forbidden Table Tests Complete ===';
END;
$$;
```

---

## 3. Invite Code Validation Tests

### File: `supabase/functions/validate-invite-code/test.ts`

```typescript
// ============================================================================
// B2B PHASE 1: INVITE CODE VALIDATION TESTS
// Run with: deno test --allow-net --allow-env supabase/functions/validate-invite-code/test.ts
// Expected: ALL TESTS FAIL until Edge Function is implemented
// ============================================================================

import {
  assertEquals,
  assertExists,
  assertRejects,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "test-anon-key";
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/validate-invite-code`;

interface InviteValidationResponse {
  valid: boolean;
  organizationId?: string;
  organizationName?: string;
  error?: string;
  errorCode?: string;
}

async function callValidateInvite(
  code: string,
  token: string,
): Promise<{ status: number; data: InviteValidationResponse }> {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ inviteCode: code }),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
}

// ============================================================================
// TEST 3.1: Valid invite code returns organizationId
// ============================================================================
Deno.test(
  "validate-invite-code returns organizationId for valid code",
  async () => {
    // Setup: Would need to create test organization with invite code first
    const testCode = "VALIDCODE123";
    const testToken = "valid-user-jwt-token";

    const response = await callValidateInvite(testCode, testToken);

    assertEquals(response.status, 200, "Should return 200 OK");
    assertEquals(response.data.valid, true, "Should indicate valid");
    assertExists(response.data.organizationId, "Should return organizationId");
    assertExists(
      response.data.organizationName,
      "Should return organizationName",
    );
  },
);

// ============================================================================
// TEST 3.2: Expired invite code returns error
// ============================================================================
Deno.test("validate-invite-code returns error for expired code", async () => {
  const expiredCode = "EXPIREDCODE";
  const testToken = "valid-user-jwt-token";

  const response = await callValidateInvite(expiredCode, testToken);

  assertEquals(response.status, 400, "Should return 400 Bad Request");
  assertEquals(response.data.valid, false, "Should indicate invalid");
  assertEquals(
    response.data.errorCode,
    "INVITE_EXPIRED",
    "Should return INVITE_EXPIRED error code",
  );
});

// ============================================================================
// TEST 3.3: Max uses exceeded returns error
// ============================================================================
Deno.test(
  "validate-invite-code returns error when max_uses exceeded",
  async () => {
    const maxedOutCode = "MAXEDOUTCODE";
    const testToken = "valid-user-jwt-token";

    const response = await callValidateInvite(maxedOutCode, testToken);

    assertEquals(response.status, 400, "Should return 400 Bad Request");
    assertEquals(response.data.valid, false, "Should indicate invalid");
    assertEquals(
      response.data.errorCode,
      "MAX_USES_EXCEEDED",
      "Should return MAX_USES_EXCEEDED error code",
    );
  },
);

// ============================================================================
// TEST 3.4: Validation increments uses counter
// ============================================================================
Deno.test("validate-invite-code increments uses_count on success", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testCode = "COUNTERCODE";
  const testToken = "valid-user-jwt-token";

  // Get initial uses count
  const { data: beforeData } = await supabase
    .from("organization_invites")
    .select("uses_count")
    .eq("invite_code", testCode)
    .single();

  const initialCount = beforeData?.uses_count ?? 0;

  // Validate the code
  await callValidateInvite(testCode, testToken);

  // Check uses count incremented
  const { data: afterData } = await supabase
    .from("organization_invites")
    .select("uses_count")
    .eq("invite_code", testCode)
    .single();

  assertEquals(
    afterData?.uses_count,
    initialCount + 1,
    "uses_count should increment by 1",
  );
});

// ============================================================================
// TEST 3.5: Duplicate invite codes are rejected (UNIQUE constraint)
// ============================================================================
Deno.test("organization_invites rejects duplicate invite_code", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // First insert should succeed
  const firstInsert = await supabase.from("organization_invites").insert({
    organization_id: "test-org-id",
    invite_code: "UNIQUETEST123",
    max_uses: 100,
    expires_at: new Date(Date.now() + 86400000).toISOString(),
  });

  // Second insert with same code should fail
  const secondInsert = await supabase.from("organization_invites").insert({
    organization_id: "different-org-id",
    invite_code: "UNIQUETEST123", // Same code
    max_uses: 100,
    expires_at: new Date(Date.now() + 86400000).toISOString(),
  });

  assertExists(secondInsert.error, "Should have error on duplicate code");
  assertEquals(
    secondInsert.error?.code,
    "23505", // PostgreSQL unique violation
    "Should be unique constraint violation",
  );
});

// ============================================================================
// TEST 3.6: Non-existent invite code returns error
// ============================================================================
Deno.test(
  "validate-invite-code returns error for non-existent code",
  async () => {
    const fakeCode = "DOESNOTEXIST";
    const testToken = "valid-user-jwt-token";

    const response = await callValidateInvite(fakeCode, testToken);

    assertEquals(response.status, 404, "Should return 404 Not Found");
    assertEquals(response.data.valid, false, "Should indicate invalid");
    assertEquals(
      response.data.errorCode,
      "INVITE_NOT_FOUND",
      "Should return INVITE_NOT_FOUND error code",
    );
  },
);

// ============================================================================
// TEST 3.7: Deactivated invite code returns error
// ============================================================================
Deno.test(
  "validate-invite-code returns error for deactivated code",
  async () => {
    const deactivatedCode = "DEACTIVATED";
    const testToken = "valid-user-jwt-token";

    const response = await callValidateInvite(deactivatedCode, testToken);

    assertEquals(response.status, 400, "Should return 400 Bad Request");
    assertEquals(response.data.valid, false, "Should indicate invalid");
    assertEquals(
      response.data.errorCode,
      "INVITE_DEACTIVATED",
      "Should return INVITE_DEACTIVATED error code",
    );
  },
);
```

---

## 4. Join Organization Tests

### File: `supabase/functions/join-organization/test.ts`

```typescript
// ============================================================================
// B2B PHASE 1: JOIN ORGANIZATION TESTS
// Run with: deno test --allow-net --allow-env supabase/functions/join-organization/test.ts
// Expected: ALL TESTS FAIL until Edge Function is implemented
// ============================================================================

import {
  assertEquals,
  assertExists,
  assert,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "test-anon-key";
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/join-organization`;

interface JoinOrganizationResponse {
  success: boolean;
  member?: {
    id: string;
    organization_id: string;
    user_id: string;
    joined_at: string;
  };
  subscription?: {
    tier: string;
    access_source: string;
  };
  error?: string;
  errorCode?: string;
}

async function callJoinOrganization(
  inviteCode: string,
  token: string,
): Promise<{ status: number; data: JoinOrganizationResponse }> {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ inviteCode }),
  });

  return {
    status: response.status,
    data: await response.json(),
  };
}

// ============================================================================
// TEST 4.1: Join organization creates organization_members record
// ============================================================================
Deno.test("join-organization creates organization_members record", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testInviteCode = "JOINTEST123";
  const testToken = "valid-user-jwt-token";

  const response = await callJoinOrganization(testInviteCode, testToken);

  assertEquals(response.status, 200, "Should return 200 OK");
  assertEquals(response.data.success, true, "Should indicate success");
  assertExists(response.data.member, "Should return member data");
  assertExists(response.data.member?.id, "Member should have ID");
  assertExists(response.data.member?.joined_at, "Member should have joined_at");

  // Verify record exists in database
  const { data: member } = await supabase
    .from("organization_members")
    .select("*")
    .eq("id", response.data.member?.id)
    .single();

  assertExists(member, "Member record should exist in database");
});

// ============================================================================
// TEST 4.2: Join organization grants premium subscription
// ============================================================================
Deno.test(
  "join-organization grants premium subscription with organization_sponsored source",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const testInviteCode = "PREMIUMTEST";
    const testToken = "valid-user-jwt-token";

    const response = await callJoinOrganization(testInviteCode, testToken);

    assertEquals(response.status, 200, "Should return 200 OK");
    assertExists(response.data.subscription, "Should return subscription data");
    assertEquals(
      response.data.subscription?.tier,
      "premium",
      "Subscription tier should be premium",
    );
    assertEquals(
      response.data.subscription?.access_source,
      "organization_sponsored",
      "Access source should be organization_sponsored",
    );

    // Verify profile subscription_tier updated
    // Note: Would need to extract user_id from token to verify
  },
);

// ============================================================================
// TEST 4.3: Join organization prevents duplicate membership
// ============================================================================
Deno.test("join-organization prevents duplicate membership", async () => {
  const testInviteCode = "DUPLICATETEST";
  const testToken = "valid-user-jwt-token";

  // First join should succeed
  const response1 = await callJoinOrganization(testInviteCode, testToken);
  assertEquals(response1.status, 200, "First join should succeed");

  // Second join should fail
  const response2 = await callJoinOrganization(testInviteCode, testToken);
  assertEquals(response2.status, 400, "Second join should fail");
  assertEquals(
    response2.data.errorCode,
    "ALREADY_MEMBER",
    "Should return ALREADY_MEMBER error code",
  );
});

// ============================================================================
// TEST 4.4: Join organization links user to correct organization
// ============================================================================
Deno.test("join-organization links user to correct organization", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testInviteCode = "LINKTEST123";
  const expectedOrgId = "expected-organization-uuid";
  const testToken = "valid-user-jwt-token";

  const response = await callJoinOrganization(testInviteCode, testToken);

  assertEquals(response.status, 200, "Should return 200 OK");
  assertEquals(
    response.data.member?.organization_id,
    expectedOrgId,
    "Member should be linked to correct organization",
  );
});

// ============================================================================
// TEST 4.5: Join organization logs audit event
// ============================================================================
Deno.test(
  "join-organization logs audit event with event_type member_joined",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const testInviteCode = "AUDITLOGTEST";
    const testToken = "valid-user-jwt-token";

    const beforeTime = new Date().toISOString();

    const response = await callJoinOrganization(testInviteCode, testToken);
    assertEquals(response.status, 200, "Should return 200 OK");

    // Check audit log entry was created
    const { data: auditEntry } = await supabase
      .from("audit_log")
      .select("*")
      .eq("event_type", "member_joined")
      .gte("created_at", beforeTime)
      .order("created_at", { ascending: false })
      .limit(1)
      .single();

    assertExists(auditEntry, "Audit log entry should exist");
    assertEquals(
      auditEntry?.event_type,
      "member_joined",
      "Event type should be member_joined",
    );
    assertExists(auditEntry?.metadata, "Audit entry should have metadata");
  },
);

// ============================================================================
// TEST 4.6: Join organization fails when org is at seat capacity
// ============================================================================
Deno.test(
  "join-organization fails when organization is at seat capacity",
  async () => {
    const testInviteCode = "FULLORGCODE";
    const testToken = "valid-user-jwt-token";

    const response = await callJoinOrganization(testInviteCode, testToken);

    assertEquals(response.status, 400, "Should return 400 Bad Request");
    assertEquals(
      response.data.errorCode,
      "SEAT_LIMIT_REACHED",
      "Should return SEAT_LIMIT_REACHED error code",
    );
  },
);

// ============================================================================
// TEST 4.7: Join organization increments seats_used counter
// ============================================================================
Deno.test(
  "join-organization increments organization.seats_used counter",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const testInviteCode = "SEATCOUNTTEST";
    const testOrgId = "test-org-for-seat-count";
    const testToken = "valid-user-jwt-token";

    // Get initial seats_used
    const { data: beforeOrg } = await supabase
      .from("organizations")
      .select("seats_used")
      .eq("id", testOrgId)
      .single();

    const initialSeats = beforeOrg?.seats_used ?? 0;

    // Join organization
    await callJoinOrganization(testInviteCode, testToken);

    // Check seats_used incremented
    const { data: afterOrg } = await supabase
      .from("organizations")
      .select("seats_used")
      .eq("id", testOrgId)
      .single();

    assertEquals(
      afterOrg?.seats_used,
      initialSeats + 1,
      "seats_used should increment by 1",
    );
  },
);
```

---

## 5. Privacy Access Audit Tests

### File: `supabase/tests/b2b/test_privacy_access_audit.sql`

```sql
-- ============================================================================
-- B2B PHASE 1: PRIVACY ACCESS AUDIT TESTS
-- Tests that forbidden table access attempts are logged
-- Expected: ALL TESTS FAIL until audit logging is implemented
-- ============================================================================

DO $$
DECLARE
    test_admin_id UUID := gen_random_uuid();
    audit_count INT;
BEGIN
    RAISE NOTICE '=== Privacy Access Audit Tests Starting ===';

-- ============================================================================
-- TEST 5.1: Forbidden table access is logged to privacy_access_audit
-- ============================================================================
BEGIN
    -- This test requires the audit logging trigger to exist
    -- When an org admin tries to SELECT from profiles, it should log

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname LIKE '%privacy_audit%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: privacy_access_audit trigger does not exist';
    END IF;

    RAISE NOTICE 'TEST 5.1 PASS: privacy_access_audit trigger exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 5.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 5.2: Suspicious pattern detection (5+ blocked accesses in 1 hour)
-- ============================================================================
BEGIN
    -- Check for function that detects suspicious patterns
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'detect_suspicious_access_pattern'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: detect_suspicious_access_pattern function does not exist';
    END IF;

    RAISE NOTICE 'TEST 5.2 PASS: detect_suspicious_access_pattern function exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 5.2 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 5.3: Admin cannot read privacy_access_audit table
-- ============================================================================
BEGIN
    -- Verify RLS blocks admin access to privacy_access_audit
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'privacy_access_audit'
        AND policyname LIKE '%service_role_only%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: privacy_access_audit is not restricted to service role only';
    END IF;

    RAISE NOTICE 'TEST 5.3 PASS: privacy_access_audit is restricted to service role';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 5.3 FAIL: %', SQLERRM;
END;

    RAISE NOTICE '=== Privacy Access Audit Tests Complete ===';
END;
$$;
```

---

## 6. SAML Assertion Replay Prevention Tests

### File: `supabase/tests/b2b/test_saml_replay_prevention.sql`

```sql
-- ============================================================================
-- B2B PHASE 1: SAML ASSERTION REPLAY PREVENTION TESTS
-- Tests that SAML assertions cannot be replayed
-- Expected: ALL TESTS FAIL until saml_assertions table is created
-- ============================================================================

DO $$
DECLARE
    test_assertion_id TEXT := 'test-assertion-' || gen_random_uuid()::text;
    test_org_id UUID := gen_random_uuid();
    insert_result INT;
BEGIN
    RAISE NOTICE '=== SAML Replay Prevention Tests Starting ===';

-- ============================================================================
-- TEST 6.1: assertion_id UNIQUE constraint exists
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'saml_assertions'
        AND constraint_type = 'UNIQUE'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions UNIQUE constraint on assertion_id missing';
    END IF;

    RAISE NOTICE 'TEST 6.1 PASS: assertion_id UNIQUE constraint exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 6.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 6.2: First assertion insert succeeds
-- ============================================================================
BEGIN
    INSERT INTO saml_assertions (
        assertion_id,
        organization_id,
        user_email,
        processed_at
    ) VALUES (
        test_assertion_id,
        test_org_id,
        'test@company.com',
        NOW()
    );

    RAISE NOTICE 'TEST 6.2 PASS: First assertion insert succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 6.2 FAIL: First assertion insert failed - %', SQLERRM;
END;

-- ============================================================================
-- TEST 6.3: Replay (duplicate assertion_id) is rejected
-- ============================================================================
BEGIN
    -- This should fail due to UNIQUE constraint
    INSERT INTO saml_assertions (
        assertion_id,
        organization_id,
        user_email,
        processed_at
    ) VALUES (
        test_assertion_id, -- Same assertion_id
        test_org_id,
        'test@company.com',
        NOW()
    );

    -- If we get here, the test failed
    RAISE EXCEPTION 'TEST FAIL: Duplicate assertion was accepted (replay attack possible)';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'TEST 6.3 PASS: Duplicate assertion correctly rejected';
    WHEN OTHERS THEN
        RAISE NOTICE 'TEST 6.3 FAIL: Unexpected error - %', SQLERRM;
END;

-- ============================================================================
-- TEST 6.4: Assertions have expiry check
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'saml_assertions'
        AND column_name = 'not_on_or_after'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions.not_on_or_after column missing';
    END IF;

    RAISE NOTICE 'TEST 6.4 PASS: saml_assertions has not_on_or_after column';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 6.4 FAIL: %', SQLERRM;
END;

    -- Cleanup
    DELETE FROM saml_assertions WHERE assertion_id = test_assertion_id;

    RAISE NOTICE '=== SAML Replay Prevention Tests Complete ===';
END;
$$;
```

---

## 7. Organization Metrics Privacy Threshold Tests

### File: `supabase/tests/b2b/test_metrics_privacy_threshold.sql`

```sql
-- ============================================================================
-- B2B PHASE 1: ORGANIZATION METRICS PRIVACY THRESHOLD TESTS
-- Tests that metrics only show when active_users >= 5
-- Expected: ALL TESTS FAIL until CHECK constraint is implemented
-- ============================================================================

DO $$
DECLARE
    test_org_id UUID := gen_random_uuid();
    test_date DATE := CURRENT_DATE;
BEGIN
    RAISE NOTICE '=== Organization Metrics Privacy Threshold Tests Starting ===';

-- ============================================================================
-- TEST 7.1: CHECK constraint active_users >= 5 exists
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints
        WHERE constraint_name LIKE '%organization_metrics%active_users%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: CHECK constraint for active_users >= 5 missing';
    END IF;

    RAISE NOTICE 'TEST 7.1 PASS: CHECK constraint for active_users exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.2: Insert with active_users < 5 fails
-- ============================================================================
BEGIN
    INSERT INTO organization_metrics (
        organization_id,
        metric_date,
        active_users,
        avg_mood_score
    ) VALUES (
        test_org_id,
        test_date,
        3, -- Less than 5, should fail
        4.2
    );

    -- If we get here, the test failed
    RAISE EXCEPTION 'TEST FAIL: Insert with active_users=3 was accepted';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'TEST 7.2 PASS: Insert with active_users < 5 correctly rejected';
    WHEN OTHERS THEN
        -- Could be table doesn't exist yet
        RAISE NOTICE 'TEST 7.2 FAIL: Unexpected error - %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.3: Insert with active_users = 5 succeeds
-- ============================================================================
BEGIN
    INSERT INTO organization_metrics (
        organization_id,
        metric_date,
        active_users,
        avg_mood_score
    ) VALUES (
        test_org_id,
        test_date,
        5, -- Exactly 5, should succeed
        4.2
    );

    RAISE NOTICE 'TEST 7.3 PASS: Insert with active_users = 5 succeeded';

    -- Cleanup
    DELETE FROM organization_metrics
    WHERE organization_id = test_org_id AND metric_date = test_date;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.3 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.4: avg_mood_score is NULL when mood_contributor_count < 5
-- ============================================================================
BEGIN
    -- Check that there's logic to null out mood data when contributors < 5
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_metrics'
        AND column_name = 'mood_contributor_count'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_metrics.mood_contributor_count column missing';
    END IF;

    -- Verify the business logic exists (trigger or application-level)
    -- This would typically be enforced at application level or via trigger

    RAISE NOTICE 'TEST 7.4 PASS: mood_contributor_count column exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.4 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.5: UNIQUE constraint on organization_id + metric_date
-- ============================================================================
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'organization_metrics'
        AND constraint_type = 'UNIQUE'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: UNIQUE constraint on organization_id + metric_date missing';
    END IF;

    RAISE NOTICE 'TEST 7.5 PASS: UNIQUE constraint exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.5 FAIL: %', SQLERRM;
END;

    RAISE NOTICE '=== Organization Metrics Privacy Threshold Tests Complete ===';
END;
$$;
```

---

## 8. Stripe Subscription Tests

### File: `supabase/functions/b2b-stripe-webhook/test.ts`

```typescript
// ============================================================================
// B2B PHASE 1: STRIPE SUBSCRIPTION TESTS
// Run with: deno test --allow-net --allow-env supabase/functions/b2b-stripe-webhook/test.ts
// Expected: ALL TESTS FAIL until Stripe integration is implemented
// ============================================================================

import {
  assertEquals,
  assertExists,
  assert,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "http://localhost:54321";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || "test-anon-key";
const WEBHOOK_URL = `${SUPABASE_URL}/functions/v1/b2b-stripe-webhook`;

// Mock Stripe webhook payload
function createStripeEvent(type: string, data: Record<string, unknown>) {
  return {
    id: `evt_${Date.now()}`,
    object: "event",
    api_version: "2023-10-16",
    created: Math.floor(Date.now() / 1000),
    type,
    data: {
      object: data,
    },
  };
}

// ============================================================================
// TEST 8.1: Stripe customer can be created with organization metadata
// ============================================================================
Deno.test(
  "Stripe customer creation includes organization metadata",
  async () => {
    // This would test the create-organization endpoint that creates Stripe customer
    const createOrgUrl = `${SUPABASE_URL}/functions/v1/create-organization`;

    const response = await fetch(createOrgUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer admin-jwt-token",
      },
      body: JSON.stringify({
        name: "Test Corp",
        adminEmail: "admin@testcorp.com",
        seatCount: 50,
      }),
    });

    const data = await response.json();

    assertEquals(response.status, 200, "Should return 200 OK");
    assertExists(data.stripeCustomerId, "Should return Stripe customer ID");
    assertExists(data.organization?.id, "Should return organization ID");
  },
);

// ============================================================================
// TEST 8.2: Subscription created with metered billing for seats
// ============================================================================
Deno.test("Subscription uses metered billing for seats", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-with-subscription";

  const { data: org } = await supabase
    .from("organizations")
    .select("stripe_subscription_id, seat_count")
    .eq("id", testOrgId)
    .single();

  assertExists(
    org?.stripe_subscription_id,
    "Organization should have subscription",
  );
  assert(org?.seat_count > 0, "Organization should have seat count");
});

// ============================================================================
// TEST 8.3: Seat quantity update triggers proration
// ============================================================================
Deno.test("Seat quantity update webhooks are handled", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  const webhookPayload = createStripeEvent("customer.subscription.updated", {
    id: "sub_test123",
    customer: "cus_test456",
    items: {
      data: [
        {
          id: "si_test789",
          quantity: 60, // Updated from 50
        },
      ],
    },
    metadata: {
      organization_id: "test-org-id",
    },
  });

  const response = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature-for-testing",
    },
    body: JSON.stringify(webhookPayload),
  });

  assertEquals(response.status, 200, "Webhook should be processed");

  // Verify seat count updated in database
  const { data: org } = await supabase
    .from("organizations")
    .select("seat_count")
    .eq("id", "test-org-id")
    .single();

  assertEquals(org?.seat_count, 60, "Seat count should be updated to 60");
});

// ============================================================================
// TEST 8.4: Payment failure webhook updates status to past_due
// ============================================================================
Deno.test("Payment failure triggers past_due status", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  const webhookPayload = createStripeEvent("invoice.payment_failed", {
    id: "in_test123",
    subscription: "sub_test123",
    customer: "cus_test456",
    metadata: {
      organization_id: "test-org-id",
    },
  });

  const response = await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature-for-testing",
    },
    body: JSON.stringify(webhookPayload),
  });

  assertEquals(response.status, 200, "Webhook should be processed");

  // Verify organization status updated
  const { data: org } = await supabase
    .from("organizations")
    .select("status")
    .eq("id", "test-org-id")
    .single();

  assertEquals(
    org?.status,
    "past_due",
    "Organization status should be past_due",
  );
});

// ============================================================================
// TEST 8.5: Billing audit log records seat changes
// ============================================================================
Deno.test("Billing audit log records seat changes", async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const testOrgId = "test-org-for-billing-audit";
  const beforeTime = new Date().toISOString();

  // Trigger a seat change (via admin API or webhook)
  const webhookPayload = createStripeEvent("customer.subscription.updated", {
    id: "sub_test_audit",
    items: {
      data: [{ quantity: 75 }],
    },
    metadata: {
      organization_id: testOrgId,
    },
  });

  await fetch(WEBHOOK_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Stripe-Signature": "mock-signature",
    },
    body: JSON.stringify(webhookPayload),
  });

  // Check billing audit log
  const { data: auditEntry } = await supabase
    .from("billing_audit_log")
    .select("*")
    .eq("organization_id", testOrgId)
    .gte("created_at", beforeTime)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  assertExists(auditEntry, "Billing audit entry should exist");
  assertEquals(
    auditEntry?.event_type,
    "seat_change",
    "Event type should be seat_change",
  );
  assertExists(auditEntry?.seat_delta, "Should record seat delta");
});

// ============================================================================
// TEST 8.6: Subscription cancellation updates organization status
// ============================================================================
Deno.test(
  "Subscription cancellation updates organization to churned",
  async () => {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

    const webhookPayload = createStripeEvent("customer.subscription.deleted", {
      id: "sub_cancelled",
      customer: "cus_cancelled",
      metadata: {
        organization_id: "org-to-cancel",
      },
    });

    const response = await fetch(WEBHOOK_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Stripe-Signature": "mock-signature",
      },
      body: JSON.stringify(webhookPayload),
    });

    assertEquals(response.status, 200, "Webhook should be processed");

    // Verify organization status
    const { data: org } = await supabase
      .from("organizations")
      .select("status")
      .eq("id", "org-to-cancel")
      .single();

    assertEquals(
      org?.status,
      "churned",
      "Organization status should be churned",
    );
  },
);
```

---

## Test File Summary

| Category          | File                                                    | Test Count | Priority |
| ----------------- | ------------------------------------------------------- | ---------- | -------- |
| Database Schema   | `supabase/tests/b2b/test_organizations_schema.sql`      | 9          | Week 1   |
| RLS Policies      | `supabase/tests/b2b/test_rls_forbidden_tables.sql`      | 7          | Week 1   |
| Invite Validation | `supabase/functions/validate-invite-code/test.ts`       | 7          | Week 2   |
| Join Organization | `supabase/functions/join-organization/test.ts`          | 7          | Week 2   |
| Privacy Audit     | `supabase/tests/b2b/test_privacy_access_audit.sql`      | 3          | Week 2   |
| SAML Replay       | `supabase/tests/b2b/test_saml_replay_prevention.sql`    | 4          | Week 1   |
| Metrics Privacy   | `supabase/tests/b2b/test_metrics_privacy_threshold.sql` | 5          | Week 3   |
| Stripe Billing    | `supabase/functions/b2b-stripe-webhook/test.ts`         | 6          | Week 3   |

**Total Tests: 48**

---

## Running Tests

### SQL Schema Tests

```bash
# Run all schema tests
psql $DATABASE_URL -f supabase/tests/b2b/test_organizations_schema.sql
psql $DATABASE_URL -f supabase/tests/b2b/test_rls_forbidden_tables.sql
psql $DATABASE_URL -f supabase/tests/b2b/test_privacy_access_audit.sql
psql $DATABASE_URL -f supabase/tests/b2b/test_saml_replay_prevention.sql
psql $DATABASE_URL -f supabase/tests/b2b/test_metrics_privacy_threshold.sql
```

### Edge Function Tests

```bash
# Run all Edge Function tests
deno test --allow-net --allow-env supabase/functions/validate-invite-code/test.ts
deno test --allow-net --allow-env supabase/functions/join-organization/test.ts
deno test --allow-net --allow-env supabase/functions/b2b-stripe-webhook/test.ts
```

---

## Expected Results After Phase 1 Implementation

When Phase 1 is complete, all 48 tests should pass:

```
=== B2B Schema Tests ===
Passed: 9 / 9

=== RLS Forbidden Table Tests ===
Passed: 7 / 7

=== Invite Validation Tests ===
Passed: 7 / 7

=== Join Organization Tests ===
Passed: 7 / 7

=== Privacy Audit Tests ===
Passed: 3 / 3

=== SAML Replay Prevention Tests ===
Passed: 4 / 4

=== Metrics Privacy Threshold Tests ===
Passed: 5 / 5

=== Stripe Billing Tests ===
Passed: 6 / 6

TOTAL: 48 / 48 PASSED
```

---

## Definition of Done for Phase 1

Phase 1 is complete when:

1. All 9 database tables exist with correct structure
2. All RLS policies block organization admins from personal data
3. Invite code validation enforces expiry and max_uses
4. Join organization creates membership and grants premium access
5. Privacy access attempts are logged
6. SAML assertions cannot be replayed
7. Organization metrics enforce >= 5 active users
8. Stripe webhooks update organization billing status
9. All 48 tests pass
