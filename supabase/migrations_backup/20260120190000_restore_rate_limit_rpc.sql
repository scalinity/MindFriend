-- Restore rate limit table and RPC used by Edge functions

CREATE TABLE IF NOT EXISTS rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  request_count INT NOT NULL DEFAULT 1,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_user_endpoint
  ON rate_limits(user_id, endpoint);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window_start
  ON rate_limits(window_start);

ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;

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
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_window_start TIMESTAMPTZ;
  v_reset_at TIMESTAMPTZ;
BEGIN
  SELECT request_count, window_start
  INTO v_count, v_window_start
  FROM rate_limits
  WHERE user_id = p_user_id AND endpoint = p_endpoint
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO rate_limits (user_id, endpoint, request_count, window_start)
    VALUES (p_user_id, p_endpoint, 1, NOW())
    ON CONFLICT (user_id, endpoint) DO UPDATE
    SET request_count = 1, window_start = NOW();

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  IF v_window_start < p_window_start THEN
    UPDATE rate_limits
    SET request_count = 1, window_start = NOW()
    WHERE user_id = p_user_id AND endpoint = p_endpoint;

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  v_reset_at := v_window_start + (p_window_ms || ' milliseconds')::interval;

  IF v_count >= p_max_requests THEN
    RETURN QUERY SELECT FALSE, 0, v_reset_at;
    RETURN;
  END IF;

  UPDATE rate_limits
  SET request_count = v_count + 1
  WHERE user_id = p_user_id AND endpoint = p_endpoint;

  RETURN QUERY SELECT TRUE, p_max_requests - v_count - 1, v_reset_at;
END;
$$;
