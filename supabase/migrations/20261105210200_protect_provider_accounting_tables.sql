-- Counter writes are performed by the existing SECURITY DEFINER/service paths.
-- Keep owner reads and prevent direct counter resets that bypass provider limits.
REVOKE INSERT,UPDATE,DELETE,TRUNCATE ON public.creative_quota_usage FROM PUBLIC,anon,authenticated;
ALTER POLICY "Service role can insert synthesis requests" ON public.synthesis_requests TO service_role;
ALTER TABLE public.synthesis_requests ADD CONSTRAINT synthesis_character_count_nonnegative
  CHECK(character_count >= 0) NOT VALID;

-- Only the authenticated voice-journal handler records trusted duration.
CREATE OR REPLACE FUNCTION public.increment_voice_quota(p_minutes integer)
 RETURNS TABLE(new_minutes integer, limit_reached boolean, voice_limit integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_is_premium BOOLEAN;
    v_limit INTEGER;
    v_new_minutes INTEGER;
BEGIN
    IF p_minutes IS NULL OR p_minutes < 0 OR p_minutes > 60 THEN
        RAISE EXCEPTION 'Invalid voice duration' USING ERRCODE='22023';
    END IF;
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    v_limit := CASE WHEN v_is_premium THEN 60 ELSE 5 END;

    -- Upsert and increment
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 0, p_minutes)
    ON CONFLICT (user_id, date)
    DO UPDATE SET voice_minutes_used = creative_quota_usage.voice_minutes_used + p_minutes
    RETURNING creative_quota_usage.voice_minutes_used INTO v_new_minutes;

    RETURN QUERY
    SELECT
        v_new_minutes,
        v_new_minutes >= v_limit,
        v_limit;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.increment_voice_quota(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.increment_voice_quota(integer) TO service_role;
