-- LOCAL DISPOSABLE DATABASE ONLY. Builds the focused prerequisite schema.
-- Run with psql -v ON_ERROR_STOP=1 -f supabase/functions/tests/voice_relay_fixture.sql.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS auth;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END $$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT current_setting('request.jwt.claim.role', true) $$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.profiles(id uuid PRIMARY KEY, subscription_tier text);
CREATE TABLE public.subscriptions(user_id uuid, status text, expires_at timestamptz);
CREATE TABLE public.voice_sessions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL,
 started_at timestamptz DEFAULT now(), ended_at timestamptz, voice_used text, duration_seconds integer DEFAULT 0,
 messages_count integer DEFAULT 0, was_quota_limited boolean DEFAULT false);
CREATE TABLE public.voice_usage(user_id uuid, period_start date, minutes_used double precision,
 last_session_at timestamptz, updated_at timestamptz, UNIQUE(user_id, period_start));
CREATE FUNCTION public.increment_voice_usage(p_user_id uuid, p_minutes double precision, p_period_start date)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
 INSERT INTO public.voice_usage(user_id, period_start, minutes_used) VALUES(p_user_id, p_period_start, p_minutes)
 ON CONFLICT(user_id, period_start) DO UPDATE SET minutes_used = voice_usage.minutes_used + excluded.minutes_used;
$$;
\ir ../../migrations/20261023082449_secure_voice_accounting.sql
\ir ../../migrations/20261023083500_voice_relay.sql
INSERT INTO auth.users VALUES ('10000000-0000-4000-8000-000000000001'), ('20000000-0000-4000-8000-000000000002');
INSERT INTO public.profiles SELECT id, 'free' FROM auth.users;
SELECT set_config('request.jwt.claim.role', 'service_role', false);
DO $$
DECLARE owner_id uuid := '10000000-0000-4000-8000-000000000001'; other_id uuid := '20000000-0000-4000-8000-000000000002';
 sid uuid; second_sid uuid; before_minutes double precision; result jsonb;
BEGIN
 IF has_table_privilege('authenticated', 'public.voice_relay_reservations', 'SELECT')
    OR has_function_privilege('authenticated', 'public.claim_voice_relay(uuid,uuid)', 'EXECUTE')
    OR has_function_privilege('anon', 'public.finalize_voice_relay(uuid,integer,boolean)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.increment_voice_usage(uuid,double precision,date)', 'EXECUTE') THEN RAISE EXCEPTION 'Service-only privilege leak'; END IF;
 sid := (public.prepare_voice_relay(owner_id)->>'session_id')::uuid;
 BEGIN
   PERFORM public.claim_voice_relay(other_id, sid); RAISE EXCEPTION 'Cross-user claim accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'INVALID_SESSION' THEN RAISE; END IF; END;
 result := public.claim_voice_relay(owner_id, sid);
 IF (result->>'reserved_seconds')::integer <> 120 THEN RAISE EXCEPTION 'Wrong reservation'; END IF;
 IF public.get_voice_minutes_remaining(owner_id) <> 1 THEN RAISE EXCEPTION 'Reservation not deducted'; END IF;
 BEGIN
   PERFORM public.claim_voice_relay(owner_id, sid); RAISE EXCEPTION 'Replay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'INVALID_SESSION' THEN RAISE; END IF; END;
 second_sid := (public.prepare_voice_relay(owner_id)->>'session_id')::uuid;
 BEGIN
   PERFORM public.claim_voice_relay(owner_id, second_sid); RAISE EXCEPTION 'Second active relay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'RELAY_ALREADY_ACTIVE' THEN RAISE; END IF; END;
 -- Claim wins the client-end interleaving: reported zero cannot close or undercount a live relay.
 PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
 PERFORM set_config('request.jwt.claim.sub', other_id::text, true);
 BEGIN
   PERFORM public.end_voice_session(sid, 0); RAISE EXCEPTION 'Cross-user end accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub', owner_id::text, true);
 PERFORM public.end_voice_session(sid, 0);
 IF (SELECT ended_at IS NOT NULL FROM public.voice_sessions WHERE id = sid) THEN RAISE EXCEPTION 'Client ended active relay'; END IF;
 PERFORM set_config('request.jwt.claim.role', 'service_role', true);
 PERFORM public.finalize_voice_relay(sid, 30, false);
 before_minutes := public.get_voice_minutes_remaining(owner_id);
 PERFORM public.finalize_voice_relay(sid, 120, true);
 IF public.get_voice_minutes_remaining(owner_id) <> before_minutes OR before_minutes <> 2.5 THEN RAISE EXCEPTION 'Finalization not idempotent'; END IF;
 IF (SELECT duration_seconds FROM public.voice_sessions WHERE id = sid) <> 30 THEN RAISE EXCEPTION 'Trusted duration changed'; END IF;
 -- Client end wins the other interleaving: ended preparation cannot claim.
 PERFORM public.end_voice_session(second_sid, 0);
 BEGIN
   PERFORM public.claim_voice_relay(owner_id, second_sid); RAISE EXCEPTION 'Ended preparation claimed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'INVALID_SESSION' THEN RAISE; END IF; END;
 -- Fractional monthly remainder is floored to whole seconds before issuance.
 UPDATE public.voice_usage SET minutes_used = 2.75 WHERE user_id = owner_id;
 sid := (public.prepare_voice_relay(owner_id)->>'session_id')::uuid;
 IF (public.claim_voice_relay(owner_id, sid)->>'reserved_seconds')::integer <> 15 THEN RAISE EXCEPTION 'Fractional allowance exceeded'; END IF;
 -- Reservation period, not close month, owns accounting.
 UPDATE public.voice_relay_reservations SET period_start = (date_trunc('month', now()) - interval '1 month')::date WHERE session_id = sid;
 PERFORM public.finalize_voice_relay(sid, 10, false);
 IF NOT EXISTS(SELECT 1 FROM public.voice_usage WHERE user_id = owner_id AND period_start = (date_trunc('month', now()) - interval '1 month')::date AND abs(minutes_used - 10.0/60.0) < 0.00001) THEN RAISE EXCEPTION 'Wrong accounting month'; END IF;
 UPDATE public.profiles SET subscription_tier = 'premium' WHERE id = other_id;
 IF public.get_voice_minutes_remaining(other_id) <> 999999 THEN RAISE EXCEPTION 'Protected profile entitlement lost'; END IF;
 RAISE NOTICE 'PASS: owner/cross-user, service-only grants, replay, quota reservation, active-owner limit, both end interleavings, idempotence, month boundary, premium';
END $$;
-- Leave schema for the optional two-connection lock test below; use only a disposable DB.
