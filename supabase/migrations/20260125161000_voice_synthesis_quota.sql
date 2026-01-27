-- Voice Synthesis Quota for Free Tier Users
-- Prevents abuse of ElevenLabs TTS API by limiting free tier re-synthesis attempts
--
-- Free tier: 5 synthesis requests per day (includes initial generation + re-synthesis)
-- Premium/Family: Unlimited
--
-- Note: This is separate from content generation quota (3/day for free).
-- A user generates content once, but may want to re-synthesize with different voices.

-- ============================================================================
-- SYNTHESIS QUOTA FUNCTION
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
    v_quota_limit INT := 5;  -- Free tier: 5 synthesis requests per day
BEGIN
    -- Premium users: always allowed, no limit
    IF p_is_premium THEN
        -- Just count for analytics, no enforcement
        SELECT COUNT(*)::INT INTO v_quota_used
        FROM synthesis_requests
        WHERE user_id = p_user_id
        AND DATE(created_at) = CURRENT_DATE;

        RETURN QUERY SELECT TRUE, v_quota_used, -1, FALSE;
        RETURN;
    END IF;

    -- Free users: count today's synthesis requests
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE;

    -- Check if user has already exceeded quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Quota not exceeded, record this request and allow
    INSERT INTO synthesis_requests (user_id) VALUES (p_user_id);

    RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, FALSE;
END;
$$;

-- Add documentation
COMMENT ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN) IS
    'Checks voice synthesis quota. Free: 5/day, Premium: unlimited. Prevents ElevenLabs API abuse.';

-- ============================================================================
-- SYNTHESIS REQUESTS TRACKING TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.synthesis_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Index for efficient daily quota lookups
CREATE INDEX IF NOT EXISTS idx_synthesis_requests_user_date
    ON synthesis_requests(user_id, created_at);

-- Add RLS
ALTER TABLE synthesis_requests ENABLE ROW LEVEL SECURITY;

-- Users can only see their own requests (for transparency in UI)
CREATE POLICY "Users can view own synthesis requests"
    ON synthesis_requests FOR SELECT
    USING (auth.uid() = user_id);

-- Only service_role can insert (via Edge Function)
CREATE POLICY "Service role can insert synthesis requests"
    ON synthesis_requests FOR INSERT
    WITH CHECK (TRUE);

-- ============================================================================
-- GRANTS - SERVICE ROLE ONLY (Security)
-- ============================================================================

-- Revoke from anon/authenticated to prevent client-side manipulation
REVOKE ALL ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN) FROM anon, authenticated;

-- Grant only to service_role (Edge Functions)
GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(UUID, BOOLEAN) TO service_role;

-- Table grants
GRANT SELECT ON synthesis_requests TO authenticated;
GRANT ALL ON synthesis_requests TO service_role;

-- ============================================================================
-- CLEANUP JOB (Optional - run periodically to clean old records)
-- ============================================================================

-- Records older than 30 days can be safely deleted (quota is daily)
-- Run this via pg_cron or scheduled Edge Function:
-- DELETE FROM synthesis_requests WHERE created_at < NOW() - INTERVAL '30 days';
