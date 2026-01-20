-- Add pg_cron job for automatic audit log cleanup
-- Runs daily at 3:00 AM UTC to delete expired audit logs

-- Enable pg_cron extension (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant usage to postgres role (required for cron jobs)
GRANT USAGE ON SCHEMA cron TO postgres;

-- Remove existing job if it exists (for idempotency)
SELECT cron.unschedule('cleanup-pattern-audit-logs')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'cleanup-pattern-audit-logs'
);

-- Schedule daily cleanup job at 3:00 AM UTC
SELECT cron.schedule(
  'cleanup-pattern-audit-logs',        -- Job name
  '0 3 * * *',                          -- Cron expression: daily at 3:00 AM
  $$DELETE FROM pattern_access_audit WHERE expires_at < NOW()$$
);

-- Add comment explaining the job
COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL. Used for:
- cleanup-pattern-audit-logs: Daily at 3:00 AM UTC, deletes expired audit logs (90-day TTL)';

-- Verify job was created
DO $$
DECLARE
  v_job_count INT;
BEGIN
  SELECT COUNT(*) INTO v_job_count
  FROM cron.job
  WHERE jobname = 'cleanup-pattern-audit-logs';

  IF v_job_count = 0 THEN
    RAISE EXCEPTION 'Failed to create audit cleanup cron job';
  END IF;

  RAISE NOTICE 'Audit cleanup cron job created successfully (runs daily at 3:00 AM UTC)';
END;
$$;
