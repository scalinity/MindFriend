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

-- Schedule the job using the same credentials pattern as other cron jobs
DO $$
BEGIN
    -- Check if pg_cron is available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'send-assessment-reminders-daily',
            '0 9 * * *',
            $cron$
            SELECT net.http_post(
                url := 'https://zfaucivtzfwnrijsbfug.supabase.co/functions/v1/send-assessment-reminders',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'x-cron-secret', public.get_cron_secret()
                ),
                body := '{}'::jsonb
            )
            $cron$
        );
        RAISE NOTICE 'Cron job send-assessment-reminders-daily scheduled successfully';
    ELSE
        RAISE WARNING 'pg_cron extension not available - skipping scheduled reminder';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Could not schedule assessment reminder cron job: %', SQLERRM;
END $$;

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
