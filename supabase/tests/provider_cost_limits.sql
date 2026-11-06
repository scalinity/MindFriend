-- LOCAL DISPOSABLE DATABASE ONLY; no user content or provider calls.
-- Create an EMPTY local database named provider_cost_limits_synthetic, then run:
-- psql -X -v ON_ERROR_STOP=1 -d provider_cost_limits_synthetic -f supabase/tests/provider_cost_limits.sql
-- Requires a local superuser, dblink, and local peer/trust auth for the second connection.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database() <> 'provider_cost_limits_synthetic' OR to_regclass('auth.users') IS NOT NULL THEN
    RAISE EXCEPTION 'Requires an empty disposable provider_cost_limits_synthetic database';
  END IF;
END $$;
-- Exercise the original owner, accounting, replay and client-end interleavings first.
\ir ../functions/tests/voice_relay_fixture.sql
-- Match Supabase's service role in this otherwise minimal synthetic schema.
ALTER ROLE service_role BYPASSRLS;
CREATE TEMP TABLE provider_cost_before AS
SELECT pg_get_functiondef('public.get_voice_minutes_remaining(uuid)'::regprocedure) AS remaining,
  pg_get_functiondef('public.end_voice_session(uuid,integer,integer,boolean)'::regprocedure) AS client_end,
  (SELECT count(*) FROM public.voice_sessions) AS sessions;
CREATE TABLE public.creative_quota_usage(user_id uuid, date date, ai_art_count integer,
  voice_minutes_used integer, UNIQUE(user_id, date));
\ir ../migrations/20261023083458_reserve_voice_journal_quota.sql
\ir ../migrations/20261023092051_provider_cost_limits.sql

DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM provider_cost_before WHERE
     remaining <> pg_get_functiondef('public.get_voice_minutes_remaining(uuid)'::regprocedure)
     OR client_end <> pg_get_functiondef('public.end_voice_session(uuid,integer,integer,boolean)'::regprocedure)
     OR sessions <> (SELECT count(*) FROM public.voice_sessions)) THEN
    RAISE EXCEPTION 'Existing quota, client-end or session history changed';
  END IF;
  IF EXISTS(SELECT 1 FROM public.voice_relay_reservations
     WHERE claimed_at IS NOT NULL AND budget_day IS DISTINCT FROM (claimed_at AT TIME ZONE 'UTC')::date) THEN
    RAISE EXCEPTION 'Existing admitted sessions were not included';
  END IF;
  IF (SELECT daily_seconds FROM public.voice_provider_budget) <> 0 THEN RAISE EXCEPTION 'Unsafe default'; END IF;
  IF has_table_privilege('authenticated', 'public.voice_provider_budget', 'UPDATE')
     OR has_table_privilege('anon', 'public.voice_provider_budget', 'SELECT') THEN RAISE EXCEPTION 'Budget privilege leak'; END IF;
END $$;
-- Move only this fixture's earlier synthetic sessions to the previous admission day.
UPDATE public.voice_relay_reservations SET budget_day = budget_day - 1 WHERE claimed_at IS NOT NULL;
INSERT INTO auth.users VALUES
 ('40000000-0000-4000-8000-000000000001'), ('40000000-0000-4000-8000-000000000002'),
 ('40000000-0000-4000-8000-000000000003'), ('40000000-0000-4000-8000-000000000004'),
 ('40000000-0000-4000-8000-000000000005'), ('40000000-0000-4000-8000-000000000006');
INSERT INTO public.profiles SELECT id, CASE WHEN id = '40000000-0000-4000-8000-000000000003' THEN 'premium' ELSE 'free' END
 FROM auth.users WHERE id::text LIKE '40000000%';
CREATE TABLE public.provider_cost_fixture(owner_id uuid PRIMARY KEY, session_id uuid);
INSERT INTO public.provider_cost_fixture SELECT id, (public.prepare_voice_relay(id)->>'session_id')::uuid
 FROM auth.users WHERE id::text LIKE '40000000%';
GRANT SELECT ON public.provider_cost_fixture TO service_role;

SET ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM public.claim_voice_relay('40000000-0000-4000-8000-000000000001', gen_random_uuid());
    RAISE EXCEPTION 'Anonymous claim accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.finalize_voice_relay(gen_random_uuid(), 0, false);
    RAISE EXCEPTION 'Anonymous finalization accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM daily_seconds FROM public.voice_provider_budget;
    RAISE EXCEPTION 'Anonymous budget read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', false);
DO $$ BEGIN
  BEGIN UPDATE public.voice_provider_budget SET daily_seconds = 100000;
    RAISE EXCEPTION 'Client budget change accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.voice_relay_reservations SET reserved_seconds = 0;
    RAISE EXCEPTION 'Client reservation reset accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.claim_voice_relay('40000000-0000-4000-8000-000000000001', gen_random_uuid());
    RAISE EXCEPTION 'Client claim accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.finalize_voice_relay(gen_random_uuid(), 0, false);
    RAISE EXCEPTION 'Client finalization accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.role', 'service_role', false);
SET ROLE service_role;
DO $$
DECLARE sid uuid := (SELECT session_id FROM public.provider_cost_fixture WHERE owner_id = '40000000-0000-4000-8000-000000000001');
BEGIN
  BEGIN PERFORM public.claim_voice_relay('40000000-0000-4000-8000-000000000001', sid);
    RAISE EXCEPTION 'Zero budget admitted a provider session';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  BEGIN UPDATE public.voice_provider_budget SET daily_seconds = -1;
    RAISE EXCEPTION 'Negative budget accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.voice_provider_budget SET daily_seconds = 150;
END $$;
RESET ROLE;
DO $$
DECLARE
  a uuid := '40000000-0000-4000-8000-000000000001'; b uuid := '40000000-0000-4000-8000-000000000002';
  c uuid := '40000000-0000-4000-8000-000000000003'; d uuid := '40000000-0000-4000-8000-000000000004';
  sa uuid := (SELECT session_id FROM public.provider_cost_fixture WHERE owner_id = a);
  sb uuid := (SELECT session_id FROM public.provider_cost_fixture WHERE owner_id = b);
  sc uuid := (SELECT session_id FROM public.provider_cost_fixture WHERE owner_id = c);
  sd uuid := (SELECT session_id FROM public.provider_cost_fixture WHERE owner_id = d);
  result jsonb; new_sid uuid; used bigint;
BEGIN
  IF (public.claim_voice_relay(a, sa)->>'reserved_seconds')::integer <> 120 THEN RAISE EXCEPTION 'Per-session cap changed'; END IF;
  IF (public.claim_voice_relay(b, sb)->>'reserved_seconds')::integer <> 30 THEN RAISE EXCEPTION 'Global remainder not enforced'; END IF;
  BEGIN PERFORM public.claim_voice_relay(c, sc); RAISE EXCEPTION 'Premium bypassed global budget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  -- Worker/provider outcome is unknown. Age does not release the full reservation.
  UPDATE public.voice_relay_reservations SET claimed_at = now() - interval '1 day' WHERE session_id = sb;
  BEGIN PERFORM public.claim_voice_relay(c, sc); RAISE EXCEPTION 'Unknown reservation expired';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  PERFORM public.finalize_voice_relay(sa, 30, false);
  PERFORM public.finalize_voice_relay(sa, 0, false);
  IF (SELECT duration_seconds FROM public.voice_relay_reservations WHERE session_id = sa) <> 30 THEN RAISE EXCEPTION 'Replay refunded usage'; END IF;
  result := public.claim_voice_relay(c, sc);
  IF (result->>'reserved_seconds')::integer <> 90 OR (result->>'is_premium')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'Premium lost entitlement or bypassed global remainder'; END IF;
  BEGIN PERFORM public.claim_voice_relay(d, sd); RAISE EXCEPTION 'Oversubscribed global budget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  PERFORM public.end_voice_session(sb, 0);
  IF (SELECT finalized_at IS NOT NULL FROM public.voice_relay_reservations WHERE session_id = sb) THEN RAISE EXCEPTION 'Client released global reservation'; END IF;
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  IF public.get_voice_minutes_remaining(a) <> 2.5 THEN RAISE EXCEPTION 'Free monthly accounting changed'; END IF;
  UPDATE public.voice_provider_budget SET daily_seconds = 300;
  new_sid := (public.prepare_voice_relay(a)->>'session_id')::uuid;
  IF (public.claim_voice_relay(a, new_sid)->>'reserved_seconds')::integer <> 120 THEN RAISE EXCEPTION 'Session limit changed'; END IF;
  PERFORM public.finalize_voice_relay(new_sid, 120, false);
  new_sid := (public.prepare_voice_relay(a)->>'session_id')::uuid;
  IF (public.claim_voice_relay(a, new_sid)->>'reserved_seconds')::integer <> 30 THEN RAISE EXCEPTION 'Three minute monthly remainder changed'; END IF;
  IF public.get_voice_minutes_remaining(a) <> 0 THEN RAISE EXCEPTION 'Monthly allowance overspent'; END IF;
  PERFORM public.finalize_voice_relay(new_sid, 30, true);
  -- Settlement changes usage on its recorded admission day, even across a date boundary.
  UPDATE public.voice_relay_reservations SET budget_day = budget_day - 1 WHERE session_id = sc;
  PERFORM public.finalize_voice_relay(sc, 10, false);
  IF (SELECT budget_day FROM public.voice_relay_reservations WHERE session_id = sc) <> (clock_timestamp() AT TIME ZONE 'UTC')::date - 1 THEN
    RAISE EXCEPTION 'Settlement moved the admission day'; END IF;
  SELECT sum(CASE WHEN finalized_at IS NULL THEN reserved_seconds ELSE duration_seconds END) INTO used
    FROM public.voice_relay_reservations WHERE budget_day = (clock_timestamp() AT TIME ZONE 'UTC')::date;
  IF used <> 210 THEN RAISE EXCEPTION 'Incorrect current-day known plus unknown accounting: %', used; END IF;
  UPDATE public.voice_provider_budget SET daily_seconds = used + 150;
  RAISE NOTICE 'PASS: zero default, actual negative roles, preserved history, premium/global limits, unknown retention, idempotence, free three minutes/month, admission day';
END $$;

-- Real two-connection race: unrelated owners compete for the same 150 seconds.
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT dblink_connect('global_budget', 'dbname=' || current_database() || ' application_name=provider_cost_global_race');
BEGIN;
SET LOCAL ROLE service_role;
SELECT public.claim_voice_relay(owner_id, session_id) FROM public.provider_cost_fixture
  WHERE owner_id = '40000000-0000-4000-8000-000000000004';
RESET ROLE;
SELECT dblink_send_query('global_budget', $query$
DO $remote$ BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', false);
  PERFORM public.claim_voice_relay(owner_id, session_id) FROM public.provider_cost_fixture
    WHERE owner_id = '40000000-0000-4000-8000-000000000005';
END $remote$;
$query$);
DO $$ DECLARE blocked boolean := false; BEGIN
  FOR attempt IN 1..100 LOOP
    PERFORM pg_stat_clear_snapshot();
    SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name = 'provider_cost_global_race' AND wait_event_type = 'Lock') INTO blocked;
    EXIT WHEN blocked;
    PERFORM pg_sleep(0.01);
  END LOOP;
  IF NOT blocked THEN RAISE EXCEPTION 'Second owner did not wait for atomic global admission'; END IF;
END $$;
COMMIT;
SELECT * FROM dblink_get_result('global_budget') AS result(status text);
SELECT dblink_disconnect('global_budget');
DO $$ DECLARE total bigint; BEGIN
  IF (SELECT reserved_seconds FROM public.voice_relay_reservations WHERE user_id = '40000000-0000-4000-8000-000000000005') <> 30 THEN
    RAISE EXCEPTION 'Concurrent second owner exceeded the global remainder'; END IF;
  SELECT sum(CASE WHEN finalized_at IS NULL THEN reserved_seconds ELSE duration_seconds END) INTO total
    FROM public.voice_relay_reservations WHERE budget_day = (clock_timestamp() AT TIME ZONE 'UTC')::date;
  IF total <> (SELECT daily_seconds FROM public.voice_provider_budget) THEN RAISE EXCEPTION 'Concurrent claims exceeded global budget'; END IF;
  RAISE NOTICE 'PASS: real two-connection cross-owner global-budget race';
END $$;

\ir ../rollback/20261023_provider_cost_limits.sql
DO $$ BEGIN
  BEGIN
    PERFORM public.claim_voice_relay(owner_id, session_id) FROM public.provider_cost_fixture
      WHERE owner_id = '40000000-0000-4000-8000-000000000006';
    RAISE EXCEPTION 'Rollback/pause admitted a new provider connection';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  PERFORM public.finalize_voice_relay(session_id, 0, false) FROM public.provider_cost_fixture
    WHERE owner_id = '40000000-0000-4000-8000-000000000004';
  IF NOT EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE user_id = '40000000-0000-4000-8000-000000000002' AND finalized_at IS NULL AND reserved_seconds = 30) THEN
    RAISE EXCEPTION 'Rollback lost an unknown reservation'; END IF;
  RAISE NOTICE 'PASS: safe rollback blocks new admission, permits trusted settlement, retains unknown usage and history';
END $$;
