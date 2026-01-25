-- ============================================================================
-- Migration: Biofeedback Adaptation System
-- Feature: F024 - Real-time physiological adaptation using Apple Watch data
-- ============================================================================

-- ============================================================================
-- ALTER: biometric_baselines - Add columns for detailed baseline data
-- The existing table has generic metric_type/baseline_value columns.
-- We add specific HR/HRV columns for the adaptation engine.
-- ============================================================================
ALTER TABLE biometric_baselines
    ADD COLUMN IF NOT EXISTS resting_heart_rate DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS resting_hrv DECIMAL(6,2),
    ADD COLUMN IF NOT EXISTS exercise_recovery_rate DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS stress_hr_threshold DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS relaxed_hr_threshold DECIMAL(5,2),
    ADD COLUMN IF NOT EXISTS sample_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS confidence_score DECIMAL(3,2) DEFAULT 0;

-- ============================================================================
-- ALTER: biofeedback_sessions - Add columns for adaptation tracking
-- ============================================================================
ALTER TABLE biofeedback_sessions
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS was_extended BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS extension_seconds INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS adaptation_mode TEXT DEFAULT 'auto',
    ADD COLUMN IF NOT EXISTS exercise_session_id UUID;

-- Add foreign key constraint if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'biofeedback_sessions_exercise_session_id_fkey'
    ) THEN
        ALTER TABLE biofeedback_sessions
            ADD CONSTRAINT biofeedback_sessions_exercise_session_id_fkey
            FOREIGN KEY (exercise_session_id) REFERENCES exercise_sessions(id) ON DELETE SET NULL;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Could not add foreign key (table may not exist): %', SQLERRM;
END $$;

-- Add check constraint for adaptation_mode if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'biofeedback_sessions_adaptation_mode_check'
    ) THEN
        ALTER TABLE biofeedback_sessions
            ADD CONSTRAINT biofeedback_sessions_adaptation_mode_check
            CHECK (adaptation_mode IN ('auto', 'gentle', 'aggressive', 'off'));
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL; -- Constraint may already exist with different name
END $$;

-- ============================================================================
-- Table: biofeedback_readings
-- Purpose: Store real-time biometric readings during sessions
-- ============================================================================
CREATE TABLE IF NOT EXISTS biofeedback_readings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES biofeedback_sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    heart_rate DECIMAL(5,2) NOT NULL CHECK (heart_rate >= 30 AND heart_rate <= 250),
    hrv_sdnn DECIMAL(6,2) CHECK (hrv_sdnn >= 0 AND hrv_sdnn <= 300),
    hrv_rmssd DECIMAL(6,2) CHECK (hrv_rmssd >= 0 AND hrv_rmssd <= 300),
    relative_stress_level DECIMAL(3,2) CHECK (relative_stress_level >= 0 AND relative_stress_level <= 1),
    adaptation_applied JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- Table: biofeedback_adaptations
-- Purpose: Track adaptations made during sessions
-- ============================================================================
CREATE TABLE IF NOT EXISTS biofeedback_adaptations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES biofeedback_sessions(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    adaptation_type TEXT NOT NULL CHECK (adaptation_type IN (
        'breathing_pace', 'exercise_extension', 'intensity_reduction',
        'guidance_frequency', 'visual_feedback', 'audio_tempo'
    )),
    previous_value JSONB,
    new_value JSONB NOT NULL,
    trigger_reason TEXT,
    biometric_trigger JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- Table: biofeedback_summaries
-- Purpose: Store session summary metrics for analytics and user display
-- ============================================================================
CREATE TABLE IF NOT EXISTS biofeedback_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES biofeedback_sessions(id) ON DELETE CASCADE,
    starting_heart_rate DECIMAL(5,2) CHECK (starting_heart_rate >= 30 AND starting_heart_rate <= 250),
    ending_heart_rate DECIMAL(5,2) CHECK (ending_heart_rate >= 30 AND ending_heart_rate <= 250),
    lowest_heart_rate DECIMAL(5,2) CHECK (lowest_heart_rate >= 30 AND lowest_heart_rate <= 250),
    highest_heart_rate DECIMAL(5,2) CHECK (highest_heart_rate >= 30 AND highest_heart_rate <= 250),
    average_heart_rate DECIMAL(5,2) CHECK (average_heart_rate >= 30 AND average_heart_rate <= 250),
    starting_hrv DECIMAL(6,2) CHECK (starting_hrv >= 0 AND starting_hrv <= 300),
    ending_hrv DECIMAL(6,2) CHECK (ending_hrv >= 0 AND ending_hrv <= 300),
    hrv_improvement_percent DECIMAL(5,2),
    time_to_relaxation_seconds INTEGER CHECK (time_to_relaxation_seconds >= 0),
    total_adaptations INTEGER DEFAULT 0 CHECK (total_adaptations >= 0),
    effectiveness_score DECIMAL(3,2) CHECK (effectiveness_score >= 0 AND effectiveness_score <= 1),
    comparison_to_baseline JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(session_id)
);

-- ============================================================================
-- Table: healthkit_heart_rate
-- Purpose: Store synced heart rate data from HealthKit for baseline calculation
-- ============================================================================
CREATE TABLE IF NOT EXISTS healthkit_heart_rate (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    sample_date TIMESTAMPTZ NOT NULL,
    heart_rate DECIMAL(5,2) NOT NULL CHECK (heart_rate >= 30 AND heart_rate <= 250),
    source_device TEXT,
    context TEXT CHECK (context IN ('active', 'resting', 'workout', 'sleep', 'unknown')),
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- Table: healthkit_hrv
-- Purpose: Store synced HRV data from HealthKit for baseline calculation
-- ============================================================================
CREATE TABLE IF NOT EXISTS healthkit_hrv (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    sample_date TIMESTAMPTZ NOT NULL,
    hrv_sdnn DECIMAL(6,2) CHECK (hrv_sdnn >= 0 AND hrv_sdnn <= 300),
    hrv_rmssd DECIMAL(6,2) CHECK (hrv_rmssd >= 0 AND hrv_rmssd <= 300),
    source_device TEXT,
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- Indexes for Performance
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_biofeedback_readings_session_id ON biofeedback_readings(session_id);
CREATE INDEX IF NOT EXISTS idx_biofeedback_readings_timestamp ON biofeedback_readings(session_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_biofeedback_adaptations_session_id ON biofeedback_adaptations(session_id);
CREATE INDEX IF NOT EXISTS idx_biofeedback_summaries_session_id ON biofeedback_summaries(session_id);
CREATE INDEX IF NOT EXISTS idx_healthkit_heart_rate_user_date ON healthkit_heart_rate(user_id, sample_date DESC);
CREATE INDEX IF NOT EXISTS idx_healthkit_hrv_user_date ON healthkit_hrv(user_id, sample_date DESC);

-- ============================================================================
-- Row Level Security Policies
-- ============================================================================

-- Enable RLS on new tables
ALTER TABLE biofeedback_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE biofeedback_adaptations ENABLE ROW LEVEL SECURITY;
ALTER TABLE biofeedback_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE healthkit_heart_rate ENABLE ROW LEVEL SECURITY;
ALTER TABLE healthkit_hrv ENABLE ROW LEVEL SECURITY;

-- biofeedback_readings policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_read_own_biofeedback_readings') THEN
        CREATE POLICY users_read_own_biofeedback_readings ON biofeedback_readings
            FOR SELECT USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_insert_own_biofeedback_readings') THEN
        CREATE POLICY users_insert_own_biofeedback_readings ON biofeedback_readings
            FOR INSERT WITH CHECK (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_adaptations policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_read_own_biofeedback_adaptations') THEN
        CREATE POLICY users_read_own_biofeedback_adaptations ON biofeedback_adaptations
            FOR SELECT USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_insert_own_biofeedback_adaptations') THEN
        CREATE POLICY users_insert_own_biofeedback_adaptations ON biofeedback_adaptations
            FOR INSERT WITH CHECK (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- biofeedback_summaries policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_read_own_biofeedback_summaries') THEN
        CREATE POLICY users_read_own_biofeedback_summaries ON biofeedback_summaries
            FOR SELECT USING (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_insert_own_biofeedback_summaries') THEN
        CREATE POLICY users_insert_own_biofeedback_summaries ON biofeedback_summaries
            FOR INSERT WITH CHECK (
                session_id IN (SELECT id FROM biofeedback_sessions WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- healthkit_heart_rate policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_read_own_healthkit_heart_rate') THEN
        CREATE POLICY users_read_own_healthkit_heart_rate ON healthkit_heart_rate
            FOR SELECT USING (user_id = auth.uid());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_insert_own_healthkit_heart_rate') THEN
        CREATE POLICY users_insert_own_healthkit_heart_rate ON healthkit_heart_rate
            FOR INSERT WITH CHECK (user_id = auth.uid());
    END IF;
END $$;

-- healthkit_hrv policies
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_read_own_healthkit_hrv') THEN
        CREATE POLICY users_read_own_healthkit_hrv ON healthkit_hrv
            FOR SELECT USING (user_id = auth.uid());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_insert_own_healthkit_hrv') THEN
        CREATE POLICY users_insert_own_healthkit_hrv ON healthkit_hrv
            FOR INSERT WITH CHECK (user_id = auth.uid());
    END IF;
END $$;

-- ============================================================================
-- Function: Calculate biofeedback session summary
-- ============================================================================
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

        -- Calculate HRV improvement percentage
        IF v_starting_hrv IS NOT NULL AND v_starting_hrv > 0 AND v_ending_hrv IS NOT NULL THEN
            v_hrv_improvement := ((v_ending_hrv - v_starting_hrv) / v_starting_hrv) * 100;
        END IF;

        -- Calculate time to relaxation (time until HR dropped significantly)
        SELECT EXTRACT(EPOCH FROM (timestamp - NEW.started_at))::INTEGER INTO v_time_to_relax
        FROM biofeedback_readings
        WHERE session_id = NEW.id
            AND heart_rate <= COALESCE(v_starting_hr * 0.9, v_avg_hr)
        ORDER BY timestamp ASC
        LIMIT 1;

        -- Count total adaptations
        SELECT COUNT(*) INTO v_total_adaptations
        FROM biofeedback_adaptations
        WHERE session_id = NEW.id;

        -- Calculate effectiveness score (0-1 based on HR reduction and HRV improvement)
        v_effectiveness := 0.5; -- Base score

        IF v_starting_hr IS NOT NULL AND v_ending_hr IS NOT NULL THEN
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for automatic summary calculation
DROP TRIGGER IF EXISTS trigger_calculate_biofeedback_summary ON biofeedback_sessions;
CREATE TRIGGER trigger_calculate_biofeedback_summary
    AFTER UPDATE ON biofeedback_sessions
    FOR EACH ROW
    EXECUTE FUNCTION calculate_biofeedback_summary();

-- ============================================================================
-- Grant Service Role Access
-- ============================================================================
GRANT ALL ON biofeedback_readings TO service_role;
GRANT ALL ON biofeedback_adaptations TO service_role;
GRANT ALL ON biofeedback_summaries TO service_role;
GRANT ALL ON healthkit_heart_rate TO service_role;
GRANT ALL ON healthkit_hrv TO service_role;
