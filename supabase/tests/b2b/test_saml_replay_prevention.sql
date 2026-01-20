-- ============================================================================
-- B2B PHASE 1: SAML ASSERTION REPLAY PREVENTION TESTS
-- Tests that SAML assertions cannot be replayed
-- Run with: psql $DATABASE_URL -f supabase/tests/b2b/test_saml_replay_prevention.sql
-- Expected: ALL TESTS FAIL until saml_assertions table is created
-- ============================================================================

DO $$
DECLARE
    test_assertion_id TEXT := 'test-assertion-' || gen_random_uuid()::text;
    test_org_id UUID := gen_random_uuid();
    test_count INT := 0;
    pass_count INT := 0;
BEGIN
    RAISE NOTICE '=== SAML Replay Prevention Tests Starting ===';

-- ============================================================================
-- TEST 6.1: saml_assertions table exists
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

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 6.1 PASS: saml_assertions table exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 6.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 6.2: assertion_id has UNIQUE constraint
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu
          ON tc.constraint_name = ccu.constraint_name
        WHERE tc.table_name = 'saml_assertions'
        AND tc.constraint_type = 'UNIQUE'
        AND ccu.column_name = 'assertion_id'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: saml_assertions.assertion_id UNIQUE constraint missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 6.2 PASS: assertion_id has UNIQUE constraint';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 6.2 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 6.3: First assertion insert succeeds
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    -- Create test organization first (if organizations table exists)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'organizations') THEN
        INSERT INTO organizations (id, name, slug, seat_count)
        VALUES (test_org_id, 'Test Org for SAML', 'test-saml-org', 10)
        ON CONFLICT DO NOTHING;
    END IF;

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

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 6.3 PASS: First assertion insert succeeded';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 6.3 FAIL: First assertion insert failed - %', SQLERRM;
END;

-- ============================================================================
-- TEST 6.4: Replay (duplicate assertion_id) is rejected
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    -- This should fail due to UNIQUE constraint
    INSERT INTO saml_assertions (
        assertion_id,
        organization_id,
        user_email,
        processed_at
    ) VALUES (
        test_assertion_id, -- Same assertion_id - should fail
        test_org_id,
        'test@company.com',
        NOW()
    );

    -- If we get here, the test failed (replay was allowed)
    RAISE EXCEPTION 'TEST FAIL: Duplicate assertion was accepted (replay attack possible)';
EXCEPTION
    WHEN unique_violation THEN
        pass_count := pass_count + 1;
        RAISE NOTICE 'TEST 6.4 PASS: Duplicate assertion correctly rejected';
    WHEN OTHERS THEN
        RAISE NOTICE 'TEST 6.4 FAIL: Unexpected error - %', SQLERRM;
END;

-- ============================================================================
-- Cleanup
-- ============================================================================
BEGIN
    DELETE FROM saml_assertions WHERE assertion_id = test_assertion_id;
    DELETE FROM organizations WHERE id = test_org_id;
EXCEPTION WHEN OTHERS THEN
    -- Ignore cleanup errors
    NULL;
END;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
    RAISE NOTICE '=== SAML Replay Prevention Tests Complete ===';
    RAISE NOTICE 'Passed: % / %', pass_count, test_count;

    IF pass_count < test_count THEN
        RAISE EXCEPTION 'SAML TESTS FAILED: % tests did not pass', (test_count - pass_count);
    END IF;
END;
$$;
