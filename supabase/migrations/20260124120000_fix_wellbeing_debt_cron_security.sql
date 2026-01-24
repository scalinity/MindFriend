-- N006: Wellbeing Debt Calculator - Security Fix for Cron Jobs
-- Replaces hardcoded service role keys with environment-based approach
-- Migration created: 2026-01-24

-- SECURITY FIX: Remove cron jobs with hardcoded credentials
-- Replace with PL/pgSQL functions that use database settings

-- Unschedule existing jobs with hardcoded keys
DO $$
BEGIN
  PERFORM cron.unschedule(job_id)
  FROM cron.job
  WHERE jobname IN ('detect-transactions-daily', 'calculate-debt-score-daily');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- Create secure wrapper function for detect-transactions
CREATE OR REPLACE FUNCTION execute_detect_transactions_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  service_key TEXT;
  base_url TEXT;
BEGIN
  -- Retrieve service role key from database settings
  -- Set via: ALTER DATABASE postgres SET app.service_role_key = '<key>';
  service_key := current_setting('app.service_role_key', true);
  
  -- Fallback to environment variable if not set
  IF service_key IS NULL OR service_key = '' THEN
    RAISE EXCEPTION 'app.service_role_key not configured in database settings';
  END IF;

  -- Get Supabase URL from settings
  base_url := current_setting('app.supabase_url', true);
  IF base_url IS NULL OR base_url = '' THEN
    RAISE EXCEPTION 'app.supabase_url not configured in database settings';
  END IF;

  -- Execute HTTP request
  PERFORM net.http_post(
    url := base_url || '/functions/v1/detect-transactions',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || service_key,
      'Content-Type', 'application/json'
    )
  );
END;
$$;

-- Create secure wrapper function for calculate-debt-score
CREATE OR REPLACE FUNCTION execute_calculate_debt_score_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  service_key TEXT;
  base_url TEXT;
BEGIN
  -- Retrieve service role key from database settings
  service_key := current_setting('app.service_role_key', true);
  
  IF service_key IS NULL OR service_key = '' THEN
    RAISE EXCEPTION 'app.service_role_key not configured in database settings';
  END IF;

  -- Get Supabase URL from settings
  base_url := current_setting('app.supabase_url', true);
  IF base_url IS NULL OR base_url = '' THEN
    RAISE EXCEPTION 'app.supabase_url not configured in database settings';
  END IF;

  -- Execute HTTP request
  PERFORM net.http_post(
    url := base_url || '/functions/v1/calculate-debt-score',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || service_key,
      'Content-Type', 'application/json'
    )
  );
END;
$$;

-- Schedule new secure cron jobs
SELECT cron.schedule(
  'detect-transactions-daily',
  '0 1 * * *',  -- Every day at 1:00 AM UTC
  'SELECT execute_detect_transactions_cron();'
);

SELECT cron.schedule(
  'calculate-debt-score-daily',
  '0 2 * * *',  -- Every day at 2:00 AM UTC
  'SELECT execute_calculate_debt_score_cron();'
);

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION execute_detect_transactions_cron() TO postgres;
GRANT EXECUTE ON FUNCTION execute_calculate_debt_score_cron() TO postgres;

-- Add helpful comments
COMMENT ON FUNCTION execute_detect_transactions_cron() IS 
  'N006: Secure wrapper for detect-transactions Edge Function cron job';
COMMENT ON FUNCTION execute_calculate_debt_score_cron() IS 
  'N006: Secure wrapper for calculate-debt-score Edge Function cron job';

-- Log successful migration
DO $$
BEGIN
  RAISE NOTICE 'N006 cron jobs updated with secure credential handling';
  RAISE NOTICE 'MANUAL STEP REQUIRED: Set database config via:';
  RAISE NOTICE 'ALTER DATABASE postgres SET app.service_role_key = ''<your-service-role-key>'';';
  RAISE NOTICE 'ALTER DATABASE postgres SET app.supabase_url = ''<your-supabase-url>'';';
END $$;
