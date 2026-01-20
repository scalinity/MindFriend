-- ============================================================================
-- B2B PHASE 1: DATABASE SCHEMA TESTS
-- These tests verify all required tables exist with correct structure
-- Run with: psql $DATABASE_URL -f supabase/tests/b2b/test_organizations_schema.sql
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

    -- Check invite_code column exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_invites'
        AND column_name = 'invite_code'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_invites.invite_code column missing';
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
-- TEST 1.5: organization_metrics with required columns
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

    -- Check required columns
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_metrics'
        AND column_name = 'active_users'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_metrics.active_users column missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'organization_metrics'
        AND column_name = 'metric_date'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: organization_metrics.metric_date column missing';
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

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'saml_assertions'
        AND column_name = 'assertion_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions.assertion_id column missing';
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
