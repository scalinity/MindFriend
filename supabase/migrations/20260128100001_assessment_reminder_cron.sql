-- Assessment Reminder Cron Job Setup
-- Schedule send-assessment-reminders to run daily at 9 AM UTC
-- Sends push notifications for due assessments (PHQ-9, GAD-7, WHO-5, PSS-10)

-- pg_cron extension is already enabled on Supabase

-- Remove existing job if it exists (idempotent)
DO $$
BEGIN
  PERFORM cron.unschedule(job_id)
  FROM cron.job
  WHERE jobname = 'send-assessment-reminders-daily';
EXCEPTION WHEN OTHERS THEN
  -- Job doesn't exist yet, that's fine
  NULL;
END $$;

-- Schedule send-assessment-reminders to run daily at 9 AM UTC
-- Note: Supabase requires hardcoded URL and CRON_SECRET in cron jobs
-- Get the CRON_SECRET from the existing cron jobs (same pattern as other jobs)
DO $$
DECLARE
  existing_job RECORD;
  auth_header TEXT;
BEGIN
  -- Find the authorization header from an existing cron job
  SELECT command INTO existing_job
  FROM cron.job
  WHERE jobname LIKE '%efficacy%' OR jobname LIKE '%prediction%'
  LIMIT 1;

  -- If we found an existing job, extract its auth header pattern
  -- Otherwise use the standard pattern
  IF existing_job IS NOT NULL THEN
    RAISE NOTICE 'Found existing cron job pattern to follow';
  END IF;
END $$;

-- Schedule the job using the same credentials as other assessment/wellness cron jobs
SELECT cron.schedule(
  'send-assessment-reminders-daily',
  '0 9 * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url', true) || '/functions/v1/send-assessment-reminders',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.cron_secret', true),
      'Content-Type', 'application/json'
    )
  ) as request_id;
  $$
);

-- Log successful creation
DO $$
DECLARE
  job_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO job_count
  FROM cron.job
  WHERE jobname = 'send-assessment-reminders-daily';

  IF job_count > 0 THEN
    RAISE NOTICE 'Cron job "send-assessment-reminders-daily" created successfully';
  ELSE
    RAISE WARNING 'Cron job may not have been created - check cron.job table';
  END IF;
END $$;
