-- ============================================================================
-- Migration: Biofeedback Security Hardening
-- Purpose: Add missing RLS policies and fix security issues identified in review
-- ============================================================================

-- ============================================================================
-- ADD UPDATE/DELETE RLS POLICIES
-- ============================================================================

-- biofeedback_readings UPDATE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_update_own_biofeedback_readings') THEN
        CREATE POLICY users_update_own_biofeedback_readings ON biofeedback_readings
            FOR UPDATE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_readings DELETE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_biofeedback_readings') THEN
        CREATE POLICY users_delete_own_biofeedback_readings ON biofeedback_readings
            FOR DELETE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_adaptations UPDATE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_update_own_biofeedback_adaptations') THEN
        CREATE POLICY users_update_own_biofeedback_adaptations ON biofeedback_adaptations
            FOR UPDATE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_adaptations DELETE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_biofeedback_adaptations') THEN
        CREATE POLICY users_delete_own_biofeedback_adaptations ON biofeedback_adaptations
            FOR DELETE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_summaries UPDATE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_update_own_biofeedback_summaries') THEN
        CREATE POLICY users_update_own_biofeedback_summaries ON biofeedback_summaries
            FOR UPDATE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_summaries DELETE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_biofeedback_summaries') THEN
        CREATE POLICY users_delete_own_biofeedback_summaries ON biofeedback_summaries
            FOR DELETE USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- healthkit_heart_rate UPDATE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_update_own_healthkit_heart_rate') THEN
        CREATE POLICY users_update_own_healthkit_heart_rate ON healthkit_heart_rate
            FOR UPDATE USING (user_id = auth.uid());
    END IF;
END $$;

-- healthkit_heart_rate DELETE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_healthkit_heart_rate') THEN
        CREATE POLICY users_delete_own_healthkit_heart_rate ON healthkit_heart_rate
            FOR DELETE USING (user_id = auth.uid());
    END IF;
END $$;

-- healthkit_hrv UPDATE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_update_own_healthkit_hrv') THEN
        CREATE POLICY users_update_own_healthkit_hrv ON healthkit_hrv
            FOR UPDATE USING (user_id = auth.uid());
    END IF;
END $$;

-- healthkit_hrv DELETE policy
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_healthkit_hrv') THEN
        CREATE POLICY users_delete_own_healthkit_hrv ON healthkit_hrv
            FOR DELETE USING (user_id = auth.uid());
    END IF;
END $$;

-- ============================================================================
-- ADD DELETE POLICY FOR BIOFEEDBACK_PREFERENCES
-- ============================================================================

-- biofeedback_preferences DELETE policy (missing from original migration)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_delete_own_biofeedback_preferences') THEN
        CREATE POLICY users_delete_own_biofeedback_preferences ON biofeedback_preferences
            FOR DELETE USING (user_id = auth.uid());
    END IF;
END $$;

-- ============================================================================
-- RATE LIMITING FOR BIOMETRIC READINGS
-- ============================================================================

-- Create rate limit tracking table
CREATE TABLE IF NOT EXISTS biofeedback_rate_limits (
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    window_start TIMESTAMPTZ NOT NULL,
    reading_count INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, window_start)
);

-- Index for efficient cleanup
CREATE INDEX IF NOT EXISTS idx_biofeedback_rate_limits_window
    ON biofeedback_rate_limits(window_start);

-- Enable RLS on rate limits table
ALTER TABLE biofeedback_rate_limits ENABLE ROW LEVEL SECURITY;

-- Service role only access for rate limits
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'service_role_manage_rate_limits') THEN
        CREATE POLICY service_role_manage_rate_limits ON biofeedback_rate_limits
            FOR ALL USING (auth.role() = 'service_role');
    END IF;
END $$;

-- Function to check rate limit (max 60 readings per minute per user)
CREATE OR REPLACE FUNCTION check_biofeedback_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_window_start TIMESTAMPTZ;
    v_current_count INTEGER;
    v_max_readings_per_minute CONSTANT INTEGER := 60;
BEGIN
    -- Get user_id from the session
    SELECT user_id INTO v_user_id
    FROM biofeedback_sessions
    WHERE id = NEW.session_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Invalid session_id';
    END IF;

    -- Get current minute window
    v_window_start := date_trunc('minute', NOW());

    -- Upsert rate limit counter
    INSERT INTO biofeedback_rate_limits (user_id, window_start, reading_count)
    VALUES (v_user_id, v_window_start, 1)
    ON CONFLICT (user_id, window_start)
    DO UPDATE SET reading_count = biofeedback_rate_limits.reading_count + 1
    RETURNING reading_count INTO v_current_count;

    -- Check if over limit
    IF v_current_count > v_max_readings_per_minute THEN
        RAISE EXCEPTION 'Rate limit exceeded: max % readings per minute', v_max_readings_per_minute;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Create trigger for rate limiting
DROP TRIGGER IF EXISTS trigger_biofeedback_rate_limit ON biofeedback_readings;
CREATE TRIGGER trigger_biofeedback_rate_limit
    BEFORE INSERT ON biofeedback_readings
    FOR EACH ROW
    EXECUTE FUNCTION check_biofeedback_rate_limit();

-- ============================================================================
-- FIX: Change summary function from SECURITY DEFINER to SECURITY INVOKER
-- ============================================================================

-- Recreate the summary function with SECURITY INVOKER
CREATE OR REPLACE FUNCTION calculate_biofeedback_summary()
RETURNS TRIGGER AS $$
DECLARE
    v_starting_hr DECIMAL(5,2);
    v_ending_hr DECIMAL(5,2);
    v_lowest_hr DECIMAL(5,2);
    v_highest_hr DECIMAL(5,2);
    v_avg_hr DECIMAL(5,2);
    v_starting_hrv DECIMAL(6,2);
    v_ending_hrv DECIMAL(6,2);
    v_hrv_improvement DECIMAL(5,2);
    v_time_to_relax INTEGER;
    v_total_adaptations INTEGER;
    v_effectiveness DECIMAL(3,2);
BEGIN
    -- Only calculate if completed_at was just set
    IF NEW.completed_at IS NOT NULL AND (OLD.completed_at IS NULL OR OLD.completed_at IS DISTINCT FROM NEW.completed_at) THEN
        -- Verify user owns this session (RLS check)
        IF NEW.user_id != auth.uid() AND auth.role() != 'service_role' THEN
            RETURN NEW; -- Silently skip for unauthorized access
        END IF;

        -- Get starting heart rate (first reading)
        SELECT heart_rate INTO v_starting_hr
        FROM biofeedback_readings
        WHERE session_id = NEW.id
        ORDER BY timestamp ASC
        LIMIT 1;

        -- Get ending heart rate (last reading)
        SELECT heart_rate INTO v_ending_hr
        FROM biofeedback_readings
        WHERE session_id = NEW.id
        ORDER BY timestamp DESC
        LIMIT 1;

        -- Get min/max/avg heart rate
        SELECT
            MIN(heart_rate),
            MAX(heart_rate),
            AVG(heart_rate)
        INTO v_lowest_hr, v_highest_hr, v_avg_hr
        FROM biofeedback_readings
        WHERE session_id = NEW.id;

        -- Get starting HRV (first reading with HRV)
        SELECT hrv_rmssd INTO v_starting_hrv
        FROM biofeedback_readings
        WHERE session_id = NEW.id AND hrv_rmssd IS NOT NULL
        ORDER BY timestamp ASC
        LIMIT 1;

        -- Get ending HRV (last reading with HRV)
        SELECT hrv_rmssd INTO v_ending_hrv
        FROM biofeedback_readings
        WHERE session_id = NEW.id AND hrv_rmssd IS NOT NULL
        ORDER BY timestamp DESC
        LIMIT 1;

        -- Calculate HRV improvement percentage (with division by zero protection)
        IF v_starting_hrv IS NOT NULL AND v_starting_hrv > 0.01 AND v_ending_hrv IS NOT NULL THEN
            v_hrv_improvement := ((v_ending_hrv - v_starting_hrv) / v_starting_hrv) * 100;
        END IF;

        -- Calculate time to relaxation (time until HR dropped significantly)
        -- Handle case where starting HR might be null
        IF v_starting_hr IS NOT NULL THEN
            SELECT EXTRACT(EPOCH FROM (timestamp - NEW.started_at))::INTEGER INTO v_time_to_relax
            FROM biofeedback_readings
            WHERE session_id = NEW.id
                AND heart_rate <= GREATEST(v_starting_hr * 0.9, COALESCE(v_avg_hr, v_starting_hr))
            ORDER BY timestamp ASC
            LIMIT 1;
        END IF;

        -- Count total adaptations
        SELECT COUNT(*) INTO v_total_adaptations
        FROM biofeedback_adaptations
        WHERE session_id = NEW.id;

        -- Calculate effectiveness score (0-1 based on HR reduction and HRV improvement)
        v_effectiveness := 0.5; -- Base score

        IF v_starting_hr IS NOT NULL AND v_ending_hr IS NOT NULL AND v_starting_hr > 0 THEN
            -- Add up to 0.3 for HR reduction
            IF v_ending_hr < v_starting_hr THEN
                v_effectiveness := v_effectiveness + LEAST(0.3, (v_starting_hr - v_ending_hr) / 30.0);
            END IF;
        END IF;

        IF v_hrv_improvement IS NOT NULL AND v_hrv_improvement > 0 THEN
            -- Add up to 0.2 for HRV improvement
            v_effectiveness := v_effectiveness + LEAST(0.2, v_hrv_improvement / 100.0);
        END IF;

        -- Ensure effectiveness is capped at 1.0
        v_effectiveness := LEAST(1.0, v_effectiveness);

        -- Insert or update summary
        INSERT INTO biofeedback_summaries (
            session_id,
            starting_heart_rate,
            ending_heart_rate,
            lowest_heart_rate,
            highest_heart_rate,
            average_heart_rate,
            starting_hrv,
            ending_hrv,
            hrv_improvement_percent,
            time_to_relaxation_seconds,
            total_adaptations,
            effectiveness_score
        ) VALUES (
            NEW.id,
            v_starting_hr,
            v_ending_hr,
            v_lowest_hr,
            v_highest_hr,
            v_avg_hr,
            v_starting_hrv,
            v_ending_hrv,
            v_hrv_improvement,
            v_time_to_relax,
            v_total_adaptations,
            v_effectiveness
        )
        ON CONFLICT (session_id) DO UPDATE SET
            starting_heart_rate = EXCLUDED.starting_heart_rate,
            ending_heart_rate = EXCLUDED.ending_heart_rate,
            lowest_heart_rate = EXCLUDED.lowest_heart_rate,
            highest_heart_rate = EXCLUDED.highest_heart_rate,
            average_heart_rate = EXCLUDED.average_heart_rate,
            starting_hrv = EXCLUDED.starting_hrv,
            ending_hrv = EXCLUDED.ending_hrv,
            hrv_improvement_percent = EXCLUDED.hrv_improvement_percent,
            time_to_relaxation_seconds = EXCLUDED.time_to_relaxation_seconds,
            total_adaptations = EXCLUDED.total_adaptations,
            effectiveness_score = EXCLUDED.effectiveness_score;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- ============================================================================
-- DATA RETENTION POLICY
-- ============================================================================

-- Function to clean up old rate limit records (run daily via cron)
CREATE OR REPLACE FUNCTION cleanup_biofeedback_rate_limits()
RETURNS void AS $$
BEGIN
    DELETE FROM biofeedback_rate_limits
    WHERE window_start < NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Function to clean up old HealthKit data (retain 90 days for baseline calculation)
CREATE OR REPLACE FUNCTION cleanup_old_healthkit_data()
RETURNS void AS $$
BEGIN
    -- Delete HealthKit heart rate data older than 90 days
    DELETE FROM healthkit_heart_rate
    WHERE sample_date < NOW() - INTERVAL '90 days';

    -- Delete HealthKit HRV data older than 90 days
    DELETE FROM healthkit_hrv
    WHERE sample_date < NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- Grant service role access to rate limits table
GRANT ALL ON biofeedback_rate_limits TO service_role;

-- ============================================================================
-- COMMENT: PHI Data Encryption Note
-- ============================================================================
-- Note: For full HIPAA compliance, consider implementing column-level encryption
-- for heart_rate, hrv_sdnn, and hrv_rmssd columns using pgcrypto or a
-- client-side encryption solution like Supabase Vault.
-- The current implementation relies on:
-- 1. RLS policies for access control
-- 2. Supabase's encryption at rest
-- 3. TLS for encryption in transit
-- 4. Rate limiting to prevent data exfiltration
