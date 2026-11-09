-- Proposed scheduled-work repair. DO NOT APPLY without production and new-secret approval.

-- Keep HTTP workloads held until their individual synthetic tests, delivery rules,

-- provider budget and backlog review are approved. Seven SQL maintenance jobs stay scheduled.

-- Requires the audited RPC/security changes and a matching CRON_SECRET in Vault/Edge secrets.

BEGIN;

CREATE OR REPLACE FUNCTION public.invoke_mindfriend_cron(p_slug text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $body$
DECLARE secret text; request_id bigint;
BEGIN
  IF p_slug IS NULL OR p_slug <> ALL (ARRAY['agent-act','agent-monitor','aggregate-efficacy-profiles','calculate-debt-score','check-lapsed-users','check-streak-protection','check-streak-risk','detect-transactions','predict-mood','proactive-scheduler','process-notification-queue','send-assessment-reminders','send-weekly-summary']) THEN
    RAISE EXCEPTION 'Unknown scheduled workload' USING ERRCODE='22023';
  END IF;
  secret := public.get_cron_secret();
  IF secret IS NULL OR secret='' THEN RAISE EXCEPTION 'Cron credential is not configured' USING ERRCODE='55000'; END IF;
  SELECT net.http_post(url := 'https://zfaucivtzfwnrijsbfug.supabase.co/functions/v1/'||p_slug,
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpmYXVjaXZ0emZ3bnJpanNiZnVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyNTI2NDgsImV4cCI6MjA4MzgyODY0OH0.tZaiIYvZKLUZFoNl2nvfRbOj8lodtY7Kw7BiQyoK2Rk','x-cron-secret',secret),
    body := '{}'::jsonb, timeout_milliseconds := 10000) INTO request_id;
  RETURN request_id;
END;
$body$;

REVOKE EXECUTE ON FUNCTION public.invoke_mindfriend_cron(text) FROM PUBLIC,anon,authenticated;

GRANT EXECUTE ON FUNCTION public.invoke_mindfriend_cron(text) TO service_role;

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=58 AND jobname='aggregate-efficacy-profiles-nightly' AND md5(command)='c8802b92b047ef18a085c70c1f900195') THEN RAISE EXCEPTION 'Schedule drift; review job 58 before repair'; END IF; END $$;

SELECT cron.alter_job(58, command := 'SELECT public.invoke_mindfriend_cron(''aggregate-efficacy-profiles'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=76 AND jobname='process-notification-queue-hourly' AND md5(command)='81cf64a9d93988228a01c0f0932bf36b') THEN RAISE EXCEPTION 'Schedule drift; review job 76 before repair'; END IF; END $$;

SELECT cron.alter_job(76, command := 'SELECT public.invoke_mindfriend_cron(''process-notification-queue'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=77 AND jobname='agent-monitor-periodic' AND md5(command)='89df67e9f61a7db34ff64954fa8f4fe6') THEN RAISE EXCEPTION 'Schedule drift; review job 77 before repair'; END IF; END $$;

SELECT cron.alter_job(77, command := 'SELECT public.invoke_mindfriend_cron(''agent-monitor'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=59 AND jobname='detect-transactions-daily' AND md5(command)='76e31bfbca441c1a99f772bb3336d440') THEN RAISE EXCEPTION 'Schedule drift; review job 59 before repair'; END IF; END $$;

SELECT cron.alter_job(59, command := 'SELECT public.invoke_mindfriend_cron(''detect-transactions'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=60 AND jobname='calculate-debt-score-daily' AND md5(command)='b2b124295b7fbb3c3a08f12bd8163f7e') THEN RAISE EXCEPTION 'Schedule drift; review job 60 before repair'; END IF; END $$;

SELECT cron.alter_job(60, command := 'SELECT public.invoke_mindfriend_cron(''calculate-debt-score'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=67 AND jobname='predict-mood-hourly' AND md5(command)='1c4e8639f7aac5356c8ced1642c5b7fe') THEN RAISE EXCEPTION 'Schedule drift; review job 67 before repair'; END IF; END $$;

SELECT cron.alter_job(67, command := 'SELECT public.invoke_mindfriend_cron(''predict-mood'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=68 AND jobname='send-assessment-reminders-daily' AND md5(command)='cda2707aa0a0ccbf21386677a91c1c1b') THEN RAISE EXCEPTION 'Schedule drift; review job 68 before repair'; END IF; END $$;

SELECT cron.alter_job(68, command := 'SELECT public.invoke_mindfriend_cron(''send-assessment-reminders'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=69 AND jobname='daily-streak-protection-check' AND md5(command)='6bf9e704b273a1892506eb0ebf654e0a') THEN RAISE EXCEPTION 'Schedule drift; review job 69 before repair'; END IF; END $$;

SELECT cron.alter_job(69, command := 'SELECT public.invoke_mindfriend_cron(''check-streak-protection'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=70 AND jobname='hourly-streak-risk-check' AND md5(command)='09f84c18666dfb03b43cf98464f218b6') THEN RAISE EXCEPTION 'Schedule drift; review job 70 before repair'; END IF; END $$;

SELECT cron.alter_job(70, command := 'SELECT public.invoke_mindfriend_cron(''check-streak-risk'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=71 AND jobname='check-lapsed-users-periodic' AND md5(command)='ed84e67892d54e6e1f7973634aa9f129') THEN RAISE EXCEPTION 'Schedule drift; review job 71 before repair'; END IF; END $$;

SELECT cron.alter_job(71, command := 'SELECT public.invoke_mindfriend_cron(''check-lapsed-users'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=74 AND jobname='weekly-summary-send' AND md5(command)='bb7c46696d1c949ebd9070e68ffd9a12') THEN RAISE EXCEPTION 'Schedule drift; review job 74 before repair'; END IF; END $$;

SELECT cron.alter_job(74, command := 'SELECT public.invoke_mindfriend_cron(''send-weekly-summary'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=75 AND jobname='proactive-scheduler-periodic' AND md5(command)='44614e0c1bd1fc9e26fa3d8883bdcb88') THEN RAISE EXCEPTION 'Schedule drift; review job 75 before repair'; END IF; END $$;

SELECT cron.alter_job(75, command := 'SELECT public.invoke_mindfriend_cron(''proactive-scheduler'');', active := false);

DO $$ BEGIN IF NOT EXISTS(SELECT FROM cron.job WHERE jobid=78 AND jobname='agent-act-periodic' AND md5(command)='57fc890e0f46899d3010411b285785b0') THEN RAISE EXCEPTION 'Schedule drift; review job 78 before repair'; END IF; END $$;

SELECT cron.alter_job(78, command := 'SELECT public.invoke_mindfriend_cron(''agent-act'');', active := false);

COMMIT;
