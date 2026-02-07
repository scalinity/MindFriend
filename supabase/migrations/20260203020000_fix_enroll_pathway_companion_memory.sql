-- Fix enroll_user_in_pathway: companion_memory table doesn't have 'importance' or 'expires_at' columns,
-- and 'life_event' is not a valid category. Use 'life_context' category and existing columns instead.

CREATE OR REPLACE FUNCTION enroll_user_in_pathway(
    p_user_id UUID,
    p_pathway_id UUID,
    p_personalization JSONB,
    p_context_content TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_pathway_id UUID;
    v_pathway_key TEXT;
    v_result JSONB;
BEGIN
    -- Get pathway key for profile update
    SELECT key INTO v_pathway_key FROM transition_pathways WHERE id = p_pathway_id;

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

    -- 2. Update companion memory (use 'life_context' category - valid per CHECK constraint)
    INSERT INTO companion_memory (
        user_id,
        category,
        content
    ) VALUES (
        p_user_id,
        'life_context',
        p_context_content
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

END;
$$;
