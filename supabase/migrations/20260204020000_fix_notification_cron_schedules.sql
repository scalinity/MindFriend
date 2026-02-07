-- Fix notification cron schedules: reduce frequency
-- proactive-scheduler: 15min → 2 hours (mood/streak patterns don't change that fast)
-- process-notification-queue: 15min → hourly (quiet hours are multi-hour windows)

DO $outer$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN

        -- Remove old 15-min jobs
        BEGIN
            PERFORM cron.unschedule('proactive-scheduler-15min');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        BEGIN
            PERFORM cron.unschedule('process-notification-queue-15min');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        -- Schedule proactive-scheduler every 2 hours
        BEGIN
            PERFORM cron.unschedule('proactive-scheduler-periodic');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'proactive-scheduler-periodic',
            '0 */2 * * *',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/proactive-scheduler'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Rescheduled proactive-scheduler to every 2 hours';

        -- Schedule process-notification-queue every hour at :30
        BEGIN
            PERFORM cron.unschedule('process-notification-queue-hourly');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'process-notification-queue-hourly',
            '30 * * * *',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/process-notification-queue'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Rescheduled process-notification-queue to every hour at :30';

    END IF;
END $outer$;
