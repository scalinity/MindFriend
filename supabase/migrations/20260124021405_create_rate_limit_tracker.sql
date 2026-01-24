-- Rate Limit Tracker Table
-- Simple table for tracking API request counts for rate limiting

DROP TABLE IF EXISTS rate_limit_tracker CASCADE;

CREATE TABLE rate_limit_tracker (
  id BIGSERIAL PRIMARY KEY,
  key TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookups by key and timestamp
CREATE INDEX IF NOT EXISTS idx_rate_limit_key_timestamp
  ON rate_limit_tracker(key, timestamp DESC);

-- Enable RLS (even though this is internal use only)
ALTER TABLE rate_limit_tracker ENABLE ROW LEVEL SECURITY;

-- Service role can do anything (Edge Functions use service role)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'rate_limit_tracker'
    AND policyname = 'Service role full access'
  ) THEN
    CREATE POLICY "Service role full access"
      ON rate_limit_tracker
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- Automatic cleanup function (delete records older than 24 hours)
CREATE OR REPLACE FUNCTION cleanup_rate_limit_tracker()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM rate_limit_tracker
  WHERE timestamp < NOW() - INTERVAL '24 hours';
END;
$$;

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION cleanup_rate_limit_tracker() TO service_role;

COMMENT ON TABLE rate_limit_tracker IS 'Tracks API request counts for rate limiting in Edge Functions';
COMMENT ON FUNCTION cleanup_rate_limit_tracker() IS 'Cleans up rate limit records older than 24 hours';
