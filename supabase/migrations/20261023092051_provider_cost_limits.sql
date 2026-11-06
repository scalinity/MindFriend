BEGIN;

-- UTC admission-day session seconds across every relay user, including premium.
-- This bounds admitted session time, not all input/output tokens or dollar spend.
-- Zero disables new provider connections until an approved limit is configured.
CREATE TABLE public.voice_provider_budget (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  daily_seconds integer NOT NULL DEFAULT 0 CHECK (daily_seconds >= 0)
);
INSERT INTO public.voice_provider_budget(singleton, daily_seconds) VALUES (true, 0);
ALTER TABLE public.voice_provider_budget ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.voice_provider_budget FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE ON public.voice_provider_budget TO service_role;
COMMENT ON TABLE public.voice_provider_budget IS
'Service-only global live-voice UTC admission-day session-seconds limit. Zero blocks admission. Not an all-token dollar cap. Existing reservations remain charged until trusted finalization; no timeout refunds.';

ALTER TABLE public.voice_relay_reservations ADD COLUMN budget_day date;
-- Preserve existing sessions and count any already admitted on the current day.
UPDATE public.voice_relay_reservations
SET budget_day = (claimed_at AT TIME ZONE 'UTC')::date
WHERE claimed_at IS NOT NULL;
CREATE INDEX voice_relay_budget_day ON public.voice_relay_reservations(budget_day)
WHERE claimed_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.claim_voice_relay(p_user_id uuid, p_session_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_session public.voice_sessions%ROWTYPE;
  v_ledger public.voice_relay_reservations%ROWTYPE;
  v_remaining double precision;
  v_seconds integer;
  v_day date;
  v_limit integer;
  v_used bigint;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 76543));
  SELECT * INTO v_session FROM public.voice_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_session.user_id <> p_user_id OR v_session.ended_at IS NOT NULL THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  SELECT * INTO v_ledger FROM public.voice_relay_reservations WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_ledger.user_id <> p_user_id OR v_ledger.claimed_at IS NOT NULL OR v_ledger.finalized_at IS NOT NULL
     OR v_ledger.prepared_at < now() - interval '2 minutes' THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  IF EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE user_id = p_user_id AND claimed_at IS NOT NULL AND finalized_at IS NULL) THEN
    RAISE EXCEPTION 'RELAY_ALREADY_ACTIVE';
  END IF;
  v_remaining := public.get_voice_minutes_remaining(p_user_id);
  v_seconds := least(120, floor(v_remaining * 60)::integer);
  IF v_seconds <= 0 THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;

  -- Same lock in finalization; no two users can spend the same remaining seconds.
  -- The global lock is always acquired after the existing owner/session locks.
  PERFORM pg_advisory_xact_lock(76544, 1);
  v_day := (clock_timestamp() AT TIME ZONE 'UTC')::date;
  SELECT daily_seconds INTO v_limit FROM public.voice_provider_budget WHERE singleton;
  SELECT coalesce(sum(coalesce(CASE WHEN finalized_at IS NOT NULL THEN duration_seconds END, reserved_seconds)), 0)
    INTO v_used FROM public.voice_relay_reservations WHERE budget_day = v_day AND claimed_at IS NOT NULL;
  v_seconds := least(v_seconds::bigint, greatest(0::bigint, coalesce(v_limit, 0)::bigint - v_used))::integer;
  IF v_seconds <= 0 THEN RAISE EXCEPTION 'VOICE_BUDGET_EXCEEDED'; END IF;

  UPDATE public.voice_relay_reservations SET claimed_at = clock_timestamp(), reserved_seconds = v_seconds,
    period_start = date_trunc('month', now())::date, budget_day = v_day WHERE session_id = p_session_id;
  RETURN jsonb_build_object('reserved_seconds', v_seconds, 'is_premium', v_remaining = 999999.0);
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_voice_relay(p_session_id uuid, p_duration_seconds integer, p_was_quota_limited boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_owner uuid; v_ledger public.voice_relay_reservations%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  SELECT user_id INTO v_owner FROM public.voice_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_owner::text, 76543));
  PERFORM 1 FROM public.voice_sessions WHERE id = p_session_id FOR UPDATE;
  SELECT * INTO v_ledger FROM public.voice_relay_reservations WHERE session_id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v_ledger.claimed_at IS NULL THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  IF v_ledger.finalized_at IS NOT NULL THEN RETURN jsonb_build_object('duration_seconds', v_ledger.duration_seconds, 'status', 'finalized'); END IF;
  IF p_duration_seconds IS NULL OR p_duration_seconds < 0 OR p_duration_seconds > v_ledger.reserved_seconds OR p_was_quota_limited IS NULL THEN
    RAISE EXCEPTION 'Invalid session usage' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(76544, 1);
  UPDATE public.voice_sessions SET ended_at = now(), duration_seconds = p_duration_seconds,
    was_quota_limited = p_was_quota_limited WHERE id = p_session_id;
  PERFORM public.increment_voice_usage(v_owner, p_duration_seconds / 60.0, v_ledger.period_start);
  UPDATE public.voice_relay_reservations SET finalized_at = now(), duration_seconds = p_duration_seconds WHERE session_id = p_session_id;
  RETURN jsonb_build_object('duration_seconds', p_duration_seconds, 'status', 'finalized');
END;
$$;

REVOKE ALL ON FUNCTION public.claim_voice_relay(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finalize_voice_relay(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_voice_relay(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_voice_relay(uuid, integer, boolean) TO service_role;
COMMENT ON FUNCTION public.claim_voice_relay(uuid, uuid) IS
'Atomically admit against monthly user limits and the global daily audio-seconds limit before provider calls. Unknown outcomes keep the entire reservation. Premium does not bypass the global limit.';
COMMENT ON FUNCTION public.reserve_voice_journal_quota(uuid, integer) IS
'Service-only daily journal minutes reserved before transcription. The handler derives minutes from validated PCM sample bytes and sends canonical WAV; client/container duration and post-billing provider duration do not establish the bound.';

COMMIT;
