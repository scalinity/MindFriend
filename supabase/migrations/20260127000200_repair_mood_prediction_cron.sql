-- =====================================================
-- Repair: Mood Prediction Cron Job
-- Ensures cron job is properly scheduled
-- =====================================================
--
-- MANUAL SETUP REQUIRED:
--
-- 1. Go to Supabase Dashboard > Project Settings > Vault
--    Add a new secret:
--    - Name: cron_secret
--    - Value: (generate a secure random string, e.g., openssl rand -base64 32)
--
-- 2. Go to Supabase Dashboard > Edge Functions > predict-mood > Secrets
--    Add environment variable:
--    - CRON_SECRET = (same value as step 1)
--
-- 3. Verify pg_cron is enabled:
--    SELECT * FROM pg_extension WHERE extname = 'pg_cron';
--
-- 4. After running this migration, verify the job is scheduled:
--    SELECT * FROM cron.job WHERE jobname = 'predict-mood-hourly';
--
-- =====================================================

-- Note: pg_cron and pg_net extensions should already be enabled
-- If not, enable them manually in Supabase Dashboard > Database > Extensions

-- Re-create the cron job
DO $outer$
BEGIN
    -- Check if pg_cron is available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Remove existing job if it exists
        BEGIN
            PERFORM cron.unschedule('predict-mood-hourly');
            RAISE NOTICE 'Removed existing predict-mood-hourly job';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'No existing job to remove (this is fine)';
        END;

        -- Schedule new job to run every hour at minute 5
        PERFORM cron.schedule(
            'predict-mood-hourly',
            '5 * * * *',
            $cron$
            SELECT net.http_post(
                url := current_setting('app.settings.supabase_url', true) || '/functions/v1/predict-mood',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'x-cron-secret', public.get_cron_secret()
                ),
                body := '{}'::jsonb
            )
            $cron$
        );

        RAISE NOTICE '✅ Cron job predict-mood-hourly scheduled successfully';
        RAISE NOTICE 'Job runs at minute 5 of every hour';
        RAISE NOTICE 'IMPORTANT: Ensure CRON_SECRET is set in both Vault and Edge Function secrets';
    ELSE
        RAISE WARNING '❌ pg_cron extension not available';
        RAISE NOTICE 'Enable it: CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog;';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Could not schedule cron job: %', SQLERRM;
END $outer$;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;
