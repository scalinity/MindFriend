-- Stop relay admission before rolling Edge code back. Existing ledger records are retained.
REVOKE EXECUTE ON FUNCTION public.prepare_voice_relay(uuid), public.claim_voice_relay(uuid, uuid) FROM service_role;

-- Drain known live relays before restoring client-reported legacy accounting.
-- Unknown outcomes retain reservations and must be resolved before this rollback proceeds.
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE claimed_at IS NOT NULL AND finalized_at IS NULL) THEN
    RAISE EXCEPTION 'Relay reservations remain active; do not restore legacy accounting yet';
  END IF;
END $$;

-- Preserve the current allowance while closing direct RPC ownership and replay gaps.
CREATE OR REPLACE FUNCTION public.end_voice_session(
  p_session_id uuid, p_duration_seconds integer,
  p_messages_count integer DEFAULT 0, p_was_quota_limited boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_user_id uuid;
  v_ended_at timestamptz;
BEGIN
  IF p_duration_seconds IS NULL OR p_duration_seconds < 0 OR p_duration_seconds > 86400
     OR p_messages_count IS NULL OR p_messages_count < 0 OR p_messages_count > 100000
     OR p_was_quota_limited IS NULL THEN
    RAISE EXCEPTION 'Invalid session usage' USING ERRCODE = '22023';
  END IF;
  SELECT user_id, ended_at INTO v_user_id, v_ended_at
    FROM public.voice_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF coalesce(auth.role(), '') <> 'service_role'
     AND (auth.uid() IS NULL OR auth.uid() <> v_user_id) THEN
    RAISE EXCEPTION 'Session not found' USING ERRCODE = '42501';
  END IF;
  -- A claim admitted before EXECUTE was revoked may commit after the drain
  -- check. Its accounting must still be owned exclusively by the relay.
  IF EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE session_id = p_session_id) THEN
    UPDATE public.voice_sessions SET ended_at = now() WHERE id = p_session_id AND ended_at IS NULL
      AND EXISTS(SELECT 1 FROM public.voice_relay_reservations WHERE session_id = p_session_id AND claimed_at IS NULL);
    RETURN;
  END IF;
  IF v_ended_at IS NOT NULL THEN RETURN; END IF;
  UPDATE public.voice_sessions
    SET ended_at = now(), duration_seconds = p_duration_seconds,
        messages_count = p_messages_count, was_quota_limited = p_was_quota_limited
    WHERE id = p_session_id;
  PERFORM public.increment_voice_usage(v_user_id, p_duration_seconds / 60.0, date_trunc('month', now())::date);
END;
$$;

-- Keep reservation-aware quota and the service-only finalizer until all live relays settle.
-- Keep increment_voice_usage revoked: restoring anonymous negative increments would reopen quota bypass.
