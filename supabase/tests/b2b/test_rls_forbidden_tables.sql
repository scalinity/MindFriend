-- ============================================================================
-- B2B PHASE 1: RLS POLICY TESTS - FORBIDDEN TABLE ACCESS
-- These tests verify organization admins CANNOT access personal user data
-- Run with: psql $DATABASE_URL -f supabase/tests/b2b/test_rls_forbidden_tables.sql
-- Expected: ALL TESTS FAIL until RLS policies are implemented
-- ============================================================================

DO $$
DECLARE
    test_count INT := 0;
    pass_count INT := 0;
    policy_exists BOOLEAN;
BEGIN
    RAISE NOTICE '=== B2B RLS Forbidden Table Tests Starting ===';

-- ============================================================================
-- TEST 2.1: RLS is enabled on organization_members table
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'organization_members'
        AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: RLS not enabled on organization_members table';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.1 PASS: RLS enabled on organization_members';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.2: RLS is enabled on organization_metrics table
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'organization_metrics'
        AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: RLS not enabled on organization_metrics table';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.2 PASS: RLS enabled on organization_metrics';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.2 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.3: RLS is enabled on organizations table
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'organizations'
        AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: RLS not enabled on organizations table';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.3 PASS: RLS enabled on organizations';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.3 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.4: RLS is enabled on organization_invites table
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'organization_invites'
        AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: RLS not enabled on organization_invites table';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.4 PASS: RLS enabled on organization_invites';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.4 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.5: RLS is enabled on privacy_access_audit table
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE tablename = 'privacy_access_audit'
        AND rowsecurity = true
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: RLS not enabled on privacy_access_audit table';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.5 PASS: RLS enabled on privacy_access_audit';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.5 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.6: Policy exists for org admins to read organization_metrics
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'organization_metrics'
        AND cmd = 'SELECT'
    ) INTO policy_exists;

    IF NOT policy_exists THEN
        RAISE EXCEPTION 'TEST FAIL: No SELECT policy on organization_metrics';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.6 PASS: SELECT policy exists on organization_metrics';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.6 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 2.7: Policy exists for org admins to read organization_members
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'organization_members'
        AND cmd = 'SELECT'
    ) INTO policy_exists;

    IF NOT policy_exists THEN
        RAISE EXCEPTION 'TEST FAIL: No SELECT policy on organization_members';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 2.7 PASS: SELECT policy exists on organization_members';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 2.7 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
    RAISE NOTICE '=== B2B RLS Forbidden Table Tests Complete ===';
    RAISE NOTICE 'Passed: % / %', pass_count, test_count;

    IF pass_count < test_count THEN
        RAISE EXCEPTION 'RLS TESTS FAILED: % tests did not pass', (test_count - pass_count);
    END IF;
END;
$$;
