-- ============================================================================
-- B2B PHASE 1: ORGANIZATION METRICS PRIVACY THRESHOLD TESTS
-- Tests that metrics only show when active_users >= 5
-- Run with: psql $DATABASE_URL -f supabase/tests/b2b/test_metrics_privacy_threshold.sql
-- Expected: ALL TESTS FAIL until CHECK constraint is implemented
-- ============================================================================

DO $$
DECLARE
    test_org_id UUID := gen_random_uuid();
    test_date DATE := CURRENT_DATE;
    test_count INT := 0;
    pass_count INT := 0;
BEGIN
    RAISE NOTICE '=== Organization Metrics Privacy Threshold Tests Starting ===';

-- ============================================================================
-- Setup: Create test organization if needed
-- ============================================================================
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'organizations') THEN
        INSERT INTO organizations (id, name, slug, seat_count)
        VALUES (test_org_id, 'Test Org for Metrics', 'test-metrics-org', 100)
        ON CONFLICT DO NOTHING;
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- Ignore setup errors
    NULL;
END;

-- ============================================================================
-- TEST 7.1: organization_metrics table exists
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

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 7.1 PASS: organization_metrics table exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.1 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.2: CHECK constraint active_users >= 5 exists
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.check_constraints cc
        JOIN information_schema.constraint_column_usage ccu
          ON cc.constraint_name = ccu.constraint_name
        WHERE ccu.table_name = 'organization_metrics'
        AND cc.check_clause LIKE '%active_users%>=%5%'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: CHECK constraint for active_users >= 5 missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 7.2 PASS: CHECK constraint for active_users >= 5 exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.2 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.3: Insert with active_users < 5 fails
-- ============================================================================
BEGIN
    test_count := test_count + 1;

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

    -- If we get here, the test failed (privacy violation possible)
    RAISE EXCEPTION 'TEST FAIL: Insert with active_users=3 was accepted';
EXCEPTION
    WHEN check_violation THEN
        pass_count := pass_count + 1;
        RAISE NOTICE 'TEST 7.3 PASS: Insert with active_users < 5 correctly rejected';
    WHEN OTHERS THEN
        RAISE NOTICE 'TEST 7.3 FAIL: Unexpected error - %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.4: Insert with active_users = 5 succeeds
-- ============================================================================
BEGIN
    test_count := test_count + 1;

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

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 7.4 PASS: Insert with active_users = 5 succeeded';

    -- Cleanup
    DELETE FROM organization_metrics
    WHERE organization_id = test_org_id AND metric_date = test_date;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.4 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- TEST 7.5: UNIQUE constraint on organization_id + metric_date
-- ============================================================================
BEGIN
    test_count := test_count + 1;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'organization_metrics'
        AND constraint_type = 'UNIQUE'
    ) THEN
        RAISE EXCEPTION 'TEST FAIL: UNIQUE constraint on organization_id + metric_date missing';
    END IF;

    pass_count := pass_count + 1;
    RAISE NOTICE 'TEST 7.5 PASS: UNIQUE constraint exists';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'TEST 7.5 FAIL: %', SQLERRM;
END;

-- ============================================================================
-- Cleanup
-- ============================================================================
BEGIN
    DELETE FROM organization_metrics WHERE organization_id = test_org_id;
    DELETE FROM organizations WHERE id = test_org_id;
EXCEPTION WHEN OTHERS THEN
    -- Ignore cleanup errors
    NULL;
END;

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
    RAISE NOTICE '=== Organization Metrics Privacy Threshold Tests Complete ===';
    RAISE NOTICE 'Passed: % / %', pass_count, test_count;

    IF pass_count < test_count THEN
        RAISE EXCEPTION 'METRICS PRIVACY TESTS FAILED: % tests did not pass', (test_count - pass_count);
    END IF;
END;
$$;
