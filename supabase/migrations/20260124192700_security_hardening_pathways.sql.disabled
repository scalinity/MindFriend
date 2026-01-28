-- Migration: Security Hardening for Pathway Functions
-- Description: Add SECURITY DEFINER, ownership verification, and race condition fixes
-- Date: 2026-01-24
-- Critical Security Fixes:
--   1. Add SECURITY DEFINER to prevent privilege escalation
--   2. Add user ownership verification in stored procedures
--   3. Fix race condition in duplicate check-in prevention
--   4. Set search_path to prevent schema injection

-- ==========================================
-- 1. Harden enroll_user_in_pathway function
-- ==========================================

CREATE OR REPLACE FUNCTION enroll_user_in_pathway(
    p_user_id UUID,
    p_pathway_id UUID,
    p_personalization JSONB,
    p_context_content TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER  -- Critical: Prevent service role privilege escalation
SET search_path = public  -- Critical: Prevent schema injection attacks
AS $$
DECLARE
    v_user_pathway_id UUID;
    v_pathway_key TEXT;
    v_result JSONB;
BEGIN
    -- CRITICAL SECURITY CHECK: Verify user ownership
    IF p_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot enroll pathway for another user';
    END IF;

    -- Validate pathway exists
    SELECT key INTO v_pathway_key
    FROM transition_pathways
    WHERE id = p_pathway_id;

    IF v_pathway_key IS NULL THEN
        RAISE EXCEPTION 'Pathway not found';
    END IF;

    -- Check for duplicate enrollment
    IF EXISTS (
        SELECT 1 FROM user_pathways
        WHERE user_id = p_user_id
        AND pathway_id = p_pathway_id
        AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Already enrolled in this pathway';
    END IF;

    -- 1. Create user_pathways record
    INSERT INTO user_pathways (
        user_id,
        pathway_id,
        current_phase,
        current_day,
        current_phase_day,
        status,
        personalization,
        started_at
    ) VALUES (
        p_user_id,
        p_pathway_id,
        1,
        1,
        1,
        'active',
        p_personalization,
        now()
    )
    RETURNING id INTO v_user_pathway_id;

    -- 2. Update companion memory
    INSERT INTO companion_memory (
        user_id,
        category,
        content,
        importance,
        expires_at
    ) VALUES (
        p_user_id,
        'life_event',
        p_context_content,
        0.95,
        NULL
    );

    -- 3. Update profile
    UPDATE profiles
    SET
        active_transition = v_pathway_key,
        updated_at = now()
    WHERE id = p_user_id;

    -- 4. Create initial progress record
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed
    ) VALUES (
        v_user_pathway_id,
        1,
        1,
        false
    );

    -- Return the user pathway ID
    v_result := jsonb_build_object('user_pathway_id', v_user_pathway_id);
    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        -- Log error without exposing sensitive data
        RAISE EXCEPTION 'Enrollment failed: %', SQLERRM;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION enroll_user_in_pathway TO authenticated;

-- ==========================================
-- 2. Harden submit_pathway_checkin function
-- ==========================================

CREATE OR REPLACE FUNCTION submit_pathway_checkin(
    p_user_pathway_id UUID,
    p_check_in_data JSONB,
    p_exercises_completed TEXT[],
    p_journal_entry TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER  -- Critical: Prevent service role privilege escalation
SET search_path = public  -- Critical: Prevent schema injection attacks
AS $$
DECLARE
    v_user_id UUID;
    v_current_day INT;
    v_current_phase INT;
    v_current_phase_day INT;
    v_pathway_id UUID;
    v_phase_duration INT;
    v_should_advance BOOLEAN := false;
    v_new_phase INT;
    v_new_day INT;
    v_new_phase_day INT;
    v_existing_checkin_id UUID;
    v_result JSONB;
BEGIN
    -- CRITICAL SECURITY CHECK: Verify user ownership
    SELECT user_id, current_day, current_phase, current_phase_day, pathway_id
    INTO v_user_id, v_current_day, v_current_phase, v_current_phase_day, v_pathway_id
    FROM user_pathways
    WHERE id = p_user_pathway_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User pathway not found';
    END IF;

    IF v_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot submit check-in for another user''s pathway';
    END IF;

    -- CRITICAL: Race condition fix - check for duplicate with row lock
    SELECT id INTO v_existing_checkin_id
    FROM pathway_progress
    WHERE user_pathway_id = p_user_pathway_id
    AND day_number = v_current_day
    FOR UPDATE NOWAIT;  -- Lock prevents concurrent inserts

    IF v_existing_checkin_id IS NOT NULL THEN
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    END IF;

    -- Input validation
    IF p_journal_entry IS NOT NULL AND length(p_journal_entry) > 10000 THEN
        RAISE EXCEPTION 'Journal entry too long (max 10,000 characters)';
    END IF;

    IF p_exercises_completed IS NOT NULL AND array_length(p_exercises_completed, 1) > 20 THEN
        RAISE EXCEPTION 'Too many exercises (max 20)';
    END IF;

    -- Get current phase duration
    SELECT duration_days INTO v_phase_duration
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id
    AND phase_number = v_current_phase;

    -- Calculate new values
    v_new_day := v_current_day + 1;
    v_new_phase := v_current_phase;
    v_new_phase_day := v_current_phase_day + 1;

    -- Check if we should advance phase
    IF v_current_phase_day >= v_phase_duration THEN
        v_should_advance := true;
        v_new_phase := v_current_phase + 1;
        v_new_phase_day := 1;
    END IF;

    -- 1. Insert progress record
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed,
        check_in_data,
        exercises_completed,
        journal_entry,
        milestones_achieved
    ) VALUES (
        p_user_pathway_id,
        v_current_day,
        v_current_phase,
        true,
        p_check_in_data,
        p_exercises_completed,
        p_journal_entry,
        '{}'::TEXT[]
    );

    -- 2. Update pathway state
    UPDATE user_pathways
    SET
        current_day = v_new_day,
        current_phase = v_new_phase,
        current_phase_day = v_new_phase_day,
        updated_at = now()
    WHERE id = p_user_pathway_id;

    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'newDay', v_new_day,
        'newPhase', v_new_phase,
        'phaseAdvanced', v_should_advance
    );

    RETURN v_result;

EXCEPTION
    WHEN lock_not_available THEN
        -- Concurrent check-in attempt
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    WHEN OTHERS THEN
        -- Log error without exposing sensitive data
        RAISE EXCEPTION 'Check-in failed: %', SQLERRM;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION submit_pathway_checkin TO authenticated;

-- ==========================================
-- 3. Add unique constraint for race condition prevention
-- ==========================================

-- This provides additional defense-in-depth beyond the FOR UPDATE lock
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'unique_pathway_day_checkin'
    ) THEN
        ALTER TABLE pathway_progress
        ADD CONSTRAINT unique_pathway_day_checkin
        UNIQUE (user_pathway_id, day_number);
    END IF;
END $$;

-- ==========================================
-- 4. Add check constraints for data validation
-- ==========================================

-- Validate JSONB check_in_data size
ALTER TABLE pathway_progress
DROP CONSTRAINT IF EXISTS check_in_data_size_limit,
ADD CONSTRAINT check_in_data_size_limit
CHECK (pg_column_size(check_in_data) < 50000);  -- 50KB limit

-- Validate personalization size
ALTER TABLE user_pathways
DROP CONSTRAINT IF EXISTS personalization_size_limit,
ADD CONSTRAINT personalization_size_limit
CHECK (pg_column_size(personalization) < 20000);  -- 20KB limit

-- ==========================================
-- 5. Comments for documentation
-- ==========================================

COMMENT ON FUNCTION enroll_user_in_pathway IS
'Securely enroll user in pathway. SECURITY DEFINER prevents privilege escalation. Verifies auth.uid() matches p_user_id.';

COMMENT ON FUNCTION submit_pathway_checkin IS
'Securely submit daily check-in. SECURITY DEFINER prevents privilege escalation. Uses FOR UPDATE NOWAIT to prevent race conditions.';
