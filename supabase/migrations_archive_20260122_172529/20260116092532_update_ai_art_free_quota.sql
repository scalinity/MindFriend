-- Update AI Art Free Tier Quota from 3 to 1
-- Free tier users now get 1 AI art generation per day (down from 3)
-- Premium users still get 20 per day

-- Update get_creative_quota function
CREATE OR REPLACE FUNCTION get_creative_quota()
RETURNS TABLE(
    ai_art_count INTEGER,
    ai_art_limit INTEGER,
    voice_minutes_used INTEGER,
    voice_minutes_limit INTEGER,
    is_premium BOOLEAN
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_is_premium BOOLEAN;
BEGIN
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    -- Get or create today's quota
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 0, 0)
    ON CONFLICT (user_id, date) DO NOTHING;

    -- Return quota info
    -- Free tier: 1 AI art per day (stricter paywall)
    -- Premium: 20 AI art per day
    RETURN QUERY
    SELECT
        cqu.ai_art_count,
        CASE WHEN v_is_premium THEN 20 ELSE 1 END AS ai_art_limit,
        cqu.voice_minutes_used,
        CASE WHEN v_is_premium THEN 60 ELSE 5 END AS voice_minutes_limit,
        v_is_premium
    FROM creative_quota_usage cqu
    WHERE cqu.user_id = v_user_id AND cqu.date = v_today;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update increment_ai_art_quota function
CREATE OR REPLACE FUNCTION increment_ai_art_quota()
RETURNS TABLE(
    new_count INTEGER,
    limit_reached BOOLEAN,
    ai_art_limit INTEGER
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_is_premium BOOLEAN;
    v_limit INTEGER;
    v_new_count INTEGER;
BEGIN
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    -- Free tier: 1 AI art per day (stricter paywall)
    -- Premium: 20 AI art per day
    v_limit := CASE WHEN v_is_premium THEN 20 ELSE 1 END;

    -- Upsert and increment
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 1, 0)
    ON CONFLICT (user_id, date)
    DO UPDATE SET ai_art_count = creative_quota_usage.ai_art_count + 1
    RETURNING creative_quota_usage.ai_art_count INTO v_new_count;

    RETURN QUERY
    SELECT
        v_new_count,
        v_new_count >= v_limit,
        v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
