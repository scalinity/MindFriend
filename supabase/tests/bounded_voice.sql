-- EMPTY LOCAL DISPOSABLE DATABASE ONLY. No provider, network, microphone or real data.
-- docker exec supabase_db_mindfriend-restoration-local createdb -U postgres bounded_voice_synthetic
-- docker exec -i supabase_db_mindfriend-restoration-local psql -X -U supabase_admin -v ON_ERROR_STOP=1 -d bounded_voice_synthetic -f /tmp/voice-bounded-repo/supabase/tests/bounded_voice.sql
-- Copy this repository's selected SQL fixture/migrations into /tmp/voice-bounded-repo first.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database() <> 'bounded_voice_synthetic' OR to_regclass('auth.users') IS NOT NULL THEN
    RAISE EXCEPTION 'Requires empty disposable bounded_voice_synthetic database';
  END IF;
END $$;
\ir ../functions/tests/voice_relay_fixture.sql
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role' AND rolbypassrls) THEN
    RAISE EXCEPTION 'Fixture requires the existing Supabase service_role BYPASSRLS role';
  END IF;
END $$;
-- Minimal synthetic prerequisites used by the actual sponsored-entitlement migration.
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{}'::jsonb $$;
ALTER TABLE public.subscriptions ADD COLUMN id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN plan_type text, ADD COLUMN access_source text, ADD COLUMN organization_id uuid,
  ADD COLUMN product_id text, ADD COLUMN original_transaction_id text,
  ADD COLUMN organization_sponsor_created_at timestamptz, ADD COLUMN updated_at timestamptz,
  ADD UNIQUE(user_id);
CREATE TABLE public.organizations(id uuid PRIMARY KEY, status text, subscription_status text);
CREATE TABLE public.organization_members(id uuid PRIMARY KEY, user_id uuid, organization_id uuid, is_active boolean, joined_at timestamptz);
CREATE TABLE public.creative_quota_usage(user_id uuid, date date, ai_art_count integer, voice_minutes_used integer, UNIQUE(user_id,date));
\ir ../migrations/20261023083458_reserve_voice_journal_quota.sql
\ir ../migrations/20261023083506_refresh_sponsored_entitlement.sql
\ir ../migrations/20261023092051_provider_cost_limits.sql
\ir ../migrations/20261023072340_bound_monthly_ai_budget.sql
\ir ../migrations/20261023092207_admit_bounded_voice.sql
-- The 06000 default remains closed; only this disposable fixture changes it.
UPDATE public.voice_relay_reservations SET budget_day=budget_day-1 WHERE claimed_at IS NOT NULL;
INSERT INTO auth.users SELECT ('60000000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid FROM generate_series(1,4) n;
INSERT INTO public.profiles SELECT id,'free' FROM auth.users WHERE id::text LIKE '60000000%';
CREATE TABLE public.bounded_voice_fixture(owner_id uuid PRIMARY KEY,session_id uuid);
INSERT INTO public.bounded_voice_fixture SELECT id,(public.prepare_voice_relay(id)->>'session_id')::uuid FROM auth.users WHERE id::text LIKE '60000000%';
GRANT SELECT ON public.bounded_voice_fixture, public.voice_sessions TO service_role;
SET ROLE anon;
DO $$ BEGIN
  BEGIN PERFORM public.claim_voice_relay(gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'anon claim'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.finalize_voice_relay(gen_random_uuid(),0,false); RAISE EXCEPTION 'anon finalize'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM public.claim_voice_relay(gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'client claim'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.finalize_voice_relay(gen_random_uuid(),0,false); RAISE EXCEPTION 'client finalize'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE service_role;
SET TIME ZONE 'Pacific/Kiritimati';
DO $$
DECLARE
  a uuid := '60000000-0000-4000-8000-000000000001'; b uuid := '60000000-0000-4000-8000-000000000002';
  sa uuid := (SELECT session_id FROM public.bounded_voice_fixture WHERE owner_id=a);
  sb uuid := (SELECT session_id FROM public.bounded_voice_fixture WHERE owner_id=b);
  month date := date_trunc('month',timezone('America/New_York',clock_timestamp()))::date;
  result jsonb; receipt jsonb;
BEGIN
  BEGIN UPDATE public.monthly_ai_budget_months SET reserved_microdollars=0; RAISE EXCEPTION 'service direct counter mutation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.monthly_ai_budget_receipts; RAISE EXCEPTION 'service erase receipt'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.claim_voice_relay(a,sa); RAISE EXCEPTION 'zero daily budget admitted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  UPDATE public.voice_provider_budget SET daily_seconds=120;
  INSERT INTO public.monthly_ai_budget_months(month_start,limit_microdollars) VALUES(month,239999);
  BEGIN PERFORM public.claim_voice_relay(a,sa); RAISE EXCEPTION 'monthly denial admitted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'MONTHLY_AI_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  IF EXISTS(SELECT 1 FROM public.monthly_ai_budget_receipts) OR (SELECT claimed_at IS NOT NULL FROM public.voice_relay_reservations WHERE session_id=sa) THEN RAISE EXCEPTION 'denial not atomic'; END IF;
  UPDATE public.monthly_ai_budget_months SET limit_microdollars=10000000 WHERE month_start=month;
  BEGIN PERFORM public.claim_voice_relay(b,sa); RAISE EXCEPTION 'cross-owner claim';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'INVALID_SESSION' THEN RAISE; END IF; END;
  result := public.claim_voice_relay(a,sa);
  IF result->>'reserved_seconds' <> '120' OR result->>'monthly_reserve_microdollars' <> '240000' OR (result->>'monthly_budget_month')::date <> month THEN RAISE EXCEPTION 'bad fixed reservation contract: %',result; END IF;
  SELECT to_jsonb(r) INTO receipt FROM public.monthly_ai_budget_receipts r WHERE request_id=sa;
  IF receipt->>'feature' <> 'voice.live' OR receipt->>'user_id' <> a::text OR receipt->>'reserve_microdollars' <> '240000' THEN RAISE EXCEPTION 'wrong owner/feature/amount'; END IF;
  BEGIN PERFORM public.claim_voice_relay(b,sb); RAISE EXCEPTION 'parallel provider accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'RELAY_ALREADY_ACTIVE' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claim.role','authenticated',false);
  PERFORM set_config('request.jwt.claim.sub',a::text,false);
  PERFORM public.end_voice_session(sa,0);
  IF (SELECT ended_at IS NOT NULL FROM public.voice_sessions WHERE id=sa) THEN RAISE EXCEPTION 'client ended active relay'; END IF;
  PERFORM set_config('request.jwt.claim.role','service_role',false);
  PERFORM public.finalize_voice_relay(sa,120,true);
  PERFORM public.finalize_voice_relay(sa,0,false);
  IF public.get_voice_minutes_remaining(a) <> 1 OR (SELECT reserved_microdollars FROM public.monthly_ai_budget_months WHERE month_start=month) <> 240000
    OR receipt IS DISTINCT FROM (SELECT to_jsonb(r) FROM public.monthly_ai_budget_receipts r WHERE request_id=sa) THEN RAISE EXCEPTION 'finalization refunded or rewrote receipt/user quota'; END IF;
  BEGIN PERFORM public.claim_voice_relay(a,sa); RAISE EXCEPTION 'replay accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'INVALID_SESSION' THEN RAISE; END IF; END;
  BEGIN PERFORM public.claim_voice_relay(b,sb); RAISE EXCEPTION 'spent120 daily budget reused';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  UPDATE public.voice_provider_budget SET daily_seconds=240;
  PERFORM public.claim_voice_relay(b,sb);
  IF (SELECT reserved_microdollars FROM public.monthly_ai_budget_months WHERE month_start=month) <> 480000 THEN RAISE EXCEPTION 'second fixed reservation incorrect'; END IF;
  RAISE NOTICE 'PASS: exact roles/owner, default0 and controlled120sec day, fixed240000 Eastern receipt, atomic denial, one active, client-end protection, idempotent user quota, no refund';
END $$;
RESET ROLE;
-- Age an unknown active provider across a month boundary; no expiry releases it.
UPDATE public.voice_relay_reservations SET claimed_at=now()-interval '2 months',budget_day='2000-01-01'
  WHERE user_id='60000000-0000-4000-8000-000000000002';
UPDATE public.voice_provider_budget SET daily_seconds=100000;
DO $$ BEGIN
  BEGIN PERFORM public.claim_voice_relay(owner_id,session_id) FROM public.bounded_voice_fixture WHERE right(owner_id::text,1)='3'; RAISE EXCEPTION 'old unknown provider expired';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'RELAY_ALREADY_ACTIVE' THEN RAISE; END IF; END;
  IF (SELECT sum(reserved_microdollars) FROM public.monthly_ai_budget_months) <> 480000 THEN RAISE EXCEPTION 'unknown reservation refunded'; END IF;
  IF to_regprocedure('public.finalize_voice_relay(uuid,integer,boolean,integer,boolean)') IS NOT NULL OR to_regclass('public.voice_relay_monthly_settlements') IS NOT NULL THEN RAISE EXCEPTION 'abandoned settlement machinery present'; END IF;
  -- Fixture-only trusted closure lets the independent race scenario proceed.
  PERFORM public.finalize_voice_relay(session_id,0,false) FROM public.bounded_voice_fixture WHERE right(owner_id::text,1)='2';
  RAISE NOTICE 'PASS: aged unknown remains active across months, no timeout refund, no five-argument settlement machinery';
END $$;
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT dblink_connect('bounded_voice','dbname=' || current_database() || ' user=supabase_admin application_name=bounded_voice_race');
BEGIN;
SELECT public.claim_voice_relay(owner_id,session_id) FROM public.bounded_voice_fixture WHERE right(owner_id::text,1)='3';
SELECT dblink_send_query('bounded_voice',$q$
DO $remote$ BEGIN
  PERFORM set_config('request.jwt.claim.role','service_role',false);
  BEGIN PERFORM public.claim_voice_relay(owner_id,session_id) FROM public.bounded_voice_fixture WHERE right(owner_id::text,1)='4'; RAISE EXCEPTION 'concurrent provider accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'RELAY_ALREADY_ACTIVE' THEN RAISE; END IF; END;
END $remote$;
$q$);
DO $$ DECLARE blocked boolean; BEGIN
  FOR n IN 1..100 LOOP
    PERFORM pg_stat_clear_snapshot();
    SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='bounded_voice_race' AND wait_event_type='Lock') INTO blocked;
    EXIT WHEN blocked; PERFORM pg_sleep(0.01);
  END LOOP;
  IF NOT blocked THEN RAISE EXCEPTION 'concurrent admission failed to serialize'; END IF;
END $$;
COMMIT;
SELECT * FROM dblink_get_result('bounded_voice') AS result(status text);
SELECT dblink_disconnect('bounded_voice');
\ir ../rollback/20261023092500_admit_bounded_voice.sql
DO $$ BEGIN
  IF (SELECT sum(reserved_microdollars) FROM public.monthly_ai_budget_months) <> 720000 OR (SELECT count(*) FROM public.monthly_ai_budget_receipts) <> 3 THEN RAISE EXCEPTION 'race or pause changed retained receipts'; END IF;
  PERFORM public.finalize_voice_relay(session_id,0,false) FROM public.bounded_voice_fixture WHERE right(owner_id::text,1)='3';
  BEGIN PERFORM public.claim_voice_relay(owner_id,session_id) FROM public.bounded_voice_fixture WHERE right(owner_id::text,1)='4'; RAISE EXCEPTION 'pause admitted provider';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'VOICE_BUDGET_EXCEEDED' THEN RAISE; END IF; END;
  RAISE NOTICE 'PASS: real concurrent global exclusion, pause preserves all receipts and permits trusted in-flight accounting';
END $$;
