-- Premium TTS Daily Cap
-- Updates synthesis quota to enforce 20/day limit even for premium users
-- Prevents runaway ElevenLabs costs from power users
--
-- Free tier: BLOCKED (handled in Edge Function)
-- Premium tier: 20/day (was unlimited)

-- ============================================================================
-- UPDATE SYNTHESIS QUOTA FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_and_increment_synthesis_quota(
    p_user_id UUID,
    p_is_premium BOOLEAN DEFAULT FALSE
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
    -- Free tier is blocked at Edge Function level, but enforce here too as safety
    IF p_is_premium THEN
        v_quota_limit := 20;  -- Premium: 20 synthesis requests per day (cost control)
    ELSE
        v_quota_limit := 0;   -- Free: 0 (blocked at Edge Function, this is fallback)
    END IF;

    -- Count today's synthesis requests
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE;

    -- Check if user has exceeded quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Quota not exceeded, record this request and allow
    INSERT INTO synthesis_requests (user_id) VALUES (p_user_id);

    RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, FALSE;
END;
$$;

-- Update documentation
COMMENT ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN) IS
    'Checks voice synthesis quota. Free: blocked (use native TTS), Premium: 20/day. Prevents ElevenLabs API cost overrun.';
