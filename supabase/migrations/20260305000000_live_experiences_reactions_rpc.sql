-- Migration: 20260303000001_live_experiences_reactions_rpc.sql
-- Add missing RPC for updating live session reactions

CREATE OR REPLACE FUNCTION update_live_session_reactions(
  p_session_id UUID,
  p_user_id UUID
)
RETURNS VOID AS $$
BEGIN
  UPDATE live_session_participants
  SET reactions_sent = reactions_sent + 1
  WHERE session_id = p_session_id
    AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_live_session_reactions(UUID, UUID) TO authenticated;
