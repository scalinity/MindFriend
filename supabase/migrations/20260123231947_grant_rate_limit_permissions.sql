-- =====================================================
-- Migration: Grant Execute Permission on Rate Limit RPC
-- Description: Allow service_role and authenticated users to call rate limit function
-- Date: 2026-01-23
-- =====================================================

-- Grant execute permission to authenticated users (for direct calls)
GRANT EXECUTE ON FUNCTION check_capacity_rate_limit(UUID, BIGINT, INT) TO authenticated;

-- Grant execute permission to service_role (for edge function calls)
GRANT EXECUTE ON FUNCTION check_capacity_rate_limit(UUID, BIGINT, INT) TO service_role;

-- Grant execute permission to anon role (in case needed for public endpoints)
GRANT EXECUTE ON FUNCTION check_capacity_rate_limit(UUID, BIGINT, INT) TO anon;

COMMENT ON FUNCTION check_capacity_rate_limit IS 'Atomically check and increment rate limit counter (service role compatible) - v2 with grants';
