-- ============================================================================
-- SOCIAL VITALITY INDEX: SECURITY FIX FOR get_users_with_scores()
-- ============================================================================
-- Migration: 20260123100000_fix_get_users_with_scores_security.sql
-- Purpose: Add service role check to prevent user enumeration
-- Issue: Function was callable by any authenticated user, allowing enumeration
-- ============================================================================

-- Update function to add service role check
CREATE OR REPLACE FUNCTION get_users_with_scores(p_min_days INTEGER DEFAULT 14)
RETURNS TABLE (
    user_id UUID,
    days_of_data BIGINT
) AS $$
BEGIN
    -- SECURITY: This function should only be called by Edge Functions (service role)
    IF current_setting('request.jwt.claim.role', true) != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: This function can only be called by Edge Functions'
            USING ERRCODE = 'PAUTH';
    END IF;

    RETURN QUERY
    SELECT
        svs.user_id,
        COUNT(DISTINCT svs.date) AS days_of_data
    FROM social_vitality_scores svs
    WHERE svs.date >= CURRENT_DATE - (p_min_days || ' days')::INTERVAL
    GROUP BY svs.user_id
    HAVING COUNT(DISTINCT svs.date) >= p_min_days;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_users_with_scores IS 'Get all users with at least N days of social vitality scores (for withdrawal detection) - SERVICE ROLE ONLY';
