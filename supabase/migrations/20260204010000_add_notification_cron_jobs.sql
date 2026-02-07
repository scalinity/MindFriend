-- Add missing cron jobs for notification edge functions
-- These functions exist but were never scheduled:
-- 1. check-lapsed-users: Re-engagement notifications (day 3/7/14/30)
-- 2. proactive-scheduler: Proactive mood/streak/milestone notifications
-- 3. process-notification-queue: Drain quiet-hours notification queue
-- 4. send-weekly-summary: Weekly email + push summary

DO $outer$
BEGIN
    -- Check if pg_cron and pg_net are available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
       AND EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN

        -- ============================================================
        -- 1. check-lapsed-users: Every 6 hours
        -- Identifies users absent for 3/7/14/30 days and sends
        -- tiered re-engagement notifications
        -- ============================================================
        BEGIN
            PERFORM cron.unschedule('check-lapsed-users-periodic');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'check-lapsed-users-periodic',
            '0 */6 * * *',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/check-lapsed-users'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''X-Cron-Secret'', current_setting(''app.settings.cron_secret'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Scheduled check-lapsed-users-periodic cron job (every 6 hours)';

        -- ============================================================
        -- 2. proactive-scheduler: Every 2 hours
        -- Identifies users needing proactive outreach based on
        -- mood decline, streak risk, milestones, and inactivity
        -- ============================================================
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

        RAISE NOTICE 'Scheduled proactive-scheduler-periodic cron job (every 2 hours)';

        -- ============================================================
        -- 3. process-notification-queue: Every hour
        -- Processes notifications that were queued during quiet hours
        -- and sends them once quiet hours end
        -- ============================================================
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

        RAISE NOTICE 'Scheduled process-notification-queue-hourly cron job (every hour at :30)';

        -- ============================================================
        -- 4. send-weekly-summary: Sunday 10 AM UTC
        -- Generates weekly email summaries and push notifications
        -- ============================================================
        BEGIN
            PERFORM cron.unschedule('weekly-summary-send');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'weekly-summary-send',
            '0 10 * * 0',
            E'SELECT net.http_post(\n'
            '    url := current_setting(''app.settings.supabase_url'') || ''/functions/v1/send-weekly-summary'',\n'
            '    headers := jsonb_build_object(\n'
            '        ''Content-Type'', ''application/json'',\n'
            '        ''Authorization'', ''Bearer '' || current_setting(''app.settings.service_role_key'')\n'
            '    ),\n'
            '    body := ''{}''::jsonb\n'
            ');'
        );

        RAISE NOTICE 'Scheduled weekly-summary-send cron job (Sunday 10 AM UTC)';

    ELSE
        RAISE WARNING 'pg_cron or pg_net extension not available - notification cron jobs not scheduled';
    END IF;
END $outer$;
