-- Intervention Efficacy Engine: User Efficacy Profiles Table
-- Aggregated efficacy statistics per user-exercise pair (updated nightly)

CREATE TABLE IF NOT EXISTS user_efficacy_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),

    -- Aggregated metrics
    overall_efficacy_score DECIMAL(5,2) NOT NULL CHECK (overall_efficacy_score >= 0 AND overall_efficacy_score <= 100),
    completion_count INTEGER NOT NULL CHECK (completion_count >= 0),
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),

    -- Contextual efficacy breakdowns (JSONB maps)
    efficacy_by_state JSONB NOT NULL DEFAULT '{}',
    efficacy_by_time_of_day JSONB NOT NULL DEFAULT '{}',
    efficacy_by_emotion JSONB NOT NULL DEFAULT '{}',

    -- Insights
    best_context TEXT,
    trend TEXT NOT NULL DEFAULT 'stable' CHECK (trend IN ('improving', 'stable', 'declining')),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_user_exercise UNIQUE(user_id, exercise_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_profiles_user ON user_efficacy_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_user_updated ON user_efficacy_profiles(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_efficacy_desc ON user_efficacy_profiles(user_id, overall_efficacy_score DESC);

-- Enable Row Level Security
ALTER TABLE user_efficacy_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Note: This table is maintained by the aggregate-efficacy-profiles cron job using service role.
-- Users can only read their own profiles. INSERT/UPDATE/DELETE are blocked for regular users.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_efficacy_profiles'
        AND policyname = 'Users read own profiles'
    ) THEN
        CREATE POLICY "Users read own profiles"
        ON user_efficacy_profiles
        FOR SELECT
        USING (auth.uid() = user_id);
    END IF;

    -- Service role can INSERT/UPDATE profiles (cron job)
    -- Regular users cannot INSERT/UPDATE/DELETE (denied by default when no policy exists)
    -- These policies are intentionally omitted to enforce service-role-only modification
END $$;

-- Add helpful comments
COMMENT ON TABLE user_efficacy_profiles IS 'Aggregated efficacy profiles per user-exercise pair, updated by nightly cron job';
COMMENT ON COLUMN user_efficacy_profiles.overall_efficacy_score IS 'Weighted average efficacy (recent sessions weighted higher)';
COMMENT ON COLUMN user_efficacy_profiles.confidence IS 'Statistical confidence (0-1), calculated as min(1.0, completionCount / 20)';
COMMENT ON COLUMN user_efficacy_profiles.efficacy_by_state IS 'JSONB map: {nervousSystemState: avgEfficacy}';
COMMENT ON COLUMN user_efficacy_profiles.efficacy_by_time_of_day IS 'JSONB map: {timeOfDay: avgEfficacy}';
COMMENT ON COLUMN user_efficacy_profiles.efficacy_by_emotion IS 'JSONB map: {emotion: avgEfficacy}';
COMMENT ON COLUMN user_efficacy_profiles.trend IS 'Efficacy trend over time: improving, stable, or declining';
