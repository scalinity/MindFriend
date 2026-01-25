-- Migration: Fix encrypted check-in pipeline
-- Architecture: Update submit_pathway_checkin to accept and store encrypted data

CREATE OR REPLACE FUNCTION submit_pathway_checkin(
    p_user_pathway_id UUID,
    p_check_in_data JSONB,
    p_exercises_completed TEXT[],
    p_journal_entry TEXT,
    p_encrypted_journal_entry TEXT DEFAULT NULL,
    p_encrypted_notes TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_current_day INT;
    v_current_phase INT;
    v_current_phase_day INT;
    v_pathway_id UUID;
    v_phase_duration INT;
    v_should_advance BOOLEAN := false;
    v_new_phase INT;
    v_new_day INT;
    v_new_phase_day INT;
    v_result JSONB;
BEGIN
    -- Get current pathway state
    SELECT current_day, current_phase, current_phase_day, pathway_id
    INTO v_current_day, v_current_phase, v_current_phase_day, v_pathway_id
    FROM user_pathways
    WHERE id = p_user_pathway_id;

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

    -- 1. Insert progress record with encrypted data
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
        -- Only store plaintext if no encrypted version provided
        CASE WHEN p_encrypted_journal_entry IS NULL THEN p_journal_entry ELSE NULL END,
        -- Store encrypted version
        p_encrypted_journal_entry,
        -- Set key identifier if encrypted
        CASE WHEN p_encrypted_journal_entry IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
        -- Store encrypted notes (from check_in_data.encryptedNotes)
        p_encrypted_notes,
        -- Set key identifier if encrypted
        CASE WHEN p_encrypted_notes IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
        -- Set encryption timestamp
        CASE WHEN p_encrypted_journal_entry IS NOT NULL OR p_encrypted_notes IS NOT NULL THEN now() ELSE NULL END,
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

END;
$$ LANGUAGE plpgsql;
