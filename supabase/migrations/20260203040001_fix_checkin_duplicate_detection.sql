-- Fix: submit_pathway_checkin fails because enrollment creates a pathway_progress
-- row for day 1 (check_in_completed=false), and the RPC rejects any existing row.
-- Fix: Only reject if check_in_completed is already true. If false, update the existing row.
-- Also remove auth.uid() check since this is called via service role client.

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
    c_max_journal_length CONSTANT INT := 10000;
    c_max_encrypted_journal_length CONSTANT INT := 20000;

    v_user_id UUID;
    v_current_day INT;
    v_current_phase INT;
    v_current_phase_day INT;
    v_pathway_id UUID;
    v_phase_duration INT;
    v_max_phase INT;
    v_should_advance BOOLEAN := false;
    v_new_phase INT;
    v_new_day INT;
    v_new_phase_day INT;
    v_existing_checkin_id UUID;
    v_existing_completed BOOLEAN;
    v_pathway_completed BOOLEAN := false;
    v_result JSONB;
BEGIN
    -- Get user pathway info
    SELECT user_id, current_day, current_phase, current_phase_day, pathway_id
    INTO v_user_id, v_current_day, v_current_phase, v_current_phase_day, v_pathway_id
    FROM user_pathways
    WHERE id = p_user_pathway_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User pathway not found';
    END IF;

    -- Check for existing progress record with row lock
    SELECT id, check_in_completed INTO v_existing_checkin_id, v_existing_completed
    FROM pathway_progress
    WHERE user_pathway_id = p_user_pathway_id
    AND day_number = v_current_day
    FOR UPDATE NOWAIT;

    -- Only reject if check-in was already completed
    IF v_existing_completed = true THEN
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    END IF;

    -- Input validation
    IF p_journal_entry IS NOT NULL AND length(p_journal_entry) > c_max_journal_length THEN
        RAISE EXCEPTION 'Journal entry exceeds maximum length (% characters)', c_max_journal_length;
    END IF;

    IF p_encrypted_journal_entry IS NOT NULL AND length(p_encrypted_journal_entry) > c_max_encrypted_journal_length THEN
        RAISE EXCEPTION 'Encrypted journal entry exceeds maximum length (% characters)', c_max_encrypted_journal_length;
    END IF;

    -- Get phase duration with read lock
    SELECT duration_days INTO v_phase_duration
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id
    AND phase_number = v_current_phase
    FOR SHARE;

    -- Get max phase number for overflow validation
    SELECT MAX(phase_number) INTO v_max_phase
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id;

    -- Calculate new values
    v_new_day := v_current_day + 1;
    v_new_phase := v_current_phase;
    v_new_phase_day := v_current_phase_day + 1;

    -- Check if we should advance phase
    IF v_new_phase_day > v_phase_duration THEN
        IF v_current_phase < v_max_phase THEN
            v_should_advance := true;
            v_new_phase := v_current_phase + 1;
            v_new_phase_day := 1;
        ELSE
            v_pathway_completed := true;
            v_should_advance := false;
        END IF;
    END IF;

    -- Insert or update progress record
    IF v_existing_checkin_id IS NOT NULL THEN
        -- Update existing record (created by enrollment)
        UPDATE pathway_progress SET
            check_in_completed = true,
            check_in_data = p_check_in_data,
            exercises_completed = p_exercises_completed,
            journal_entry = CASE WHEN p_encrypted_journal_entry IS NULL THEN p_journal_entry ELSE NULL END,
            encrypted_journal_entry = p_encrypted_journal_entry,
            journal_encryption_key_id = CASE WHEN p_encrypted_journal_entry IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
            encrypted_check_in_data = p_encrypted_notes,
            check_in_encryption_key_id = CASE WHEN p_encrypted_notes IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
            data_encrypted_at = CASE WHEN p_encrypted_journal_entry IS NOT NULL OR p_encrypted_notes IS NOT NULL THEN now() ELSE NULL END
        WHERE id = v_existing_checkin_id;
    ELSE
        -- Insert new progress record
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
    END IF;

    -- Update pathway state
    IF v_pathway_completed THEN
        UPDATE user_pathways
        SET
            status = 'completed',
            completed_at = now(),
            current_day = v_new_day,
            updated_at = now()
        WHERE id = p_user_pathway_id;
    ELSE
        UPDATE user_pathways
        SET
            current_day = v_new_day,
            current_phase = v_new_phase,
            current_phase_day = v_new_phase_day,
            updated_at = now()
        WHERE id = p_user_pathway_id;
    END IF;

    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'newDay', v_new_day,
        'newPhase', v_new_phase,
        'phaseAdvanced', v_should_advance,
        'pathwayCompleted', v_pathway_completed
    );

    RETURN v_result;
END;
$$;
