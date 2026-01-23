-- Add RPC function for journal analysis usage tracking
-- This function is called by the analyze-journal Edge Function to atomically increment usage

-- Function to increment journal analysis usage
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

    -- Upsert the daily usage count
    INSERT INTO journal_daily_usage (user_id, date, analyses_requested)
    VALUES (p_user_id, p_date, 1)
    ON CONFLICT (user_id, date)
    DO UPDATE SET analyses_requested = journal_daily_usage.analyses_requested + 1
    RETURNING journal_daily_usage.analyses_requested INTO current_count;

    -- Return the current count and remaining quota
    RETURN QUERY SELECT
        current_count,
        CASE
            WHEN user_quota IS NULL THEN -1  -- Unlimited
            ELSE GREATEST(0, user_quota - current_count)
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION increment_journal_analysis_usage(UUID, DATE) TO authenticated;

COMMENT ON FUNCTION increment_journal_analysis_usage IS 'Atomically increments journal analysis usage count and returns current usage';
