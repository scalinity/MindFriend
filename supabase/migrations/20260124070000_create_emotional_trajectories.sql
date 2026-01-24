-- Intervention Efficacy Engine: Emotional Trajectories Table
-- Stores time-series emotional state snapshots during exercise sessions

CREATE TABLE IF NOT EXISTS emotional_trajectories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES exercise_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    samples JSONB NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_trajectories_user_session ON emotional_trajectories(user_id, session_id);
CREATE INDEX IF NOT EXISTS idx_trajectories_exercise ON emotional_trajectories(exercise_id);
CREATE INDEX IF NOT EXISTS idx_trajectories_created_at ON emotional_trajectories(created_at DESC);

-- Enable Row Level Security
ALTER TABLE emotional_trajectories ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'emotional_trajectories'
        AND policyname = 'Users read own trajectories'
    ) THEN
        CREATE POLICY "Users read own trajectories"
        ON emotional_trajectories
        FOR SELECT
        USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'emotional_trajectories'
        AND policyname = 'Users insert own trajectories'
    ) THEN
        CREATE POLICY "Users insert own trajectories"
        ON emotional_trajectories
        FOR INSERT
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Add helpful comment
COMMENT ON TABLE emotional_trajectories IS 'Time-series emotion snapshots during exercise sessions for efficacy tracking';
COMMENT ON COLUMN emotional_trajectories.samples IS 'JSONB array of {timestamp, secondsFromStart, nervousSystemState, emotionClassification, hrvReading, compositeScore}';
