-- Intervention Efficacy Engine: Cron Job Setup
-- Schedule aggregate-efficacy-profiles to run nightly at 2 AM UTC

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove existing job if it exists (idempotent)
DO $$
BEGIN
  PERFORM cron.unschedule(job_id)
  FROM cron.job
  WHERE jobname = 'aggregate-efficacy-profiles-nightly';
EXCEPTION WHEN OTHERS THEN
  -- Job doesn't exist yet, that's fine
  NULL;
END $$;

-- Schedule aggregate-efficacy-profiles to run nightly at 2 AM UTC
-- Note: Supabase requires hardcoded URL and service role key in cron jobs
SELECT cron.schedule(
  'aggregate-efficacy-profiles-nightly',  -- Job name
  '0 2 * * *',                            -- Schedule: 2 AM UTC daily
  $$
  SELECT net.http_post(
    url := 'https://zfaucivtzfwnrijsbfug.supabase.co/functions/v1/aggregate-efficacy-profiles',
    headers := jsonb_build_object(
      'Authorization', 'Bearer 6b65582b222e549585cfa8d26dc45c54f385f768db28dba3f6ba3e70ebe573aa',
      'Content-Type', 'application/json'
    )
  ) as request_id;
  $$
);

-- Add helpful comment
COMMENT ON EXTENSION pg_cron IS 'Cron-based job scheduler for PostgreSQL';

-- Log successful creation
DO $$
DECLARE
  job_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO job_count
  FROM cron.job
  WHERE jobname = 'aggregate-efficacy-profiles-nightly';

  IF job_count > 0 THEN
    RAISE NOTICE 'Cron job "aggregate-efficacy-profiles-nightly" created successfully';
  ELSE
    RAISE WARNING 'Cron job may not have been created - check cron.job table';
  END IF;
END $$;
