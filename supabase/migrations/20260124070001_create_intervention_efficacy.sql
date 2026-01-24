-- Intervention Efficacy Engine: Intervention Efficacy Table
-- Stores calculated efficacy scores per session

CREATE TABLE IF NOT EXISTS intervention_efficacy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    session_id UUID NOT NULL,
    completed_at TIMESTAMPTZ NOT NULL,

    -- Core metrics
    efficacy_score DECIMAL(5,2) NOT NULL CHECK (efficacy_score >= 0 AND efficacy_score <= 100),
    net_emotional_change DECIMAL(4,3) NOT NULL CHECK (net_emotional_change >= -1 AND net_emotional_change <= 1),
    trajectory_shape TEXT NOT NULL,
    breakthrough_detected BOOLEAN DEFAULT FALSE,
    breakthrough_second INTEGER,

    -- Context
    starting_state JSONB NOT NULL,
    time_of_day TEXT NOT NULL,
    day_of_week INTEGER NOT NULL CHECK (day_of_week >= 1 AND day_of_week <= 7),
    prior_sleep_quality DECIMAL(3,2),
    stress_level DECIMAL(3,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_trajectory_shape CHECK (
        trajectory_shape IN ('steadyImprovement', 'lateBreakthrough', 'earlyPeak', 'deterioration', 'flat')
    ),
    CONSTRAINT valid_time_of_day CHECK (
        time_of_day IN ('morning', 'afternoon', 'evening', 'night')
    )
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_efficacy_user_exercise ON intervention_efficacy(user_id, exercise_id);
CREATE INDEX IF NOT EXISTS idx_efficacy_user_created ON intervention_efficacy(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_efficacy_breakthroughs ON intervention_efficacy(user_id) WHERE breakthrough_detected = TRUE;
CREATE INDEX IF NOT EXISTS idx_efficacy_session ON intervention_efficacy(session_id);

-- Enable Row Level Security
ALTER TABLE intervention_efficacy ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'intervention_efficacy'
        AND policyname = 'Users read own efficacy'
    ) THEN
        CREATE POLICY "Users read own efficacy"
        ON intervention_efficacy
        FOR SELECT
        USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'intervention_efficacy'
        AND policyname = 'Users insert own efficacy'
    ) THEN
        CREATE POLICY "Users insert own efficacy"
        ON intervention_efficacy
        FOR INSERT
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Add helpful comments
COMMENT ON TABLE intervention_efficacy IS 'Calculated efficacy scores for each completed exercise session';
COMMENT ON COLUMN intervention_efficacy.efficacy_score IS '0-100 metric representing intervention effectiveness';
COMMENT ON COLUMN intervention_efficacy.net_emotional_change IS 'Delta from start to end state, range -1 to +1';
COMMENT ON COLUMN intervention_efficacy.breakthrough_detected IS 'Rapid positive shift of > 0.4 within 60 seconds';
COMMENT ON COLUMN intervention_efficacy.starting_state IS 'JSONB: {nervousSystemState, primaryEmotion, stressLevel}';
