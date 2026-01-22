-- MindFriend Conversation Rehearsal Security & Performance Fixes
-- Applied: 2026-01-20
-- Fixes:
--  1. Add data retention policy (90 day default)
--  2. Add session timeout enforcement (2 hours)
--  3. Add matched_keyword column to crisis_events (PII protection)
--  4. Add indexes for performance
--  5. Add automatic session cleanup function

-- 1. Add data retention support
ALTER TABLE rehearsal_sessions
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
  GENERATED ALWAYS AS (started_at + INTERVAL '2 hours') STORED;

-- 2. Add session cleanup tracking
ALTER TABLE rehearsal_sessions
  ADD COLUMN IF NOT EXISTS abandoned_at TIMESTAMPTZ;

-- 3. Add matched_keyword to crisis_events for PII-safe logging
ALTER TABLE crisis_events
  ADD COLUMN IF NOT EXISTS matched_keyword TEXT;

-- 4. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_user_status
  ON rehearsal_sessions(user_id, status)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_expired
  ON rehearsal_sessions(expires_at)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_crisis_events_keyword
  ON crisis_events(matched_keyword, detected_at)
  WHERE matched_keyword IS NOT NULL;

-- 5. Function to auto-abandon expired sessions (runs every 15 min via pg_cron)
CREATE OR REPLACE FUNCTION abandon_expired_rehearsal_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE rehearsal_sessions
  SET
    status = 'abandoned',
    abandoned_at = NOW(),
    completed_at = NOW()
  WHERE
    status = 'active'
    AND expires_at < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 6. Function to delete old archived sessions (90 day retention)
CREATE OR REPLACE FUNCTION delete_old_rehearsal_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  -- Delete sessions that are completed/abandoned and older than 90 days
  DELETE FROM rehearsal_sessions
  WHERE
    status IN ('completed', 'abandoned', 'crisis_ended')
    AND completed_at < NOW() - INTERVAL '90 days';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 7. Add rollback_rehearsal_quota function for transaction support
CREATE OR REPLACE FUNCTION rollback_rehearsal_quota(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_settings
  SET rehearsals_used_this_week = GREATEST(0, rehearsals_used_this_week - 1)
  WHERE user_id = p_user_id;
END;
$$;

-- 8. Update check_and_increment_rehearsal_quota to handle edge cases
CREATE OR REPLACE FUNCTION check_and_increment_rehearsal_quota(p_user_id UUID)
RETURNS TABLE (can_create BOOLEAN, used INTEGER, quota_limit INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_used INTEGER;
  v_reset_at TIMESTAMPTZ;
  v_subscription_tier TEXT;
BEGIN
  -- Get current quota and subscription
  SELECT
    rehearsals_used_this_week,
    rehearsals_quota_reset_at,
    subscription_tier INTO v_used, v_reset_at, v_subscription_tier
  FROM user_settings us
  JOIN profiles p ON p.id = us.user_id
  WHERE us.user_id = p_user_id
  FOR UPDATE; -- Row lock to prevent race condition

  -- Premium users have unlimited quota
  IF v_subscription_tier = 'premium' THEN
    RETURN QUERY SELECT TRUE::BOOLEAN, 0::INTEGER, 999999::INTEGER;
    RETURN;
  END IF;

  -- Check if quota needs reset (weekly)
  IF v_reset_at < NOW() - INTERVAL '7 days' THEN
    -- Reset quota atomically in same transaction
    UPDATE user_settings
    SET
      rehearsals_used_this_week = 0,
      rehearsals_quota_reset_at = NOW()
    WHERE user_id = p_user_id;

    -- Free tier allows 2 rehearsals per week
    RETURN QUERY SELECT TRUE::BOOLEAN, 0::INTEGER, 2::INTEGER;
  ELSE
    -- Check if under limit and increment
    IF v_used < 2 THEN
      UPDATE user_settings
      SET rehearsals_used_this_week = v_used + 1
      WHERE user_id = p_user_id;
      RETURN QUERY SELECT TRUE::BOOLEAN, v_used + 1::INTEGER, 2::INTEGER;
    ELSE
      RETURN QUERY SELECT FALSE::BOOLEAN, v_used::INTEGER, 2::INTEGER;
    END IF;
  END IF;
END;
$$;

-- 9. Function to atomically check active session count (prevents TOCTOU race)
CREATE OR REPLACE FUNCTION check_active_session_limit(p_user_id UUID)
RETURNS TABLE (can_create BOOLEAN, active_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO v_active_count
  FROM rehearsal_sessions
  WHERE user_id = p_user_id
    AND status = 'active'
  FOR UPDATE; -- Lock rows to prevent TOCTOU race

  -- Maximum 3 concurrent active sessions
  RETURN QUERY SELECT (v_active_count < 3)::BOOLEAN, v_active_count;
END;
$$;

-- 10. RLS Policy: Users can only view their own crisis events
CREATE POLICY "Users can view own crisis events"
  ON crisis_events FOR SELECT
  USING (auth.uid()::TEXT = user_id::TEXT);

-- 11. RLS Policy: Admin can view all crisis events for moderation
CREATE POLICY "Service role can manage crisis events"
  ON crisis_events FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Run initial cleanup (remove any leftover abandoned sessions)
SELECT abandon_expired_rehearsal_sessions();
