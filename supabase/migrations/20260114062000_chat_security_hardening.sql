-- Chat Security Hardening Migration
-- Addresses security issues identified in code review

-- 1. Update crisis_events table to store keyword matched instead of actual content (PII protection)
ALTER TABLE crisis_events
ADD COLUMN IF NOT EXISTS trigger_keyword TEXT;

-- Make trigger_content nullable (we no longer store actual user content)
ALTER TABLE crisis_events
ALTER COLUMN trigger_content DROP NOT NULL;

COMMENT ON COLUMN crisis_events.trigger_keyword IS 'The crisis keyword that was detected (not user content)';
COMMENT ON COLUMN crisis_events.trigger_content IS 'DEPRECATED: No longer populated for PII protection';

-- 2. Create atomic quota check and increment function to prevent race conditions
CREATE OR REPLACE FUNCTION check_and_increment_ai_quota(
  p_user_id UUID,
  p_is_premium BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
  allowed BOOLEAN,
  quota_used INT,
  quota_limit INT,
  was_reset BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_quota_used INT;
  v_quota_limit INT;
  v_quota_reset_at TIMESTAMPTZ;
  v_was_reset BOOLEAN := FALSE;
BEGIN
  -- Lock the row to prevent concurrent updates
  SELECT daily_ai_used, daily_ai_quota, quota_reset_at
  INTO v_quota_used, v_quota_limit, v_quota_reset_at
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  -- Check if quota needs reset (new day)
  IF DATE(v_quota_reset_at) < CURRENT_DATE THEN
    v_quota_used := 0;
    v_was_reset := TRUE;
    UPDATE profiles
    SET daily_ai_used = 0, quota_reset_at = NOW()
    WHERE id = p_user_id;
  END IF;

  -- Premium users always allowed
  IF p_is_premium THEN
    -- Increment but don't check limit
    UPDATE profiles
    SET daily_ai_used = v_quota_used + 1
    WHERE id = p_user_id;

    RETURN QUERY SELECT TRUE, v_quota_used + 1, -1, v_was_reset;
    RETURN;
  END IF;

  -- Check quota for free users
  IF v_quota_used >= v_quota_limit THEN
    -- Quota exceeded, don't increment
    RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, v_was_reset;
    RETURN;
  END IF;

  -- Atomically increment quota
  UPDATE profiles
  SET daily_ai_used = v_quota_used + 1
  WHERE id = p_user_id;

  RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, v_was_reset;
END;
$$;

COMMENT ON FUNCTION check_and_increment_ai_quota IS 'Atomically checks and increments AI quota to prevent race conditions';

-- 3. Ensure RLS policies exist for chat-related tables
-- Note: These may already exist, using IF NOT EXISTS pattern

-- Conversations RLS
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'conversations' AND policyname = 'Users can view own conversations'
  ) THEN
    CREATE POLICY "Users can view own conversations" ON conversations
      FOR SELECT USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'conversations' AND policyname = 'Users can insert own conversations'
  ) THEN
    CREATE POLICY "Users can insert own conversations" ON conversations
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'conversations' AND policyname = 'Users can update own conversations'
  ) THEN
    CREATE POLICY "Users can update own conversations" ON conversations
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'conversations' AND policyname = 'Users can delete own conversations'
  ) THEN
    CREATE POLICY "Users can delete own conversations" ON conversations
      FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Messages RLS (users can only access messages from their own conversations)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'messages' AND policyname = 'Users can view own messages'
  ) THEN
    CREATE POLICY "Users can view own messages" ON messages
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM conversations
          WHERE conversations.id = messages.conversation_id
          AND conversations.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'messages' AND policyname = 'Users can insert own messages'
  ) THEN
    CREATE POLICY "Users can insert own messages" ON messages
      FOR INSERT WITH CHECK (
        EXISTS (
          SELECT 1 FROM conversations
          WHERE conversations.id = messages.conversation_id
          AND conversations.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Crisis events RLS (users can only view their own crisis events, no delete/update)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'crisis_events' AND policyname = 'Users can view own crisis events'
  ) THEN
    CREATE POLICY "Users can view own crisis events" ON crisis_events
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- Ensure RLS is enabled on all chat tables
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE crisis_events ENABLE ROW LEVEL SECURITY;

-- 4. Rate limiting table and function
CREATE TABLE IF NOT EXISTS rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  request_count INT NOT NULL DEFAULT 1,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_user_endpoint ON rate_limits(user_id, endpoint);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window_start ON rate_limits(window_start);

COMMENT ON TABLE rate_limits IS 'Tracks API request counts for rate limiting';

-- Rate limiting function (sliding window counter)
CREATE OR REPLACE FUNCTION check_rate_limit(
  p_user_id UUID,
  p_endpoint TEXT,
  p_window_start TIMESTAMPTZ,
  p_max_requests INT,
  p_window_ms INT
)
RETURNS TABLE(
  allowed BOOLEAN,
  remaining INT,
  reset_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INT;
  v_window_start TIMESTAMPTZ;
  v_reset_at TIMESTAMPTZ;
BEGIN
  -- Try to get existing record with lock
  SELECT request_count, window_start
  INTO v_count, v_window_start
  FROM rate_limits
  WHERE user_id = p_user_id AND endpoint = p_endpoint
  FOR UPDATE;

  IF NOT FOUND THEN
    -- First request, create record
    INSERT INTO rate_limits (user_id, endpoint, request_count, window_start)
    VALUES (p_user_id, p_endpoint, 1, NOW())
    ON CONFLICT (user_id, endpoint) DO UPDATE
    SET request_count = 1, window_start = NOW();

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  -- Check if window has expired
  IF v_window_start < p_window_start THEN
    -- Reset window
    UPDATE rate_limits
    SET request_count = 1, window_start = NOW()
    WHERE user_id = p_user_id AND endpoint = p_endpoint;

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  -- Window is still active
  v_reset_at := v_window_start + (p_window_ms || ' milliseconds')::interval;

  IF v_count >= p_max_requests THEN
    -- Rate limit exceeded
    RETURN QUERY SELECT FALSE, 0, v_reset_at;
    RETURN;
  END IF;

  -- Increment counter
  UPDATE rate_limits
  SET request_count = v_count + 1
  WHERE user_id = p_user_id AND endpoint = p_endpoint;

  RETURN QUERY SELECT TRUE, p_max_requests - v_count - 1, v_reset_at;
END;
$$;

COMMENT ON FUNCTION check_rate_limit IS 'Atomically checks and updates rate limit counters using sliding window';

-- RLS for rate_limits (service role only)
ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;

-- No user policies - only service role can access rate_limits
