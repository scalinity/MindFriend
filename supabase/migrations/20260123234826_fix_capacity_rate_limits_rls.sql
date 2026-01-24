-- =====================================================
-- Migration: Fix capacity_rate_limits RLS
-- Description: Ensure table exists and disable RLS since it's only accessed via SECURITY DEFINER RPC
-- Date: 2026-01-23
-- =====================================================

-- Create table if it doesn't exist (idempotent)
CREATE TABLE IF NOT EXISTS capacity_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    request_count INT NOT NULL DEFAULT 0,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_capacity_rate_limits_user ON capacity_rate_limits(user_id);

-- The capacity_rate_limits table is only accessed through the check_capacity_rate_limit() RPC function
-- which has SECURITY DEFINER and runs with elevated privileges.
-- Having RLS enabled causes issues when the RPC tries to access the table.
-- Since the RPC already enforces security (checks auth.uid() matches p_user_id), we can disable RLS.

ALTER TABLE capacity_rate_limits DISABLE ROW LEVEL SECURITY;

COMMENT ON TABLE capacity_rate_limits IS 'Rate limit tracking for capacity calculation endpoint (accessed via SECURITY DEFINER RPC only)';
