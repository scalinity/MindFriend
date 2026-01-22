-- MindFriend Atomic Session Transcript Update RPC
-- Purpose: Prevent race conditions when updating session transcripts
-- Created: 2026-01-22
-- Fixes: Session transcript corruption from concurrent updates

-- Add function to atomically update session transcript
CREATE OR REPLACE FUNCTION update_session_transcript_atomic(
    p_session_id UUID,
    p_user_id UUID,
    p_transcript_json TEXT,
    p_total_exchanges INTEGER
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

    -- Update transcript atomically within same transaction
    UPDATE rehearsal_sessions
    SET
        transcript = p_transcript_json,
        total_exchanges = p_total_exchanges,
        updated_at = NOW()
    WHERE id = p_session_id
    AND user_id = p_user_id;

    RETURN QUERY SELECT TRUE::BOOLEAN, NULL::TEXT;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE::BOOLEAN, SQLERRM::TEXT;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION update_session_transcript_atomic(UUID, UUID, TEXT, INTEGER) TO authenticated;

COMMENT ON FUNCTION update_session_transcript_atomic IS
'Atomically updates session transcript to prevent race conditions from concurrent message processing';
