-- TTS Monthly Character Budget
-- Caps premium TTS spend at $5/month per user
-- Google Cloud TTS Standard: $4/1M chars = $0.000004/char
-- Budget: 1,250,000 characters/month = $5.00
--
-- Also reduces daily cap from 20 to 10 as secondary safeguard.

-- ============================================================================
-- ADD CHARACTER COUNT TO SYNTHESIS REQUESTS
-- ============================================================================

ALTER TABLE synthesis_requests
    ADD COLUMN IF NOT EXISTS character_count INT DEFAULT 0;

-- ============================================================================
-- MONTHLY BUDGET CHECK FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_tts_monthly_budget(
    p_user_id UUID,
    p_character_count INT
) RETURNS TABLE(
    allowed BOOLEAN,
    chars_used BIGINT,
    chars_limit BIGINT,
    chars_remaining BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_chars_used BIGINT;
    v_chars_limit BIGINT := 1250000;  -- $5/month at $0.000004/char
BEGIN
    -- Sum character count for current calendar month
    SELECT COALESCE(SUM(character_count), 0)::BIGINT INTO v_chars_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND created_at >= date_trunc('month', CURRENT_TIMESTAMP);

    -- Check if adding this request would exceed budget
    IF (v_chars_used + p_character_count) > v_chars_limit THEN
        RETURN QUERY SELECT
            FALSE,
            v_chars_used,
            v_chars_limit,
            GREATEST(v_chars_limit - v_chars_used, 0::BIGINT);
        RETURN;
    END IF;

    RETURN QUERY SELECT
        TRUE,
        v_chars_used,
        v_chars_limit,
        (v_chars_limit - v_chars_used - p_character_count)::BIGINT;
END;
$$;

COMMENT ON FUNCTION public.check_tts_monthly_budget(UUID, INT) IS
    'Checks if user has remaining TTS character budget for the month. Limit: 1,250,000 chars ($5.00 at Google Cloud TTS Standard pricing).';

-- ============================================================================
-- UPDATE DAILY CAP: 20 → 10 (secondary safeguard)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_and_increment_synthesis_quota(
    p_user_id UUID,
    p_is_premium BOOLEAN DEFAULT FALSE,
    p_character_count INT DEFAULT 0
) RETURNS TABLE(
    allowed BOOLEAN,
    quota_used INTEGER,
    quota_limit INTEGER,
    was_reset BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_quota_used INT;
    v_quota_limit INT;
BEGIN
    -- Set quota limit based on tier
    IF p_is_premium THEN
        v_quota_limit := 10;  -- Premium: 10/day (reduced from 20, monthly budget is primary control)
    ELSE
        v_quota_limit := 0;   -- Free: blocked at Edge Function level
    END IF;

    -- Count today's synthesis requests
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE;

    -- Check if user has exceeded daily quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Record this request with character count
    INSERT INTO synthesis_requests (user_id, character_count)
    VALUES (p_user_id, p_character_count);

    RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, FALSE;
END;
$$;

COMMENT ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN, INT) IS
    'Checks daily synthesis quota and records request. Free: blocked, Premium: 10/day. Records character count for monthly budget tracking.';

-- ============================================================================
-- GRANTS
-- ============================================================================

REVOKE ALL ON FUNCTION public.check_tts_monthly_budget(UUID, INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_tts_monthly_budget(UUID, INT) TO service_role;

-- Re-grant for updated signature
REVOKE ALL ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN, INT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN, INT) TO service_role;

-- ============================================================================
-- INDEX for monthly budget lookups
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_synthesis_requests_user_month
    ON synthesis_requests(user_id, created_at)
    WHERE character_count > 0;
