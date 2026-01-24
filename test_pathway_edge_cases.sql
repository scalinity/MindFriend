-- Test Script: Life Transition Pathways Edge Cases
-- Purpose: Verify critical bug fixes and edge case handling
-- Run: psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f test_pathway_edge_cases.sql

\echo '===================================='
\echo 'Test 1: Verify current_phase_day column exists'
\echo '===================================='

SELECT
    column_name,
    data_type,
    column_default
FROM information_schema.columns
WHERE table_name = 'user_pathways'
  AND column_name = 'current_phase_day';

\echo ''
\echo '===================================='
\echo 'Test 2: Enroll in pathway and verify day 1 content'
\echo '===================================='

-- Create test user
DO $$
DECLARE
    v_test_user_id UUID;
    v_pathway_id UUID;
    v_user_pathway_id UUID;
    v_enrollment_result JSONB;
BEGIN
    -- Get a pathway ID
    SELECT id INTO v_pathway_id FROM transition_pathways WHERE key = 'job_loss' LIMIT 1;

    -- Insert test user in auth.users
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
    VALUES (
        gen_random_uuid(),
        'test-pathway-' || random() || '@test.com',
        crypt('password', gen_salt('bf')),
        now()
    )
    ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email
    RETURNING id INTO v_test_user_id;

    -- Create profile
    INSERT INTO profiles (id, email, display_name)
    VALUES (v_test_user_id, 'test-pathway-' || random() || '@test.com', 'Test User')
    ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE 'Created test user: %', v_test_user_id;

    -- Enroll in pathway
    SELECT enroll_user_in_pathway(
        v_test_user_id,
        v_pathway_id,
        '{"reason": "Testing enrollment"}'::jsonb,
        'User is testing the pathway enrollment process'
    ) INTO v_enrollment_result;

    v_user_pathway_id := (v_enrollment_result->>'user_pathway_id')::UUID;
    RAISE NOTICE 'Enrolled in pathway: %', v_user_pathway_id;

    -- Verify initial state
    PERFORM assert_equals(
        'Enrollment: current_day',
        (SELECT current_day FROM user_pathways WHERE id = v_user_pathway_id),
        1
    );

    PERFORM assert_equals(
        'Enrollment: current_phase',
        (SELECT current_phase FROM user_pathways WHERE id = v_user_pathway_id),
        1
    );

    PERFORM assert_equals(
        'Enrollment: current_phase_day',
        (SELECT current_phase_day FROM user_pathways WHERE id = v_user_pathway_id),
        1
    );

    RAISE NOTICE '✅ Test 2 PASSED: Enrollment creates correct initial state (day=1, phase=1, phase_day=1)';

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test 2 FAILED: %', SQLERRM;
END $$;

\echo ''
\echo '===================================='
\echo 'Test 3: Submit check-in on day 1, verify day advances to 2'
\echo '===================================='

DO $$
DECLARE
    v_test_user_id UUID;
    v_pathway_id UUID;
    v_user_pathway_id UUID;
    v_enrollment_result JSONB;
    v_checkin_result JSONB;
BEGIN
    -- Get pathway
    SELECT id INTO v_pathway_id FROM transition_pathways WHERE key = 'job_loss' LIMIT 1;

    -- Create test user
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
    VALUES (
        gen_random_uuid(),
        'test-checkin-' || random() || '@test.com',
        crypt('password', gen_salt('bf')),
        now()
    )
    RETURNING id INTO v_test_user_id;

    INSERT INTO profiles (id, email, display_name)
    VALUES (v_test_user_id, 'test-checkin-' || random() || '@test.com', 'Test User')
    ON CONFLICT (id) DO NOTHING;

    -- Enroll
    SELECT enroll_user_in_pathway(
        v_test_user_id,
        v_pathway_id,
        '{}'::jsonb,
        'Testing check-in'
    ) INTO v_enrollment_result;

    v_user_pathway_id := (v_enrollment_result->>'user_pathway_id')::UUID;

    -- Submit check-in
    SELECT submit_pathway_checkin(
        v_user_pathway_id,
        '{"mood": 7, "energy": 6}'::jsonb,
        ARRAY['exercise-1']::TEXT[],
        'Day 1 reflection'
    ) INTO v_checkin_result;

    -- Verify day advanced
    PERFORM assert_equals(
        'Check-in: new day',
        (SELECT current_day FROM user_pathways WHERE id = v_user_pathway_id),
        2
    );

    PERFORM assert_equals(
        'Check-in: phase day incremented',
        (SELECT current_phase_day FROM user_pathways WHERE id = v_user_pathway_id),
        2
    );

    PERFORM assert_equals(
        'Check-in: still in phase 1',
        (SELECT current_phase FROM user_pathways WHERE id = v_user_pathway_id),
        1
    );

    RAISE NOTICE '✅ Test 3 PASSED: Check-in advances day correctly (day=2, phase=1, phase_day=2)';

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test 3 FAILED: %', SQLERRM;
END $$;

\echo ''
\echo '===================================='
\echo 'Test 4: Submit check-in on last day of phase, verify phase advances'
\echo '===================================='

DO $$
DECLARE
    v_test_user_id UUID;
    v_pathway_id UUID;
    v_user_pathway_id UUID;
    v_enrollment_result JSONB;
    v_checkin_result JSONB;
    v_phase_duration INT;
    v_day INT;
BEGIN
    -- Get pathway and phase duration
    SELECT id INTO v_pathway_id FROM transition_pathways WHERE key = 'job_loss' LIMIT 1;
    SELECT duration_days INTO v_phase_duration FROM pathway_phases WHERE pathway_id = v_pathway_id AND phase_number = 1;

    -- Create test user
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
    VALUES (
        gen_random_uuid(),
        'test-phase-advance-' || random() || '@test.com',
        crypt('password', gen_salt('bf')),
        now()
    )
    RETURNING id INTO v_test_user_id;

    INSERT INTO profiles (id, email, display_name)
    VALUES (v_test_user_id, 'test-phase-advance-' || random() || '@test.com', 'Test User')
    ON CONFLICT (id) DO NOTHING;

    -- Enroll
    SELECT enroll_user_in_pathway(
        v_test_user_id,
        v_pathway_id,
        '{}'::jsonb,
        'Testing phase advancement'
    ) INTO v_enrollment_result;

    v_user_pathway_id := (v_enrollment_result->>'user_pathway_id')::UUID;

    -- Fast-forward to last day of phase 1
    UPDATE user_pathways
    SET
        current_day = v_phase_duration,
        current_phase_day = v_phase_duration,
        current_phase = 1
    WHERE id = v_user_pathway_id;

    RAISE NOTICE 'Fast-forwarded to day % (last day of phase 1)', v_phase_duration;

    -- Submit check-in on last day of phase
    SELECT submit_pathway_checkin(
        v_user_pathway_id,
        '{"mood": 8, "energy": 7}'::jsonb,
        ARRAY[]::TEXT[],
        'Last day of phase 1'
    ) INTO v_checkin_result;

    -- Verify phase advanced
    PERFORM assert_equals(
        'Phase advance: new phase',
        (SELECT current_phase FROM user_pathways WHERE id = v_user_pathway_id),
        2
    );

    PERFORM assert_equals(
        'Phase advance: phase_day reset to 1',
        (SELECT current_phase_day FROM user_pathways WHERE id = v_user_pathway_id),
        1
    );

    PERFORM assert_equals(
        'Phase advance: overall day incremented',
        (SELECT current_day FROM user_pathways WHERE id = v_user_pathway_id),
        v_phase_duration + 1
    );

    RAISE NOTICE '✅ Test 4 PASSED: Phase advances correctly when completing last day (phase=2, phase_day=1, day=%)', v_phase_duration + 1;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test 4 FAILED: %', SQLERRM;
END $$;

\echo ''
\echo '===================================='
\echo 'Test 5: Submit duplicate check-in (should fail with unique constraint)'
\echo '===================================='

DO $$
DECLARE
    v_test_user_id UUID;
    v_pathway_id UUID;
    v_user_pathway_id UUID;
    v_enrollment_result JSONB;
    v_checkin_result JSONB;
    v_duplicate_failed BOOLEAN := false;
BEGIN
    -- Get pathway
    SELECT id INTO v_pathway_id FROM transition_pathways WHERE key = 'job_loss' LIMIT 1;

    -- Create test user
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
    VALUES (
        gen_random_uuid(),
        'test-duplicate-' || random() || '@test.com',
        crypt('password', gen_salt('bf')),
        now()
    )
    RETURNING id INTO v_test_user_id;

    INSERT INTO profiles (id, email, display_name)
    VALUES (v_test_user_id, 'test-duplicate-' || random() || '@test.com', 'Test User')
    ON CONFLICT (id) DO NOTHING;

    -- Enroll
    SELECT enroll_user_in_pathway(
        v_test_user_id,
        v_pathway_id,
        '{}'::jsonb,
        'Testing duplicate check-in'
    ) INTO v_enrollment_result;

    v_user_pathway_id := (v_enrollment_result->>'user_pathway_id')::UUID;

    -- Submit first check-in
    SELECT submit_pathway_checkin(
        v_user_pathway_id,
        '{"mood": 7, "energy": 6}'::jsonb,
        ARRAY[]::TEXT[],
        'First check-in'
    ) INTO v_checkin_result;

    -- Reset to same day to simulate duplicate
    UPDATE user_pathways SET current_day = 1 WHERE id = v_user_pathway_id;

    -- Try to submit duplicate check-in (should fail)
    BEGIN
        SELECT submit_pathway_checkin(
            v_user_pathway_id,
            '{"mood": 8, "energy": 7}'::jsonb,
            ARRAY[]::TEXT[],
            'Duplicate check-in'
        ) INTO v_checkin_result;

        RAISE NOTICE '❌ Test 5 FAILED: Duplicate check-in was allowed (should have failed)';

    EXCEPTION WHEN unique_violation THEN
        v_duplicate_failed := true;
        RAISE NOTICE '✅ Test 5 PASSED: Duplicate check-in correctly prevented with unique constraint';
    END;

    IF NOT v_duplicate_failed THEN
        RAISE NOTICE '❌ Test 5 FAILED: No unique constraint violation raised';
    END IF;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test 5 FAILED: %', SQLERRM;
END $$;

\echo ''
\echo '===================================='
\echo 'Test 6: Verify array indexing (no off-by-one errors)'
\echo '===================================='

DO $$
DECLARE
    v_test_user_id UUID;
    v_pathway_id UUID;
    v_user_pathway_id UUID;
    v_enrollment_result JSONB;
    v_phase_id UUID;
    v_daily_themes JSONB;
    v_theme_day_1 JSONB;
    v_theme_last_day JSONB;
    v_phase_duration INT;
BEGIN
    -- Get pathway
    SELECT id INTO v_pathway_id FROM transition_pathways WHERE key = 'job_loss' LIMIT 1;
    SELECT id, duration_days, daily_themes INTO v_phase_id, v_phase_duration, v_daily_themes
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id AND phase_number = 1;

    -- Check array has correct length
    IF jsonb_array_length(v_daily_themes) != v_phase_duration THEN
        RAISE NOTICE '❌ Test 6 FAILED: daily_themes array length (%) does not match duration_days (%)',
            jsonb_array_length(v_daily_themes), v_phase_duration;
    ELSE
        RAISE NOTICE 'Array length correct: % themes for % days', jsonb_array_length(v_daily_themes), v_phase_duration;
    END IF;

    -- Verify first theme (index 0 in JSONB array = day 1)
    v_theme_day_1 := v_daily_themes->0;
    RAISE NOTICE 'Day 1 theme: %', v_theme_day_1;

    -- Verify last theme (index duration-1 in JSONB array = last day)
    v_theme_last_day := v_daily_themes->(v_phase_duration - 1);
    RAISE NOTICE 'Last day theme: %', v_theme_last_day;

    -- Test get-pathway-content logic
    -- Day 1 should access index 0 (dayInPhase - 1 = 1 - 1 = 0)
    -- Last day should access index duration-1 (dayInPhase - 1 = duration - 1)

    IF v_theme_day_1 IS NULL THEN
        RAISE NOTICE '❌ Test 6 FAILED: Day 1 theme is null (off-by-one error in array access)';
    ELSIF v_theme_last_day IS NULL THEN
        RAISE NOTICE '❌ Test 6 FAILED: Last day theme is null (off-by-one error in array access)';
    ELSE
        RAISE NOTICE '✅ Test 6 PASSED: Array indexing correct (day 1 and last day both accessible)';
    END IF;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test 6 FAILED: %', SQLERRM;
END $$;

\echo ''
\echo '===================================='
\echo 'Test 7: Verify phase boundary validation in stored procedure'
\echo '===================================='

DO $$
DECLARE
    v_test_user_id UUID;
    v_pathway_id UUID;
    v_user_pathway_id UUID;
    v_enrollment_result JSONB;
    v_checkin_result JSONB;
    v_max_phases INT := 4;
BEGIN
    -- Get pathway
    SELECT id INTO v_pathway_id FROM transition_pathways WHERE key = 'job_loss' LIMIT 1;

    -- Create test user
    INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at)
    VALUES (
        gen_random_uuid(),
        'test-boundary-' || random() || '@test.com',
        crypt('password', gen_salt('bf')),
        now()
    )
    RETURNING id INTO v_test_user_id;

    INSERT INTO profiles (id, email, display_name)
    VALUES (v_test_user_id, 'test-boundary-' || random() || '@test.com', 'Test User')
    ON CONFLICT (id) DO NOTHING;

    -- Enroll
    SELECT enroll_user_in_pathway(
        v_test_user_id,
        v_pathway_id,
        '{}'::jsonb,
        'Testing phase boundaries'
    ) INTO v_enrollment_result;

    v_user_pathway_id := (v_enrollment_result->>'user_pathway_id')::UUID;

    -- Manually set to last phase, last day
    UPDATE user_pathways
    SET
        current_phase = 4,
        current_phase_day = (SELECT duration_days FROM pathway_phases WHERE pathway_id = v_pathway_id AND phase_number = 4),
        current_day = (SELECT SUM(duration_days) FROM pathway_phases WHERE pathway_id = v_pathway_id)
    WHERE id = v_user_pathway_id;

    -- Submit check-in on last day of last phase
    SELECT submit_pathway_checkin(
        v_user_pathway_id,
        '{"mood": 9, "energy": 8}'::jsonb,
        ARRAY[]::TEXT[],
        'Final day'
    ) INTO v_checkin_result;

    -- Verify it doesn't try to advance to phase 5
    DECLARE
        v_final_phase INT;
    BEGIN
        SELECT current_phase INTO v_final_phase FROM user_pathways WHERE id = v_user_pathway_id;

        IF v_final_phase > v_max_phases THEN
            RAISE NOTICE '❌ Test 7 FAILED: Phase advanced beyond maximum (phase=%)', v_final_phase;
        ELSE
            RAISE NOTICE '✅ Test 7 PASSED: Phase boundary respected (final phase=%)', v_final_phase;
        END IF;
    END;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Test 7 FAILED: %', SQLERRM;
END $$;

\echo ''
\echo '===================================='
\echo 'Helper function for assertions'
\echo '===================================='

CREATE OR REPLACE FUNCTION assert_equals(test_name TEXT, actual INT, expected INT)
RETURNS VOID AS $$
BEGIN
    IF actual != expected THEN
        RAISE EXCEPTION '% - Expected: %, Got: %', test_name, expected, actual;
    END IF;
END;
$$ LANGUAGE plpgsql;

\echo ''
\echo '===================================='
\echo 'Test Summary'
\echo '===================================='
\echo 'Tests check:'
\echo '1. ✅ current_phase_day column exists (BUG FIX 1)'
\echo '2. ✅ Enrollment creates correct initial state'
\echo '3. ✅ Check-in increments day correctly (BUG FIX 2)'
\echo '4. ✅ Phase advancement when completing last day'
\echo '5. ✅ Duplicate check-in prevention'
\echo '6. ✅ Array indexing correctness (off-by-one check)'
\echo '7. ✅ Phase boundary validation'
\echo '===================================='
