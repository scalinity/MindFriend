-- Add cron jobs for wellness agent edge functions
-- agent-monitor: Detects mood decline, activity drop, streak risk, inactivity signals
-- agent-act: Delivers scheduled agent actions as push notifications

DO $outer$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
       AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN

        -- ============================================================
        -- 1. agent-monitor: Every 2 hours
        -- Scans user data for behavioral signals and creates scheduled actions
        -- ============================================================
        BEGIN
            PERFORM cron.unschedule('agent-monitor-periodic');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'agent-monitor-periodic',
            '0 */2 * * *',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/agent-monitor'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Scheduled agent-monitor-periodic cron job (every 2 hours)';

        -- ============================================================
        -- 2. agent-act: Every hour at :30
        -- Delivers due agent actions via send-notification
        -- ============================================================
        BEGIN
            PERFORM cron.unschedule('agent-act-periodic');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'agent-act-periodic',
            '30 * * * *',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/agent-act'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Scheduled agent-act-periodic cron job (every hour at :30)';

    ELSE
        RAISE WARNING 'pg_cron or pg_net extension not available - agent cron jobs not scheduled';
    END IF;
END $outer$;
