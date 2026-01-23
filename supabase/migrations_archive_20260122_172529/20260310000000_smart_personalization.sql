-- Smart Personalization Migration
-- Spec 10: Adaptive learning and personalized recommendations

-- User preference profile
CREATE TABLE IF NOT EXISTS user_preference_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Explicit preferences (user-set)
    preferred_session_length TEXT DEFAULT 'medium', -- micro, short, medium, long
    preferred_content_types TEXT[] DEFAULT ARRAY['audio', 'visual', 'text'],
    preferred_categories TEXT[] DEFAULT ARRAY[]::TEXT[],
    preferred_voice_gender TEXT, -- male, female, neutral, no_preference
    background_sound_preference TEXT DEFAULT 'nature', -- nature, music, silence, ambient
    difficulty_preference TEXT DEFAULT 'adaptive', -- easy, medium, hard, adaptive

    -- Scheduling preferences
    preferred_times JSONB DEFAULT '{"weekday": [], "weekend": []}',
    quiet_hours_start TIME DEFAULT '22:00',
    quiet_hours_end TIME DEFAULT '07:00',
    reminder_frequency TEXT DEFAULT 'daily', -- none, daily, smart

    -- Feature toggles
    mood_based_recommendations BOOLEAN DEFAULT true,
    personalized_insights BOOLEAN DEFAULT true,
    smart_scheduling BOOLEAN DEFAULT true,
    adaptive_difficulty BOOLEAN DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_user_preferences UNIQUE (user_id)
);

-- Learned preferences (from behavior)
CREATE TABLE IF NOT EXISTS learned_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    preference_type TEXT NOT NULL, -- content_length, content_type, category, time_of_day, etc.
    preference_key TEXT NOT NULL, -- specific value (e.g., "5-10min", "meditation", "morning")

    -- Learning metrics
    engagement_count INTEGER DEFAULT 0,
    completion_count INTEGER DEFAULT 0,
    total_duration_seconds INTEGER DEFAULT 0,
    positive_ratings INTEGER DEFAULT 0,
    negative_ratings INTEGER DEFAULT 0,

    -- Calculated scores
    engagement_rate DECIMAL(5,4) DEFAULT 0, -- completions / engagements
    preference_score DECIMAL(5,4) DEFAULT 0.5, -- 0-1 preference strength
    confidence_score DECIMAL(5,4) DEFAULT 0, -- 0-1 confidence in preference

    -- Temporal tracking
    first_interaction_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_interaction_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_learned_preference UNIQUE (user_id, preference_type, preference_key)
);

-- Content engagement tracking
CREATE TABLE IF NOT EXISTS content_engagements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL, -- exercise, audio, quest, micro_moment, etc.
    content_id UUID NOT NULL,

    -- Engagement details
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    completion_percentage DECIMAL(5,2) DEFAULT 0,
    completed BOOLEAN DEFAULT false,

    -- Context
    mood_before TEXT,
    mood_after TEXT,
    time_of_day TEXT NOT NULL, -- morning, afternoon, evening, night
    day_of_week INTEGER NOT NULL, -- 0-6

    -- Feedback
    rating INTEGER, -- 1-5
    skipped BOOLEAN DEFAULT false,
    skip_reason TEXT,

    -- Content attributes (denormalized for analysis)
    content_category TEXT,
    content_length_minutes INTEGER,
    content_difficulty TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Usage patterns
CREATE TABLE IF NOT EXISTS usage_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    pattern_type TEXT NOT NULL, -- daily_time, weekly_day, session_length, category_preference

    -- Pattern data
    pattern_data JSONB NOT NULL, -- Varies by type

    -- Statistics
    sample_size INTEGER DEFAULT 0,
    confidence DECIMAL(5,4) DEFAULT 0,

    -- Validity
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_usage_pattern UNIQUE (user_id, pattern_type)
);

-- Recommendations log
CREATE TABLE IF NOT EXISTS recommendation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Recommendation details
    recommendation_type TEXT NOT NULL, -- for_you, category, mood_based, time_based
    content_type TEXT NOT NULL,
    content_id UUID NOT NULL,
    position INTEGER NOT NULL, -- Position in list

    -- Scoring
    relevance_score DECIMAL(5,4) NOT NULL,
    personalization_factors JSONB DEFAULT '{}', -- Which factors influenced score

    -- Outcome
    was_viewed BOOLEAN DEFAULT false,
    was_clicked BOOLEAN DEFAULT false,
    was_completed BOOLEAN DEFAULT false,
    time_to_click_seconds INTEGER,

    -- Context
    current_mood TEXT,
    time_of_day TEXT,
    recommendation_context JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Personalized insights
CREATE TABLE IF NOT EXISTS personalized_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Insight details
    insight_type TEXT NOT NULL, -- pattern, milestone, suggestion, trend
    insight_category TEXT NOT NULL, -- mood, activity, progress, habit
    title TEXT NOT NULL,
    description TEXT NOT NULL,

    -- Data backing the insight
    data_points JSONB NOT NULL,
    confidence DECIMAL(5,4) NOT NULL,

    -- Actionability
    action_type TEXT, -- try_content, adjust_schedule, set_goal, celebrate
    action_data JSONB, -- Context for the action

    -- Status
    was_shown BOOLEAN DEFAULT false,
    was_dismissed BOOLEAN DEFAULT false,
    was_acted_upon BOOLEAN DEFAULT false,

    -- Validity
    valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Smart schedule suggestions
CREATE TABLE IF NOT EXISTS schedule_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Suggestion details
    suggested_time TIME NOT NULL,
    suggested_days INTEGER[] NOT NULL, -- Array of day numbers (0-6)
    activity_type TEXT NOT NULL, -- meditation, check_in, exercise, etc.

    -- Scoring
    confidence_score DECIMAL(5,4) NOT NULL,
    based_on_sessions INTEGER NOT NULL, -- Number of sessions analyzed

    -- Reasoning
    reasoning TEXT NOT NULL,
    supporting_data JSONB DEFAULT '{}',

    -- Status
    status TEXT DEFAULT 'suggested', -- suggested, accepted, rejected, expired
    user_response_at TIMESTAMPTZ,

    -- Validity
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days'
);

-- Preference experiments (A/B testing personalization)
CREATE TABLE IF NOT EXISTS preference_experiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    experiment_type TEXT NOT NULL, -- time_slot, content_type, difficulty
    experiment_variant TEXT NOT NULL,

    -- Results
    sessions_in_experiment INTEGER DEFAULT 0,
    success_metric DECIMAL(5,4), -- Completion rate, engagement, etc.

    -- Status
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    outcome TEXT, -- winner, loser, inconclusive

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_learned_preferences_user ON learned_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_learned_preferences_type ON learned_preferences(preference_type);
CREATE INDEX IF NOT EXISTS idx_content_engagements_user ON content_engagements(user_id);
CREATE INDEX IF NOT EXISTS idx_content_engagements_content ON content_engagements(content_type, content_id);
CREATE INDEX IF NOT EXISTS idx_content_engagements_time ON content_engagements(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_patterns_user ON usage_patterns(user_id);
CREATE INDEX IF NOT EXISTS idx_recommendation_logs_user ON recommendation_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_personalized_insights_user ON personalized_insights(user_id, was_shown, valid_until);
CREATE INDEX IF NOT EXISTS idx_schedule_suggestions_user ON schedule_suggestions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_preference_experiments_user ON preference_experiments(user_id);

-- RLS Policies
ALTER TABLE user_preference_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE learned_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_engagements ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE recommendation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE personalized_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE preference_experiments ENABLE ROW LEVEL SECURITY;

-- Users can manage their own preference profile
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own preference profile' AND tablename = 'user_preference_profiles') THEN
        CREATE POLICY "Users manage own preference profile"
            ON user_preference_profiles FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can view their own learned preferences
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own learned preferences' AND tablename = 'learned_preferences') THEN
        CREATE POLICY "Users view own learned preferences"
            ON learned_preferences FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can view own engagements
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own engagements' AND tablename = 'content_engagements') THEN
        CREATE POLICY "Users view own engagements"
            ON content_engagements FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can insert own engagements
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users insert own engagements' AND tablename = 'content_engagements') THEN
        CREATE POLICY "Users insert own engagements"
            ON content_engagements FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Users can view own patterns
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own patterns' AND tablename = 'usage_patterns') THEN
        CREATE POLICY "Users view own patterns"
            ON usage_patterns FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can view own recommendations
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own recommendations' AND tablename = 'recommendation_logs') THEN
        CREATE POLICY "Users view own recommendations"
            ON recommendation_logs FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can manage own insights
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own insights' AND tablename = 'personalized_insights') THEN
        CREATE POLICY "Users manage own insights"
            ON personalized_insights FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can manage schedule suggestions
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage schedule suggestions' AND tablename = 'schedule_suggestions') THEN
        CREATE POLICY "Users manage schedule suggestions"
            ON schedule_suggestions FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can manage preference experiments
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage preference experiments' AND tablename = 'preference_experiments') THEN
        CREATE POLICY "Users manage preference experiments"
            ON preference_experiments FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Trigger to update timestamps
CREATE OR REPLACE FUNCTION update_preference_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers (drop first to avoid duplicates)
DROP TRIGGER IF EXISTS trigger_update_preference_profile_timestamp ON user_preference_profiles;
CREATE TRIGGER trigger_update_preference_profile_timestamp
    BEFORE UPDATE ON user_preference_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_preference_updated_at();

DROP TRIGGER IF EXISTS trigger_update_learned_preference_timestamp ON learned_preferences;
CREATE TRIGGER trigger_update_learned_preference_timestamp
    BEFORE UPDATE ON learned_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_preference_updated_at();

DROP TRIGGER IF EXISTS trigger_update_usage_pattern_timestamp ON usage_patterns;
CREATE TRIGGER trigger_update_usage_pattern_timestamp
    BEFORE UPDATE ON usage_patterns
    FOR EACH ROW
    EXECUTE FUNCTION update_preference_updated_at();
