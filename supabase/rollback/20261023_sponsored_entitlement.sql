-- Restore the three pre-refresh quota bodies without deleting entitlement data.
-- Keep the authorized helper for installed clients; removing it requires an app rollback.
BEGIN;

CREATE OR REPLACE FUNCTION public.reserve_ai_image_quota(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE limit_count integer; reserved integer;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Missing image owner' USING ERRCODE='22023'; END IF;
  SELECT CASE WHEN EXISTS(SELECT FROM public.subscriptions WHERE user_id=p_user_id
    AND status='active' AND (expires_at IS NULL OR expires_at>now())) THEN 20 ELSE 2 END INTO limit_count;
  INSERT INTO public.creative_quota_usage(user_id,date,ai_art_count,voice_minutes_used)
    VALUES(p_user_id,current_date,1,0)
    ON CONFLICT(user_id,date) DO UPDATE SET ai_art_count=greatest(creative_quota_usage.ai_art_count,0)+1
      WHERE greatest(creative_quota_usage.ai_art_count,0)<limit_count
    RETURNING ai_art_count INTO reserved;
  RETURN reserved IS NOT NULL;
END $$;

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

COMMIT;
