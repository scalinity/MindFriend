-- Migration: Fix Critical Security Issues from Supabase Security Advisor
-- Created: 2026-01-27
-- Description: Enable RLS on tables and fix security definer views
--
-- Issues addressed:
-- 1. RLS Disabled: ar_exercise_sessions, ar_exercise_types, ar_scene_preferences,
--    capacity_rate_limits, mentorship_encryption_keys
-- 2. Security Definer Views: active_alerts, error_rate_summary, journal_entries_decrypted,
--    moods_decrypted, pathway_progress_decrypted, sanitization_summary

-- =============================================================================
-- PART 1: Enable RLS on tables
-- =============================================================================

-- ar_exercise_sessions
ALTER TABLE IF EXISTS ar_exercise_sessions ENABLE ROW LEVEL SECURITY;

-- Ensure policies exist
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_sessions'
        AND policyname = 'Users read own AR sessions'
    ) THEN
        CREATE POLICY "Users read own AR sessions"
            ON ar_exercise_sessions FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_sessions'
        AND policyname = 'Users insert own AR sessions'
    ) THEN
        CREATE POLICY "Users insert own AR sessions"
            ON ar_exercise_sessions FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_sessions'
        AND policyname = 'Users update own AR sessions'
    ) THEN
        CREATE POLICY "Users update own AR sessions"
            ON ar_exercise_sessions FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- ar_exercise_types
ALTER TABLE IF EXISTS ar_exercise_types ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_types'
        AND policyname = 'Authenticated users read AR exercise types'
    ) THEN
        CREATE POLICY "Authenticated users read AR exercise types"
            ON ar_exercise_types FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_types'
        AND policyname = 'Service role manages AR exercise types'
    ) THEN
        CREATE POLICY "Service role manages AR exercise types"
            ON ar_exercise_types FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- ar_scene_preferences
ALTER TABLE IF EXISTS ar_scene_preferences ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_scene_preferences'
        AND policyname = 'Users manage own AR scene preferences'
    ) THEN
        CREATE POLICY "Users manage own AR scene preferences"
            ON ar_scene_preferences FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- capacity_rate_limits (enable RLS with service-role-only access)
ALTER TABLE IF EXISTS capacity_rate_limits ENABLE ROW LEVEL SECURITY;

-- Drop any existing policy that might conflict
DROP POLICY IF EXISTS "Service role only for capacity rate limits" ON capacity_rate_limits;

-- Only service role can access (used by SECURITY DEFINER functions only)
CREATE POLICY "Service role only for capacity rate limits"
    ON capacity_rate_limits FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- mentorship_encryption_keys (already has RLS but ensure it's enforced)
ALTER TABLE IF EXISTS mentorship_encryption_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS mentorship_encryption_keys FORCE ROW LEVEL SECURITY;

-- Ensure deny-all policy exists for encryption keys
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'mentorship_encryption_keys'
        AND policyname = 'Deny all direct client access to encryption keys'
    ) THEN
        CREATE POLICY "Deny all direct client access to encryption keys"
            ON mentorship_encryption_keys FOR SELECT
            USING (FALSE);
    END IF;
END $$;

-- Add service role policy for encryption keys
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'mentorship_encryption_keys'
        AND policyname = 'Service role manages encryption keys'
    ) THEN
        CREATE POLICY "Service role manages encryption keys"
            ON mentorship_encryption_keys FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- =============================================================================
-- PART 2: Fix Security Definer Views
-- Recreate views with SECURITY INVOKER to respect RLS policies
-- =============================================================================

-- Note: In PostgreSQL 15+, views support SECURITY INVOKER attribute
-- For older versions, we use a workaround by creating functions

-- Fix active_alerts view
DROP VIEW IF EXISTS active_alerts CASCADE;
CREATE VIEW active_alerts
WITH (security_invoker = true)
AS
SELECT
    id,
    function_name,
    ROUND((error_rate * 100)::numeric, 2) AS error_rate_pct,
    ROUND((threshold * 100)::numeric, 2) AS threshold_pct,
    window_minutes,
    message,
    created_at,
    (NOW() - created_at) AS age
FROM error_alerts
WHERE acknowledged = FALSE
AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- Fix error_rate_summary view
DROP VIEW IF EXISTS error_rate_summary CASCADE;
CREATE VIEW error_rate_summary
WITH (security_invoker = true)
AS
SELECT
    function_name,
    DATE_TRUNC('hour', timestamp) AS hour,
    COUNT(*) AS error_count,
    COUNT(DISTINCT error_type) AS unique_error_types,
    ARRAY_AGG(DISTINCT error_type) AS error_types
FROM error_events
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY function_name, DATE_TRUNC('hour', timestamp)
ORDER BY hour DESC, error_count DESC;

-- Fix sanitization_summary view
DROP VIEW IF EXISTS sanitization_summary CASCADE;
CREATE VIEW sanitization_summary
WITH (security_invoker = true)
AS
WITH field_aggregates AS (
    SELECT
        date_trunc('day', sanitized_at) AS date,
        sanitization_method,
        array_agg(DISTINCT field) AS common_raw_fields
    FROM intervention_delivery_audit
    CROSS JOIN LATERAL unnest(raw_fields_detected) AS field
    WHERE cardinality(raw_fields_detected) > 0
    GROUP BY date_trunc('day', sanitized_at), sanitization_method
)
SELECT
    date_trunc('day', a.sanitized_at) AS date,
    a.sanitization_method,
    COUNT(*) AS total_deliveries,
    COUNT(CASE WHEN a.sanitization_applied THEN 1 END) AS sanitized_count,
    COUNT(CASE WHEN NOT a.sanitization_applied THEN 1 END) AS no_phi_count,
    f.common_raw_fields
FROM intervention_delivery_audit a
LEFT JOIN field_aggregates f ON
    date_trunc('day', a.sanitized_at) = f.date
    AND a.sanitization_method = f.sanitization_method
GROUP BY date_trunc('day', a.sanitized_at), a.sanitization_method, f.common_raw_fields
ORDER BY date DESC;

-- Fix journal_entries_decrypted view
-- These views were created ad-hoc and have SECURITY DEFINER (unsafe)
-- Just drop them - the app uses RLS-protected tables directly
DROP VIEW IF EXISTS journal_entries_decrypted CASCADE;

-- Fix moods_decrypted view
DROP VIEW IF EXISTS moods_decrypted CASCADE;

-- Fix pathway_progress_decrypted view
DROP VIEW IF EXISTS pathway_progress_decrypted CASCADE;

-- =============================================================================
-- PART 3: Add comments for documentation
-- =============================================================================

COMMENT ON VIEW active_alerts IS 'Unacknowledged alerts from the past 24 hours (SECURITY INVOKER - respects RLS)';
COMMENT ON VIEW error_rate_summary IS 'Hourly error rate summary for the past 24 hours (SECURITY INVOKER - respects RLS)';
COMMENT ON VIEW sanitization_summary IS 'Daily summary of PHI sanitization events (SECURITY INVOKER - respects RLS)';

-- Log completion
DO $$
BEGIN
    RAISE NOTICE 'Security fixes applied:';
    RAISE NOTICE '- RLS enabled on ar_exercise_sessions, ar_exercise_types, ar_scene_preferences';
    RAISE NOTICE '- RLS enabled on capacity_rate_limits (service_role only)';
    RAISE NOTICE '- RLS enforced on mentorship_encryption_keys';
    RAISE NOTICE '- Views recreated with SECURITY INVOKER: active_alerts, error_rate_summary, sanitization_summary';
    RAISE NOTICE '- Unsafe views dropped: journal_entries_decrypted, moods_decrypted, pathway_progress_decrypted';
END $$;
