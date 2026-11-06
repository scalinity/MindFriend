-- Requires 20261023003000, 20261023005000, 20261023006000 and the deployed
-- 20261023052846 shared ledger. Apply 06000 first; daily_seconds defaults to 0.
-- Do not apply the separate abandoned 20261023074714 hold/settlement proposal.
BEGIN;
DO $$ BEGIN
  IF pg_catalog.to_regclass('public.voice_provider_budget') IS NULL
    OR pg_catalog.to_regprocedure('public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)') IS NULL THEN
    RAISE EXCEPTION 'Apply provider_cost_limits and bound_monthly_ai_budget first';
  END IF;
  IF pg_catalog.to_regclass('public.voice_relay_monthly_settlements') IS NOT NULL THEN
    RAISE EXCEPTION 'The abandoned voice monthly hold migration must not be applied';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.claim_voice_relay(p_user_id uuid, p_session_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_session public.voice_sessions%ROWTYPE;
  v_ledger public.voice_relay_reservations%ROWTYPE;
  v_remaining double precision;
  v_seconds integer;
  v_day date;
  v_limit integer;
  v_used bigint;
  v_budget jsonb;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL OR p_session_id IS NULL THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 76543));
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
  PERFORM pg_catalog.pg_advisory_xact_lock(76544, 1);
  -- The daily voice lock also serializes the one-active-provider rule across
  -- all owners/months. Unknown closure remains unfinalized and blocks another.
  IF EXISTS(SELECT 1 FROM public.voice_relay_reservations AS r
      WHERE r.claimed_at IS NOT NULL AND r.finalized_at IS NULL) THEN
    RAISE EXCEPTION 'RELAY_ALREADY_ACTIVE';
  END IF;
  v_day := (pg_catalog.clock_timestamp() AT TIME ZONE 'UTC')::date;
  SELECT daily_seconds INTO v_limit FROM public.voice_provider_budget WHERE singleton;
  SELECT coalesce(sum(coalesce(CASE WHEN finalized_at IS NOT NULL THEN duration_seconds END, reserved_seconds)), 0)
    INTO v_used FROM public.voice_relay_reservations WHERE budget_day = v_day AND claimed_at IS NOT NULL;
  v_seconds := least(v_seconds::bigint, greatest(0::bigint, coalesce(v_limit, 0)::bigint - v_used))::integer;
  IF v_seconds <= 0 THEN RAISE EXCEPTION 'VOICE_BUDGET_EXCEEDED'; END IF;

  v_budget := public.reserve_monthly_ai_budget(p_session_id, p_user_id, 'voice.live', 240000::bigint);
  IF v_budget->>'allowed' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'MONTHLY_AI_BUDGET_EXCEEDED';
  END IF;
  UPDATE public.voice_relay_reservations AS r SET claimed_at = pg_catalog.clock_timestamp(), reserved_seconds = v_seconds,
    period_start = pg_catalog.date_trunc('month', now())::date, budget_day = v_day WHERE r.session_id = p_session_id;
  RETURN pg_catalog.jsonb_build_object('reserved_seconds', v_seconds, 'is_premium', v_remaining = 999999.0,
    'monthly_reserve_microdollars', 240000, 'monthly_budget_month', v_budget->>'month_start');
END;
$$;

REVOKE ALL ON FUNCTION public.claim_voice_relay(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_voice_relay(uuid, uuid) TO service_role;
COMMENT ON FUNCTION public.claim_voice_relay(uuid, uuid) IS
'Atomically admit one active two-minute relay globally against existing user/daily limits and a fixed $0.24 shared monthly reservation (three $0.08 minutes for setup/close). The receipt is retained without refund after every outcome. This is not a provider-enforced absolute invoice cap; an unknown remote disconnect can outlive local relay teardown.';
COMMIT;
