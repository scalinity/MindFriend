-- Error Monitoring Tables
-- Tables for tracking errors and alerts across Edge Functions

-- Error Events Table (tracks all errors)
DROP TABLE IF EXISTS error_events CASCADE;

CREATE TABLE error_events (
  id BIGSERIAL PRIMARY KEY,
  function_name TEXT NOT NULL,
  error_type TEXT NOT NULL,
  error_message TEXT NOT NULL,
  error_stack TEXT,
  context JSONB DEFAULT '{}'::jsonb,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookups by function and timestamp
CREATE INDEX IF NOT EXISTS idx_error_events_function_timestamp
  ON error_events(function_name, timestamp DESC);

-- Index for error type analysis
CREATE INDEX IF NOT EXISTS idx_error_events_type
  ON error_events(error_type, timestamp DESC);

-- Error Alerts Table (tracks alert events when thresholds exceeded)
DROP TABLE IF EXISTS error_alerts CASCADE;

CREATE TABLE error_alerts (
  id BIGSERIAL PRIMARY KEY,
  function_name TEXT NOT NULL,
  error_rate DECIMAL(5,4) NOT NULL,
  threshold DECIMAL(5,4) NOT NULL,
  window_minutes INTEGER NOT NULL,
  message TEXT NOT NULL,
  acknowledged BOOLEAN DEFAULT FALSE,
  acknowledged_at TIMESTAMPTZ,
  acknowledged_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for active alerts
CREATE INDEX IF NOT EXISTS idx_error_alerts_active
  ON error_alerts(function_name, created_at DESC)
  WHERE acknowledged = FALSE;

-- Index for all alerts by function
CREATE INDEX IF NOT EXISTS idx_error_alerts_function
  ON error_alerts(function_name, created_at DESC);

-- Enable RLS (even though this is internal use only)
ALTER TABLE error_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE error_alerts ENABLE ROW LEVEL SECURITY;

-- Service role can do anything (Edge Functions use service role)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'error_events'
    AND policyname = 'Service role full access'
  ) THEN
    CREATE POLICY "Service role full access"
      ON error_events
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'error_alerts'
    AND policyname = 'Service role full access'
  ) THEN
    CREATE POLICY "Service role full access"
      ON error_alerts
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- Automatic cleanup function (delete records older than 7 days)
CREATE OR REPLACE FUNCTION cleanup_error_monitoring()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Clean up old error events (>7 days)
  DELETE FROM error_events
  WHERE timestamp < NOW() - INTERVAL '7 days';

  -- Clean up old acknowledged alerts (>7 days)
  DELETE FROM error_alerts
  WHERE acknowledged = TRUE
  AND acknowledged_at < NOW() - INTERVAL '7 days';
END;
$$;

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION cleanup_error_monitoring() TO service_role;

-- View for error rate analysis
CREATE OR REPLACE VIEW error_rate_summary AS
SELECT
  function_name,
  DATE_TRUNC('hour', timestamp) AS hour,
  COUNT(*) AS error_count,
  COUNT(DISTINCT error_type) AS unique_error_types,
  ARRAY_AGG(DISTINCT error_type) AS error_types
FROM error_events
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY function_name, DATE_TRUNC('hour', timestamp)
ORDER BY hour DESC, error_count DESC;

-- View for recent unacknowledged alerts
CREATE OR REPLACE VIEW active_alerts AS
SELECT
  id,
  function_name,
  ROUND((error_rate * 100)::numeric, 2) AS error_rate_pct,
  ROUND((threshold * 100)::numeric, 2) AS threshold_pct,
  window_minutes,
  message,
  created_at,
  (NOW() - created_at) AS age
FROM error_alerts
WHERE acknowledged = FALSE
AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

COMMENT ON TABLE error_events IS 'Tracks all error occurrences across Edge Functions for monitoring and analysis';
COMMENT ON TABLE error_alerts IS 'Records alert events when error rate thresholds are exceeded';
COMMENT ON FUNCTION cleanup_error_monitoring() IS 'Cleans up error events and acknowledged alerts older than 7 days';
COMMENT ON VIEW error_rate_summary IS 'Hourly error rate summary for the past 24 hours';
COMMENT ON VIEW active_alerts IS 'Unacknowledged alerts from the past 24 hours';
