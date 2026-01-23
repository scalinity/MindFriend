-- MindFriend Atomic End Session Update RPC
-- Purpose: Prevent race conditions when finalizing session with feedback summary
-- Created: 2026-01-22
-- Fixes: Session completion data corruption from concurrent finalization requests

-- Add function to atomically complete session with feedback summary
CREATE OR REPLACE FUNCTION end_session_atomic(
    p_session_id UUID,
    p_user_id UUID,
    p_status TEXT,
    p_confidence_rating INTEGER,
    p_notes TEXT,
    p_feedback_summary TEXT,
    p_communication_style TEXT
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

    -- Update session atomically within same transaction
    UPDATE rehearsal_sessions
    SET
        status = p_status::rehearsal_session_status,
        completed_at = NOW(),
        confidence_rating = p_confidence_rating,
        notes = p_notes,
        feedback_summary = p_feedback_summary,
        communication_style = p_communication_style::communication_style,
        updated_at = NOW()
    WHERE id = p_session_id
    AND user_id = p_user_id;

    RETURN QUERY SELECT TRUE::BOOLEAN, NULL::TEXT;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE::BOOLEAN, SQLERRM::TEXT;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION end_session_atomic(UUID, UUID, TEXT, INTEGER, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION end_session_atomic IS
'Atomically completes a session with all feedback data to prevent race conditions from concurrent finalization';
