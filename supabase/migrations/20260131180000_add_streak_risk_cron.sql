-- Add hourly cron job for streak risk notifications
-- Sends reminders at 6 PM and 9 PM user's local time if they haven't completed quest
-- Edge Function: check-streak-risk

DO $outer$
BEGIN
    -- Check if pg_cron and pg_net are available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
       AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN

        -- Remove old job if exists (ignore if doesn't exist)
        BEGIN
            PERFORM cron.unschedule('hourly-streak-risk-check');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- Schedule hourly check (runs every hour at minute 0)
        -- The Edge Function handles timezone logic to send at 6 PM and 9 PM local time
        PERFORM cron.schedule(
            'hourly-streak-risk-check',
            '0 * * * *',  -- Every hour at minute 0
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/check-streak-risk'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Scheduled hourly-streak-risk-check cron job (every hour at :00)';
    ELSE
        RAISE WARNING 'pg_cron or pg_net extension not available - streak risk cron not scheduled';
    END IF;
END $outer$;
