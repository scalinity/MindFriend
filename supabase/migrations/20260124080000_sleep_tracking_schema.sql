-- Sleep Optimization System Schema
-- Feature: F012 - Sleep tracking, goals, insights, wind-down routines
-- Date: 2026-01-24

-- ============================================================================
-- TABLES
-- ============================================================================

-- Sleep entries (HealthKit sync + manual logging)
CREATE TABLE IF NOT EXISTS sleep_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('healthkit', 'manual', 'apple_watch')),

    -- Timing
    bedtime TIMESTAMPTZ NOT NULL,
    wake_time TIMESTAMPTZ NOT NULL,
    time_in_bed_minutes INTEGER NOT NULL CHECK (time_in_bed_minutes >= 60 AND time_in_bed_minutes <= 1440),
    time_asleep_minutes INTEGER CHECK (time_asleep_minutes <= time_in_bed_minutes),

    -- Stages (from wearables)
    deep_sleep_minutes INTEGER CHECK (deep_sleep_minutes >= 0),
    rem_sleep_minutes INTEGER CHECK (rem_sleep_minutes >= 0),
    light_sleep_minutes INTEGER CHECK (light_sleep_minutes >= 0),
    awake_minutes INTEGER CHECK (awake_minutes >= 0),

    -- Quality metrics
    sleep_efficiency DECIMAL(5,2) CHECK (sleep_efficiency >= 0 AND sleep_efficiency <= 100),
    heart_rate_avg INTEGER CHECK (heart_rate_avg >= 30 AND heart_rate_avg <= 200),
    heart_rate_min INTEGER CHECK (heart_rate_min >= 30 AND heart_rate_min <= 200),
    hrv_avg DECIMAL(5,2) CHECK (hrv_avg >= 0 AND hrv_avg <= 200),
    respiratory_rate DECIMAL(4,1) CHECK (respiratory_rate >= 8 AND respiratory_rate <= 30),

    -- User input
    user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
    dream_notes TEXT CHECK (char_length(dream_notes) <= 1000),
    notes TEXT CHECK (char_length(notes) <= 500),

    -- Calculated
    sleep_score INTEGER CHECK (sleep_score BETWEEN 0 AND 100),
    score_breakdown JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, date)
);

-- Sleep goals and preferences
CREATE TABLE IF NOT EXISTS sleep_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    target_bedtime TIME,
    target_wake_time TIME,
    target_duration_minutes INTEGER NOT NULL DEFAULT 480 CHECK (target_duration_minutes BETWEEN 240 AND 720),
    wind_down_duration_minutes INTEGER NOT NULL DEFAULT 30 CHECK (wind_down_duration_minutes BETWEEN 10 AND 120),

    bedtime_reminder_enabled BOOLEAN NOT NULL DEFAULT true,
    bedtime_reminder_offset_minutes INTEGER NOT NULL DEFAULT 60 CHECK (bedtime_reminder_offset_minutes BETWEEN 15 AND 120),

    preferred_wind_down_types TEXT[] DEFAULT ARRAY['breathing', 'meditation'],
    sleep_environment_prefs JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sleep debt tracking
CREATE TABLE IF NOT EXISTS sleep_debt (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    current_debt_minutes INTEGER NOT NULL DEFAULT 0,
    week_avg_duration_minutes INTEGER,
    optimal_duration_minutes INTEGER NOT NULL DEFAULT 480,
    last_calculated TIMESTAMPTZ NOT NULL DEFAULT now(),
    debt_history JSONB DEFAULT '[]',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Wind-down sessions
CREATE TABLE IF NOT EXISTS wind_down_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    routine JSONB NOT NULL,
    duration_planned_minutes INTEGER NOT NULL CHECK (duration_planned_minutes BETWEEN 5 AND 120),
    duration_actual_minutes INTEGER,
    completed BOOLEAN NOT NULL DEFAULT false,
    sleep_entry_id UUID REFERENCES sleep_entries(id) ON DELETE SET NULL,
    feedback_rating INTEGER CHECK (feedback_rating BETWEEN 1 AND 5),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sleep insights cache
CREATE TABLE IF NOT EXISTS sleep_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    insight_type TEXT NOT NULL CHECK (insight_type IN (
        'weekly_report',
        'mood_correlation',
        'pattern_detected',
        'improvement',
        'concern'
    )),
    insight_data JSONB NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ NOT NULL,
    viewed BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sleep_entries_user_date
    ON sleep_entries(user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_sleep_entries_user_score
    ON sleep_entries(user_id, sleep_score);

CREATE INDEX IF NOT EXISTS idx_sleep_entries_bedtime
    ON sleep_entries(user_id, bedtime DESC);

CREATE INDEX IF NOT EXISTS idx_wind_down_sessions_user
    ON wind_down_sessions(user_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_sleep_insights_user
    ON sleep_insights(user_id, generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_sleep_insights_type
    ON sleep_insights(user_id, insight_type);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE sleep_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_debt ENABLE ROW LEVEL SECURITY;
ALTER TABLE wind_down_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_insights ENABLE ROW LEVEL SECURITY;

-- Sleep entries policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_entries' AND policyname = 'Users can manage own sleep entries'
    ) THEN
        CREATE POLICY "Users can manage own sleep entries" ON sleep_entries
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Sleep goals policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_goals' AND policyname = 'Users can manage own sleep goals'
    ) THEN
        CREATE POLICY "Users can manage own sleep goals" ON sleep_goals
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Sleep debt policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_debt' AND policyname = 'Users can view own sleep debt'
    ) THEN
        CREATE POLICY "Users can view own sleep debt" ON sleep_debt
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_debt' AND policyname = 'Service role can update sleep debt'
    ) THEN
        CREATE POLICY "Service role can update sleep debt" ON sleep_debt
            FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
    END IF;
END $$;

-- Wind-down sessions policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'wind_down_sessions' AND policyname = 'Users can manage own wind-down sessions'
    ) THEN
        CREATE POLICY "Users can manage own wind-down sessions" ON wind_down_sessions
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Sleep insights policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_insights' AND policyname = 'Users can view own insights'
    ) THEN
        CREATE POLICY "Users can view own insights" ON sleep_insights
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_insights' AND policyname = 'Users can update own insights'
    ) THEN
        CREATE POLICY "Users can update own insights" ON sleep_insights
            FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_insights' AND policyname = 'Service role can manage insights'
    ) THEN
        CREATE POLICY "Service role can manage insights" ON sleep_insights
            FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
    END IF;
END $$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update updated_at timestamp for sleep_entries
CREATE OR REPLACE FUNCTION update_sleep_entries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_sleep_entries_updated_at ON sleep_entries;
CREATE TRIGGER trigger_update_sleep_entries_updated_at
    BEFORE UPDATE ON sleep_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_sleep_entries_updated_at();

-- Update updated_at timestamp for sleep_goals
CREATE OR REPLACE FUNCTION update_sleep_goals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_sleep_goals_updated_at ON sleep_goals;
CREATE TRIGGER trigger_update_sleep_goals_updated_at
    BEFORE UPDATE ON sleep_goals
    FOR EACH ROW
    EXECUTE FUNCTION update_sleep_goals_updated_at();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE sleep_entries IS 'Daily sleep logs from HealthKit or manual entry';
COMMENT ON TABLE sleep_goals IS 'User sleep targets and preferences';
COMMENT ON TABLE sleep_debt IS 'Cumulative sleep deficit tracking';
COMMENT ON TABLE wind_down_sessions IS 'Bedtime routine tracking with activity completion';
COMMENT ON TABLE sleep_insights IS 'Cached AI-generated sleep insights and recommendations';

COMMENT ON COLUMN sleep_entries.source IS 'Data source: healthkit, manual, or apple_watch';
COMMENT ON COLUMN sleep_entries.sleep_score IS 'Calculated quality score (0-100)';
COMMENT ON COLUMN sleep_entries.score_breakdown IS 'JSON breakdown: {duration, efficiency, timing, stages, restfulness}';
COMMENT ON COLUMN sleep_goals.preferred_wind_down_types IS 'Array of preferred activity types for wind-down routines';
COMMENT ON COLUMN wind_down_sessions.routine IS 'JSON array of wind-down activities with completion status';
COMMENT ON COLUMN sleep_insights.insight_data IS 'JSON insight details: {title, message, metric, value, trend, recommendation}';
