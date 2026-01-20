-- Migration: Add RPC function for atomic couples exercise session rating
-- Purpose: Handle atomic rating updates when both users rate simultaneously
-- References: Phase 1.2 Edge Functions - couples-exercise-sessions PATCH endpoint

-- ============================================================================
-- TABLE: Create appreciations table for partner messages
-- ============================================================================

CREATE TABLE IF NOT EXISTS appreciations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  to_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT appreciations_users_different CHECK (from_user_id != to_user_id)
);

-- Enable RLS
ALTER TABLE appreciations ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can read appreciations sent to them, create ones they send
CREATE POLICY "Users can read their own appreciations"
  ON appreciations FOR SELECT
  USING (auth.uid() = to_user_id OR auth.uid() = from_user_id);

CREATE POLICY "Users can create appreciations"
  ON appreciations FOR INSERT
  WITH CHECK (auth.uid() = from_user_id);

-- ============================================================================
-- RPC FUNCTION: Atomic couples exercise session rating
-- ============================================================================

-- Drop existing function if it exists (for idempotency)
DROP FUNCTION IF EXISTS update_session_rating(UUID, UUID, INT, TEXT);

-- Create RPC function for atomic session rating updates
-- This function ensures both ratings are saved atomically before status transitions
CREATE FUNCTION update_session_rating(
  p_session_id UUID,
  p_user_id UUID,
  p_rating INT,
  p_notes TEXT
) RETURNS couples_exercise_sessions AS $$
DECLARE
  v_session couples_exercise_sessions;
BEGIN
  -- Lock the row for update to prevent race conditions
  SELECT * INTO v_session FROM couples_exercise_sessions
    WHERE id = p_session_id
    FOR UPDATE;

  -- Validate session exists
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- Validate rating is within valid range (1-5)
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5';
  END IF;

  -- Update rating for the appropriate user
  IF v_session.user_id_1 = p_user_id THEN
    UPDATE couples_exercise_sessions
      SET
        user_1_rating = p_rating,
        user_1_notes = p_notes,
        -- Mark session completed if both users have now rated
        status = CASE
          WHEN user_2_rating IS NOT NULL THEN 'completed'
          ELSE status
        END,
        completed_at = CASE
          WHEN user_2_rating IS NOT NULL THEN NOW()
          ELSE completed_at
        END,
        updated_at = NOW()
      WHERE id = p_session_id
      RETURNING * INTO v_session;
  ELSIF v_session.user_id_2 = p_user_id THEN
    UPDATE couples_exercise_sessions
      SET
        user_2_rating = p_rating,
        user_2_notes = p_notes,
        -- Mark session completed if both users have now rated
        status = CASE
          WHEN user_1_rating IS NOT NULL THEN 'completed'
          ELSE status
        END,
        completed_at = CASE
          WHEN user_1_rating IS NOT NULL THEN NOW()
          ELSE completed_at
        END,
        updated_at = NOW()
      WHERE id = p_session_id
      RETURNING * INTO v_session;
  ELSE
    RAISE EXCEPTION 'User is not part of this session';
  END IF;

  RETURN v_session;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION update_session_rating(UUID, UUID, INT, TEXT)
  TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION update_session_rating(UUID, UUID, INT, TEXT) IS
  'Atomically update session rating for a user. Transitions session to completed when both users have rated.';

-- ============================================================================
-- TRIGGER: Auto-expire partner link invites after 72 hours
-- ============================================================================

-- Check if trigger already exists, drop if it does
DROP TRIGGER IF EXISTS auto_expire_partner_invites ON partner_links;
DROP FUNCTION IF EXISTS expire_old_partner_invites();

-- Function to check and expire old invites
CREATE FUNCTION expire_old_partner_invites()
RETURNS VOID AS $$
BEGIN
  UPDATE partner_links
    SET status = 'ended', ended_at = NOW()
    WHERE status = 'pending'
      AND expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Note: Actual scheduling of this function should be done via pg_cron extension
-- Example: SELECT cron.schedule('expire-partner-invites', '*/5 * * * *', 'SELECT expire_old_partner_invites()');

-- ============================================================================
-- FUNCTION: Auto-abandon sessions if user doesn't join within 24 hours
-- ============================================================================

DROP FUNCTION IF EXISTS abandon_inactive_sessions();

CREATE FUNCTION abandon_inactive_sessions()
RETURNS VOID AS $$
BEGIN
  UPDATE couples_exercise_sessions
    SET status = 'abandoned', updated_at = NOW()
    WHERE status = 'pending'
      AND user_2_joined_at IS NULL
      AND created_at < NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INDEXES: Query optimization for couples mode
-- ============================================================================

-- Index for efficient filtering of pending partner invites by expiration
CREATE INDEX IF NOT EXISTS idx_partner_links_status_expires
  ON partner_links(status, expires_at)
  WHERE status = 'pending';

-- Index for finding sessions between two specific users
CREATE INDEX IF NOT EXISTS idx_couples_exercise_sessions_users
  ON couples_exercise_sessions(user_id_1, user_id_2, status);

-- Index for efficiently fetching appreciations for a user in reverse chronological order
CREATE INDEX IF NOT EXISTS idx_appreciations_recipient_created
  ON appreciations(to_user_id, created_at DESC);
