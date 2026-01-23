-- ============================================================================
-- SOCIAL VITALITY INDEX: CRON JOB CONFIGURATION
-- ============================================================================
-- Migration: 20260123090000_social_vitality_cron_jobs.sql
-- Purpose: Configure pg_cron jobs to run Social Vitality Edge Functions daily
-- Dependencies: 20260123080000_social_vitality_index.sql
--
-- Schedule:
-- 1. aggregate-interaction-metrics: 00:00 UTC (midnight)
-- 2. calculate-social-vitality: 00:05 UTC (after aggregation)
-- 3. detect-withdrawal: 00:10 UTC (after score calculation)
-- ============================================================================

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant usage to postgres user
GRANT USAGE ON SCHEMA cron TO postgres;

-- ============================================================================
-- CLEANUP: Remove existing jobs if they exist (idempotent)
-- ============================================================================

DO $$
BEGIN
    -- Remove existing jobs (ignore errors if they don't exist)
    PERFORM cron.unschedule('aggregate-interaction-metrics-daily');
    PERFORM cron.unschedule('calculate-social-vitality-daily');
    PERFORM cron.unschedule('detect-withdrawal-daily');
EXCEPTION WHEN OTHERS THEN
    NULL; -- Ignore errors if jobs don't exist
END $$;

-- ============================================================================
-- JOB 1: Aggregate Interaction Metrics (Daily at 00:00 UTC)
-- ============================================================================
-- Purpose: Aggregate circle_posts into interaction_metrics for previous day
-- Runs: Daily at midnight UTC
-- Expected duration: 1-2 minutes for 1,000 users

SELECT cron.schedule(
    'aggregate-interaction-metrics-daily',
    '0 0 * * *',  -- Every day at 00:00 UTC
    $$
    SELECT
      net.http_post(
          url:='https://' || current_setting('app.settings.project_ref') || '.supabase.co/functions/v1/aggregate-interaction-metrics',
          headers:='{"Content-Type": "application/json", "Authorization": "Bearer ' || current_setting('app.settings.service_role_key') || '"}'::jsonb,
          body:='{}'::jsonb
      ) as request_id;
    $$
);

COMMENT ON EXTENSION pg_cron IS 'Social Vitality Index daily cron jobs';

-- ============================================================================
-- JOB 2: Calculate Social Vitality Scores (Daily at 00:05 UTC)
-- ============================================================================
-- Purpose: Calculate daily social vitality scores for all active users
-- Runs: Daily at 00:05 UTC (5 minutes after aggregation)
-- Expected duration: 1-2 minutes for 1,000 users

SELECT cron.schedule(
    'calculate-social-vitality-daily',
    '5 0 * * *',  -- Every day at 00:05 UTC
    $$
    SELECT
      net.http_post(
          url:='https://' || current_setting('app.settings.project_ref') || '.supabase.co/functions/v1/calculate-social-vitality',
          headers:='{"Content-Type": "application/json", "Authorization": "Bearer ' || current_setting('app.settings.service_role_key') || '"}'::jsonb,
          body:='{}'::jsonb
      ) as request_id;
    $$
);

-- ============================================================================
-- JOB 3: Detect Social Withdrawal (Daily at 00:10 UTC)
-- ============================================================================
-- Purpose: Detect social withdrawal patterns and send peer support alerts
-- Runs: Daily at 00:10 UTC (10 minutes after score calculation)
-- Expected duration: 30 seconds - 1 minute for 1,000 users

SELECT cron.schedule(
    'detect-withdrawal-daily',
    '10 0 * * *',  -- Every day at 00:10 UTC
    $$
    SELECT
      net.http_post(
          url:='https://' || current_setting('app.settings.project_ref') || '.supabase.co/functions/v1/detect-withdrawal',
          headers:='{"Content-Type": "application/json", "Authorization": "Bearer ' || current_setting('app.settings.service_role_key') || '"}'::jsonb,
          body:='{}'::jsonb
      ) as request_id;
    $$
);

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- View all scheduled jobs
DO $$
BEGIN
    RAISE NOTICE 'Social Vitality cron jobs configured:';
    RAISE NOTICE '  1. aggregate-interaction-metrics-daily: 00:00 UTC';
    RAISE NOTICE '  2. calculate-social-vitality-daily: 00:05 UTC';
    RAISE NOTICE '  3. detect-withdrawal-daily: 00:10 UTC';
    RAISE NOTICE '';
    RAISE NOTICE 'To view job status: SELECT * FROM cron.job;';
    RAISE NOTICE 'To view job history: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;';
END $$;

-- ============================================================================
-- ROLLBACK (for development/testing)
-- ============================================================================
-- To remove these cron jobs, run:
-- SELECT cron.unschedule('aggregate-interaction-metrics-daily');
-- SELECT cron.unschedule('calculate-social-vitality-daily');
-- SELECT cron.unschedule('detect-withdrawal-daily');
-- ============================================================================

-- Verify cron jobs were created
DO $$
DECLARE
    v_job_count INTEGER;
    v_job_names TEXT;
BEGIN
    SELECT COUNT(*), string_agg(jobname, ', ') INTO v_job_count, v_job_names
    FROM cron.job
    WHERE jobname IN (
        'aggregate-interaction-metrics-daily',
        'calculate-social-vitality-daily',
        'detect-withdrawal-daily'
    );

    IF v_job_count < 3 THEN
        RAISE EXCEPTION 'Expected 3 cron jobs, found % (%)', v_job_count, COALESCE(v_job_names, 'none');
    END IF;

    RAISE NOTICE 'SUCCESS: All % Social Vitality cron jobs configured: %', v_job_count, v_job_names;
END $$;
