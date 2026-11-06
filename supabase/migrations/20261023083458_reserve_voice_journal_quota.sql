BEGIN;

-- Service-only reservation before paid transcription; never refund uncertain calls.
CREATE OR REPLACE FUNCTION public.reserve_voice_journal_quota(p_user_id uuid, p_minutes integer)
RETURNS TABLE(allowed boolean, voice_minutes_used integer, voice_minutes_limit integer, is_premium boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_premium boolean;
    v_limit integer;
    v_used integer;
    v_reserved integer;
    v_today date := CURRENT_DATE;
BEGIN
    IF p_user_id IS NULL OR p_minutes IS NULL OR p_minutes <= 0 OR p_minutes > 10 THEN
        RAISE EXCEPTION 'Invalid voice journal reservation' USING ERRCODE = '22023';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions s
        WHERE s.user_id = p_user_id AND s.status = 'active'
          AND (s.expires_at IS NULL OR s.expires_at > now())
    ) INTO v_premium;
    v_limit := CASE WHEN v_premium THEN 60 ELSE 5 END;

    IF p_minutes <= v_limit THEN
        INSERT INTO public.creative_quota_usage AS usage (user_id, date, ai_art_count, voice_minutes_used)
        VALUES (p_user_id, v_today, 0, p_minutes)
        ON CONFLICT (user_id, date) DO UPDATE
        SET voice_minutes_used = greatest(usage.voice_minutes_used, 0) + p_minutes
        WHERE greatest(usage.voice_minutes_used, 0) + p_minutes <= v_limit
        RETURNING usage.voice_minutes_used INTO v_reserved;
    END IF;

    IF v_reserved IS NOT NULL THEN
        RETURN QUERY SELECT true, v_reserved, v_limit, v_premium;
    ELSE
        SELECT greatest(usage.voice_minutes_used, 0) INTO v_used
        FROM public.creative_quota_usage usage
        WHERE usage.user_id = p_user_id AND usage.date = v_today;
        RETURN QUERY SELECT false, coalesce(v_used, 0), v_limit, v_premium;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_voice_journal_quota(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_voice_journal_quota(uuid, integer) TO service_role;
COMMENT ON FUNCTION public.reserve_voice_journal_quota(uuid, integer) IS
'Atomically reserve declared voice journal minutes before xAI. Active unexpired subscriptions receive 60 minutes daily; free accounts receive 5. Reservations survive uncertain failures. Provider duration is available after billing and cannot enforce a hard provider cost cap.';

COMMIT;
