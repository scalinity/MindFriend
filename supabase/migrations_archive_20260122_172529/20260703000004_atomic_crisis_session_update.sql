-- MindFriend Atomic Crisis Session Status Update RPC
-- Purpose: Prevent race conditions when updating session to crisis_ended
-- Created: 2026-01-22
-- Fixes: Crisis session status corruption from concurrent updates

-- Add function to atomically update crisis session status
CREATE OR REPLACE FUNCTION update_session_crisis_status_atomic(
    p_session_id UUID,
    p_user_id UUID
) RETURNS TABLE (
    success BOOLEAN,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_exists BOOLEAN;
BEGIN
    -- Check if session exists and belongs to user (with row lock)
    SELECT EXISTS(
        SELECT 1 FROM rehearsal_sessions
        WHERE id = p_session_id
        AND user_id = p_user_id
        AND status = 'active'
        FOR UPDATE
    ) INTO v_session_exists;

    IF NOT v_session_exists THEN
        RETURN QUERY SELECT FALSE::BOOLEAN, 'Session not found or not active'::TEXT;
        RETURN;
    END IF;

    -- Update session status atomically within same transaction
    UPDATE rehearsal_sessions
    SET
        status = 'crisis_ended',
        crisis_detected = TRUE,
        completed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_session_id
    AND user_id = p_user_id;

    RETURN QUERY SELECT TRUE::BOOLEAN, NULL::TEXT;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE::BOOLEAN, SQLERRM::TEXT;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION update_session_crisis_status_atomic(UUID, UUID) TO authenticated;

COMMENT ON FUNCTION update_session_crisis_status_atomic IS
'Atomically updates session to crisis_ended status to prevent race conditions from concurrent crisis detection';
