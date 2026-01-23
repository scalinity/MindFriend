-- =====================================================
-- Mood Prediction Cron Job Setup
-- Runs predict-mood Edge Function every hour
-- (function determines which users need predictions based on timezone)
-- =====================================================
--
-- IMPORTANT: This migration creates the cron job but requires manual setup:
--
-- 1. Store CRON_SECRET in Supabase Vault (Dashboard > Settings > Vault):
--    INSERT INTO vault.secrets (name, secret)
--    VALUES ('cron_secret', 'your-secure-cron-secret-here');
--
-- 2. Set CRON_SECRET in Edge Function environment (Dashboard > Edge Functions > Secrets):
--    CRON_SECRET = your-secure-cron-secret-here
--
-- Alternative: Use Supabase Dashboard > Database > Cron Jobs UI to set up visually
-- =====================================================

-- Enable pg_net extension if not already enabled (for HTTP calls)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Helper function to get secret from vault (if available)
CREATE OR REPLACE FUNCTION public.get_cron_secret()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    -- Try to get from vault
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'cron_secret'
    LIMIT 1;

    RETURN COALESCE(v_secret, '');
EXCEPTION
    WHEN OTHERS THEN
        RETURN '';
END;
$$;

-- Create the cron job for mood predictions
-- Runs hourly to catch users in their 6-8 AM local time window
DO $outer$
BEGIN
    -- Check if pg_cron is available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Remove existing job if it exists (ignore errors)
        BEGIN
            PERFORM cron.unschedule('predict-mood-hourly');
        EXCEPTION WHEN OTHERS THEN
            -- Job doesn't exist, that's fine
            NULL;
        END;

        -- Schedule new job to run every hour at minute 5
        -- The Edge Function will filter users based on their timezone
        PERFORM cron.schedule(
            'predict-mood-hourly',
            '5 * * * *',
            $cron$
            SELECT net.http_post(
                url := 'https://zfaucivtzfwnrijsbfug.supabase.co/functions/v1/predict-mood',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'x-cron-secret', public.get_cron_secret()
                ),
                body := '{}'::jsonb
            )
            $cron$
        );

        RAISE NOTICE 'Cron job predict-mood-hourly scheduled successfully';
    ELSE
        RAISE NOTICE 'pg_cron extension not available - cron job not scheduled';
        RAISE NOTICE 'Set up cron externally using Vercel Cron, Upstash, or similar';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail migration
        RAISE NOTICE 'Could not schedule cron job: %', SQLERRM;
        RAISE NOTICE 'Manual setup required: Use Supabase Dashboard > Database > Cron Jobs';
END $outer$;
