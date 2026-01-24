-- N006: Wellbeing Debt Calculator - Cron Job Setup
-- Sets up daily scheduled jobs for transaction detection and debt calculation

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove existing N006 jobs if they exist (idempotent)
DO $$
BEGIN
  -- Remove detect-transactions job
  PERFORM cron.unschedule(job_id)
  FROM cron.job
  WHERE jobname = 'detect-transactions-daily';

  -- Remove calculate-debt-score job
  PERFORM cron.unschedule(job_id)
  FROM cron.job
  WHERE jobname = 'calculate-debt-score-daily';
EXCEPTION WHEN OTHERS THEN
  -- Jobs dont exist yet, thats fine
  NULL;
END $$;

-- Schedule detect-transactions Edge Function to run daily at 1:00 AM UTC
-- This function detects all deposits and withdrawals from data sources
-- Note: Supabase requires hardcoded URL and service role key in cron jobs
SELECT cron.schedule(
  'detect-transactions-daily',
  '0 1 * * *',  -- Every day at 1:00 AM UTC
  $$
  SELECT net.http_post(
    url := 'https://zfaucivtzfwnrijsbfug.supabase.co/functions/v1/detect-transactions',
    headers := jsonb_build_object(
      'Authorization', 'Bearer 6b65582b222e549585cfa8d26dc45c54f385f768db28dba3f6ba3e70ebe573aa',
      'Content-Type', 'application/json'
    )
  ) as request_id;
  $$
);

-- Schedule calculate-debt-score Edge Function to run daily at 2:00 AM UTC
-- This function calculates rolling debts, trends, and updates profiles
-- Runs AFTER detect-transactions to ensure fresh data is available
SELECT cron.schedule(
  'calculate-debt-score-daily',
  '0 2 * * *',  -- Every day at 2:00 AM UTC
  $$
  SELECT net.http_post(
    url := 'https://zfaucivtzfwnrijsbfug.supabase.co/functions/v1/calculate-debt-score',
    headers := jsonb_build_object(
      'Authorization', 'Bearer 6b65582b222e549585cfa8d26dc45c54f385f768db28dba3f6ba3e70ebe573aa',
      'Content-Type', 'application/json'
    )
  ) as request_id;
  $$
);

-- Grant necessary permissions for cron jobs
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

-- Log successful creation
DO $$
DECLARE
  detect_count INTEGER;
  calculate_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO detect_count
  FROM cron.job
  WHERE jobname = 'detect-transactions-daily';

  SELECT COUNT(*) INTO calculate_count
  FROM cron.job
  WHERE jobname = 'calculate-debt-score-daily';

  IF detect_count > 0 AND calculate_count > 0 THEN
    RAISE NOTICE 'N006 cron jobs created successfully';
  ELSE
    RAISE WARNING 'N006 cron jobs may not have been created - check cron.job table';
  END IF;
END $$;
