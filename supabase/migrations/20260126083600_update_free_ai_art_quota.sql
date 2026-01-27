-- Update free tier AI art quota from 1 to 2 images per day
-- Premium remains at 20 per day

CREATE OR REPLACE FUNCTION public.get_creative_quota()
RETURNS TABLE(
    ai_art_count integer,
    ai_art_limit integer,
    voice_minutes_used integer,
    voice_minutes_limit integer,
    is_premium boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_premium BOOLEAN := FALSE;
    v_today DATE := CURRENT_DATE;
BEGIN
    -- Check if user is authenticated
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check premium status
    SELECT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
        AND (expires_at IS NULL OR expires_at > NOW())
    ) INTO v_is_premium;

    -- Ensure quota record exists for today
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 0, 0)
    ON CONFLICT (user_id, date) DO NOTHING;

    -- Return quota info
    -- Free tier: 2 AI art per day
    -- Premium: 20 AI art per day
    RETURN QUERY
    SELECT
        cqu.ai_art_count,
        CASE WHEN v_is_premium THEN 20 ELSE 2 END AS ai_art_limit,
        cqu.voice_minutes_used,
        CASE WHEN v_is_premium THEN 60 ELSE 5 END AS voice_minutes_limit,
        v_is_premium
    FROM creative_quota_usage cqu
    WHERE cqu.user_id = v_user_id AND cqu.date = v_today;
END;
$$;
