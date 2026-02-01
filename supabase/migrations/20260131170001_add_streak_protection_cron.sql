-- Add daily cron job to check streak protection for all users
-- This ensures shields are applied even if users don't open the app
-- Runs at 06:00 UTC daily (before most users wake up)

DO $outer$
BEGIN
    -- Check if pg_cron and pg_net are available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
       AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN

        -- Remove old job if exists (ignore if doesn't exist)
        BEGIN
            PERFORM cron.unschedule('daily-streak-protection-check');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- Schedule daily check at 06:00 UTC
        -- This runs before most users wake up, ensuring shields are applied proactively
        PERFORM cron.schedule(
            'daily-streak-protection-check',
            '0 6 * * *',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/check-streak-protection'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Scheduled daily-streak-protection-check cron job at 06:00 UTC';
    ELSE
        RAISE WARNING 'pg_cron or pg_net extension not available - streak protection cron not scheduled';
        RAISE NOTICE 'To enable: CREATE EXTENSION pg_cron WITH SCHEMA pg_catalog; CREATE EXTENSION pg_net;';
    END IF;
END $outer$;
