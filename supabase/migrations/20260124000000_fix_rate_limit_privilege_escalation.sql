-- Fix Rate Limit Privilege Escalation (P0 CRITICAL)
-- Addresses CVSS 8.1 security vulnerability from Phase 2 review
--
-- ISSUE: check_rate_limit() function was granted to anon and authenticated roles
-- This allowed ANY user to:
-- 1. Bypass rate limits by manipulating window parameters
-- 2. DOS attack other users by exhausting their rate limit counters
-- 3. Cause financial damage by triggering unlimited XAI API calls
--
-- FIX: Revoke function access from anon and authenticated, grant only to service_role
-- Edge Functions use service_role key, so legitimate rate limit checks continue to work

-- ============================================================================
-- REVOKE DANGEROUS GRANTS
-- ============================================================================

REVOKE ALL ON FUNCTION public.check_rate_limit(
  p_user_id UUID,
  p_endpoint TEXT,
  p_window_start TIMESTAMPTZ,
  p_max_requests INT,
  p_window_ms INT
) FROM anon, authenticated;

-- ============================================================================
-- GRANT TO SERVICE ROLE ONLY
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.check_rate_limit(
  p_user_id UUID,
  p_endpoint TEXT,
  p_window_start TIMESTAMPTZ,
  p_max_requests INT,
  p_window_ms INT
) TO service_role;

-- Add security documentation
COMMENT ON FUNCTION public.check_rate_limit IS
  'SECURITY: Only callable by service_role. Edge Functions enforce caller identity validation. Direct client calls are prohibited to prevent rate limit manipulation and DOS attacks.';

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- After deployment, verify grants with:
-- SELECT grantee, privilege_type
-- FROM information_schema.routine_privileges
-- WHERE routine_name = 'check_rate_limit';
-- Expected: Only service_role has EXECUTE
