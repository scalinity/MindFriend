-- ================================================
-- Migration: Atomic Rehearsal Quota Check
-- Created: 2026-01-20
-- Description: Add atomic database function for rehearsal quota enforcement
-- ================================================

-- Function to atomically check and increment rehearsal quota
CREATE OR REPLACE FUNCTION check_and_increment_rehearsal_quota(
    p_user_id UUID
) RETURNS TABLE (
    can_create BOOLEAN,
    used INTEGER,
    quota_limit INTEGER,
    reset_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_used INTEGER;
    v_reset_at TIMESTAMPTZ;
    v_is_premium BOOLEAN;
    v_quota_limit INTEGER := 2; -- Free tier limit
    v_week_ago TIMESTAMPTZ := NOW() - INTERVAL '7 days';
BEGIN
    -- Check if user is premium
    SELECT subscription_tier = 'premium' INTO v_is_premium
    FROM profiles
    WHERE id = p_user_id;

    -- Premium users have unlimited quota
    IF v_is_premium THEN
        RETURN QUERY SELECT TRUE, 0, 999999, NOW();
        RETURN;
    END IF;

    -- Get or create user settings with row-level lock
    SELECT
        COALESCE(rehearsals_used_this_week, 0),
        COALESCE(rehearsals_quota_reset_at, NOW())
    INTO v_used, v_reset_at
    FROM user_settings
    WHERE user_id = p_user_id
    FOR UPDATE; -- Lock the row

    -- If no settings exist, create them
    IF NOT FOUND THEN
        INSERT INTO user_settings (user_id, rehearsals_used_this_week, rehearsals_quota_reset_at)
        VALUES (p_user_id, 0, NOW())
        RETURNING rehearsals_used_this_week, rehearsals_quota_reset_at
        INTO v_used, v_reset_at;
    END IF;

    -- Check if quota needs reset
    IF v_reset_at < v_week_ago THEN
        v_used := 0;
        v_reset_at := NOW();
    END IF;

    -- Check if user can create new session
    IF v_used < v_quota_limit THEN
        -- Increment quota usage atomically
        UPDATE user_settings
        SET
            rehearsals_used_this_week = v_used + 1,
            rehearsals_quota_reset_at = v_reset_at
        WHERE user_id = p_user_id;

        RETURN QUERY SELECT TRUE, v_used + 1, v_quota_limit, v_reset_at + INTERVAL '7 days';
    ELSE
        -- Quota exceeded
        RETURN QUERY SELECT FALSE, v_used, v_quota_limit, v_reset_at + INTERVAL '7 days';
    END IF;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION check_and_increment_rehearsal_quota(UUID) TO authenticated;

COMMENT ON FUNCTION check_and_increment_rehearsal_quota IS
'Atomically checks and increments rehearsal quota to prevent race conditions';
