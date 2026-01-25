-- Migration: Restore Security Controls to submit_pathway_checkin
-- Created: 2026-01-25 05:00:00
-- Purpose: Fix CRITICAL authorization bypass vulnerability identified in Phase 2 review
-- Issue: Previous migration (20260125043000) removed user ownership verification
-- Fix: Restore user ownership check, duplicate prevention with row locking, input validation
CREATE OR REPLACE FUNCTION submit_pathway_checkin(
    p_user_pathway_id UUID,
    p_check_in_data JSONB,
    p_exercises_completed TEXT[],
    p_journal_entry TEXT,
    p_encrypted_journal_entry TEXT DEFAULT NULL,
    p_encrypted_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    -- ✅ CRITICAL SECURITY CHECK: Verify user ownership
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

    -- ✅ CRITICAL: Race condition fix - check for duplicate with row lock
    SELECT id INTO v_existing_checkin_id
    FROM pathway_progress
    WHERE user_pathway_id = p_user_pathway_id
    AND day_number = v_current_day
    FOR UPDATE NOWAIT;

    IF v_existing_checkin_id IS NOT NULL THEN
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    END IF;

    -- ✅ Input validation
    IF p_journal_entry IS NOT NULL AND length(p_journal_entry) > 10000 THEN
        RAISE EXCEPTION 'Journal entry exceeds maximum length (10000 characters)';
    END IF;

    IF p_encrypted_journal_entry IS NOT NULL AND length(p_encrypted_journal_entry) > 20000 THEN
        RAISE EXCEPTION 'Encrypted journal entry exceeds maximum length (20000 characters)';
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

    -- Insert progress record with encrypted data
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed,
        check_in_data,
        exercises_completed,
        journal_entry,
        encrypted_journal_entry,
        journal_encryption_key_id,
        encrypted_check_in_data,
        check_in_encryption_key_id,
        data_encrypted_at,
        milestones_achieved
    ) VALUES (
        p_user_pathway_id,
        v_current_day,
        v_current_phase,
        true,
        p_check_in_data,
        p_exercises_completed,
        CASE WHEN p_encrypted_journal_entry IS NULL THEN p_journal_entry ELSE NULL END,
        p_encrypted_journal_entry,
        CASE WHEN p_encrypted_journal_entry IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
        p_encrypted_notes,
        CASE WHEN p_encrypted_notes IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
        CASE WHEN p_encrypted_journal_entry IS NOT NULL OR p_encrypted_notes IS NOT NULL THEN now() ELSE NULL END,
        '{}'::TEXT[]
    );

    -- Update pathway state
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
END;
$$;

-- Note: Function permissions inherited from previous migrations
