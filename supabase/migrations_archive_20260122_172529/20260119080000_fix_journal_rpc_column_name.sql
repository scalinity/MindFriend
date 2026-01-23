-- Fix RPC function to use correct column name (analyses_used instead of analyses_requested)
-- This corrects a bug where the RPC referenced the wrong column name

CREATE OR REPLACE FUNCTION increment_journal_analysis_usage(
    p_user_id UUID,
    p_date DATE
)
RETURNS TABLE(analyses_today INTEGER, quota_remaining INTEGER) AS $$
DECLARE
    current_count INTEGER;
    user_quota INTEGER;
BEGIN
    -- Get user's quota (NULL means unlimited for premium)
    SELECT e.journal_analysis_daily_quota INTO user_quota
    FROM subscriptions s
    LEFT JOIN entitlements e ON e.tier = s.tier
    WHERE s.user_id = p_user_id;

    -- Default to free tier quota if no subscription found
    IF user_quota IS NULL AND NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE user_id = p_user_id AND tier IN ('premium', 'premium_annual')
    ) THEN
        user_quota := 3;
    END IF;

    -- Upsert the daily usage count (using correct column name: analyses_used)
    INSERT INTO journal_daily_usage (user_id, date, analyses_used)
    VALUES (p_user_id, p_date, 1)
    ON CONFLICT (user_id, date)
    DO UPDATE SET analyses_used = journal_daily_usage.analyses_used + 1
    RETURNING journal_daily_usage.analyses_used INTO current_count;

    -- Return the current count and remaining quota
    RETURN QUERY SELECT
        current_count,
        CASE
            WHEN user_quota IS NULL THEN -1  -- Unlimited
            ELSE GREATEST(0, user_quota - current_count)
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION increment_journal_analysis_usage IS 'Atomically increments journal analysis usage count and returns current usage';
