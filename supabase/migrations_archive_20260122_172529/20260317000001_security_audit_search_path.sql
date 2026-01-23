-- Security Hardening: SECURITY DEFINER Functions search_path (Audit Issue #003)
-- Fixes: Missing SET search_path = public on SECURITY DEFINER functions
-- Risk: Search path injection - malicious users could create functions with same names
--       in different schemas, causing SECURITY DEFINER functions to execute them instead
-- Solution: Add SET search_path = public to all SECURITY DEFINER functions

-- 1) Fix check_and_increment_ai_quota (defined in 20260114062000_chat_security_hardening.sql)
ALTER FUNCTION public.check_and_increment_ai_quota(UUID, BOOLEAN)
SET search_path = public;

-- 2) Fix check_rate_limit (defined in 20260114062000_chat_security_hardening.sql)
ALTER FUNCTION public.check_rate_limit(UUID, TEXT, TIMESTAMPTZ, INT, INT)
SET search_path = public;

-- 3) Verify both functions now have safe search_path
-- SELECT proname, prosecdef, proconfig FROM pg_proc
-- WHERE prosecdef AND proname IN ('check_and_increment_ai_quota', 'check_rate_limit');
-- Expected: Both should have proconfig containing 'search_path=public'

COMMENT ON FUNCTION public.check_and_increment_ai_quota(UUID, BOOLEAN) IS
  'Atomically checks and increments AI quota. SECURITY DEFINER with safe search_path.';

COMMENT ON FUNCTION public.check_rate_limit(UUID, TEXT, TIMESTAMPTZ, INT, INT) IS
  'Atomically checks and updates rate limit counters. SECURITY DEFINER with safe search_path.';
