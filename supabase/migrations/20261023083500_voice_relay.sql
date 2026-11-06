-- Phase 2, release-gated. No deployment authorization is implied by this migration.
-- Reservations survive unknown worker failures; no background expiry can free live usage.
CREATE TABLE public.voice_relay_reservations (
  session_id uuid PRIMARY KEY REFERENCES public.voice_sessions(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  period_start date NOT NULL,
  prepared_at timestamptz NOT NULL DEFAULT now(),
  claimed_at timestamptz,
  reserved_seconds integer NOT NULL DEFAULT 0 CHECK (reserved_seconds BETWEEN 0 AND 120),
  finalized_at timestamptz,
  duration_seconds integer CHECK (duration_seconds BETWEEN 0 AND 120)
);
CREATE UNIQUE INDEX voice_relay_one_active_owner ON public.voice_relay_reservations(user_id)
  WHERE claimed_at IS NOT NULL AND finalized_at IS NULL;
ALTER TABLE public.voice_relay_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.voice_relay_reservations FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.voice_relay_reservations TO service_role;

CREATE OR REPLACE FUNCTION public.get_voice_minutes_remaining(p_user_id uuid)
RETURNS double precision LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_used double precision; v_reserved integer;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' AND (auth.uid() IS NULL OR auth.uid() <> p_user_id) THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id = p_user_id AND subscription_tier = 'premium')
     OR EXISTS(SELECT 1 FROM public.subscriptions WHERE user_id = p_user_id AND status = 'active' AND expires_at > now()) THEN
    RETURN 999999.0;
  END IF;
  SELECT minutes_used INTO v_used FROM public.voice_usage
    WHERE user_id = p_user_id AND period_start = date_trunc('month', now())::date;
  SELECT coalesce(sum(reserved_seconds), 0) INTO v_reserved FROM public.voice_relay_reservations
    WHERE user_id = p_user_id AND period_start = date_trunc('month', now())::date
      AND claimed_at IS NOT NULL AND finalized_at IS NULL;
  RETURN greatest(0, 3.0 - coalesce(v_used, 0) - v_reserved / 60.0);
END;
$$;

CREATE FUNCTION public.prepare_voice_relay(p_user_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid; v_remaining double precision; v_premium boolean;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 76543));
  -- Preserve the existing three starts/minute limit without adding another function deployment.
  IF (SELECT count(*) FROM public.voice_relay_reservations WHERE user_id = p_user_id AND prepared_at > now() - interval '1 minute') >= 3 THEN
    RAISE EXCEPTION 'RATE_LIMITED';
  END IF;
  v_remaining := public.get_voice_minutes_remaining(p_user_id);
  IF v_remaining <= 0 THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  v_premium := v_remaining = 999999.0;
  INSERT INTO public.voice_sessions(user_id, voice_used) VALUES (p_user_id, 'ara') RETURNING id INTO v_id;
  INSERT INTO public.voice_relay_reservations(session_id, user_id, period_start)
    VALUES (v_id, p_user_id, date_trunc('month', now())::date);
  RETURN jsonb_build_object('session_id', v_id, 'expires_at', now() + interval '2 minutes',
    'minutes_remaining', v_remaining, 'voice', 'ara', 'is_premium', v_premium,
    'available_voices', CASE WHEN v_premium THEN '["ara","rex","sal","eve","leo"]'::jsonb ELSE '["ara"]'::jsonb END);
END;
$$;

CREATE FUNCTION public.claim_voice_relay(p_user_id uuid, p_session_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_session public.voice_sessions%ROWTYPE; v_ledger public.voice_relay_reservations%ROWTYPE;
  v_remaining double precision; v_seconds integer;
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
  UPDATE public.voice_relay_reservations SET claimed_at = now(), reserved_seconds = v_seconds,
    period_start = date_trunc('month', now())::date WHERE session_id = p_session_id;
  RETURN jsonb_build_object('reserved_seconds', v_seconds, 'is_premium', v_remaining = 999999.0);
END;
$$;

CREATE FUNCTION public.finalize_voice_relay(p_session_id uuid, p_duration_seconds integer, p_was_quota_limited boolean DEFAULT false)
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
  UPDATE public.voice_sessions SET ended_at = now(), duration_seconds = p_duration_seconds,
    was_quota_limited = p_was_quota_limited WHERE id = p_session_id;
  PERFORM public.increment_voice_usage(v_owner, p_duration_seconds / 60.0, v_ledger.period_start);
  UPDATE public.voice_relay_reservations SET finalized_at = now(), duration_seconds = p_duration_seconds WHERE session_id = p_session_id;
  RETURN jsonb_build_object('duration_seconds', p_duration_seconds, 'status', 'finalized');
END;
$$;

-- Check membership AFTER the voice_sessions row lock: a client-end race cannot bypass the ledger.
CREATE OR REPLACE FUNCTION public.end_voice_session(
  p_session_id uuid, p_duration_seconds integer,
  p_messages_count integer DEFAULT 0, p_was_quota_limited boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user_id uuid; v_ended_at timestamptz;
BEGIN
  IF p_duration_seconds IS NULL OR p_duration_seconds < 0 OR p_duration_seconds > 86400
     OR p_messages_count IS NULL OR p_messages_count < 0 OR p_messages_count > 100000 OR p_was_quota_limited IS NULL THEN
    RAISE EXCEPTION 'Invalid session usage' USING ERRCODE = '22023';
  END IF;
  SELECT user_id, ended_at INTO v_user_id, v_ended_at FROM public.voice_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF coalesce(auth.role(), '') <> 'service_role' AND (auth.uid() IS NULL OR auth.uid() <> v_user_id) THEN
    RAISE EXCEPTION 'Session not found' USING ERRCODE = '42501';
  END IF;
  IF EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE session_id = p_session_id) THEN
    -- An unclaimed preparation may end, but can then never connect. Claimed usage is server-only.
    UPDATE public.voice_sessions SET ended_at = now() WHERE id = p_session_id AND ended_at IS NULL
      AND EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE session_id = p_session_id AND claimed_at IS NULL);
    RETURN;
  END IF;
  IF v_ended_at IS NOT NULL THEN RETURN; END IF;
  UPDATE public.voice_sessions SET ended_at = now(), duration_seconds = p_duration_seconds,
    messages_count = p_messages_count, was_quota_limited = p_was_quota_limited WHERE id = p_session_id;
  PERFORM public.increment_voice_usage(v_user_id, p_duration_seconds / 60.0, date_trunc('month', now())::date);
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_voice_relay(uuid), public.claim_voice_relay(uuid, uuid), public.finalize_voice_relay(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_voice_relay(uuid), public.claim_voice_relay(uuid, uuid), public.finalize_voice_relay(uuid, integer, boolean) TO service_role;
-- Prevent direct negative increments from minting allowance outside the reservation lock.
REVOKE ALL ON FUNCTION public.increment_voice_usage(uuid, double precision, date) FROM PUBLIC, anon, authenticated;
