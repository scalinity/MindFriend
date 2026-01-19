-- Predictive Intervention System
-- ML-powered system that predicts mental health dips and proactively intervenes
-- Privacy-first: predictions_enabled defaults to FALSE (opt-in required)

-- ============================================================================
-- PREDICTION SETTINGS (User opt-in and preferences)
-- ============================================================================

CREATE TABLE IF NOT EXISTS prediction_settings (
    user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,

    -- CRITICAL: Default FALSE for privacy - user must explicitly opt-in
    predictions_enabled BOOLEAN NOT NULL DEFAULT false,

    -- Data sources user allows (all default TRUE once opted in)
    use_mood_data BOOLEAN NOT NULL DEFAULT true,
    use_chat_sentiment BOOLEAN NOT NULL DEFAULT true,
    use_biometrics BOOLEAN NOT NULL DEFAULT true,
    use_app_usage BOOLEAN NOT NULL DEFAULT true,
    use_sleep_data BOOLEAN NOT NULL DEFAULT true,

    -- Intervention preferences
    allow_gentle_nudges BOOLEAN NOT NULL DEFAULT true,
    allow_active_checkins BOOLEAN NOT NULL DEFAULT true,
    preferred_intervention_time TIME, -- Optimal time of day for interventions

    -- Family alerts (for child accounts with parent oversight)
    allow_family_alerts BOOLEAN NOT NULL DEFAULT false,
    family_alert_threshold TEXT NOT NULL DEFAULT 'high' CHECK (family_alert_threshold IN ('high', 'crisis')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- DAILY SIGNALS (Aggregated signals computed daily)
-- Uses FK to biometric_daily_summaries for biometric data (no duplication)
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    signal_date DATE NOT NULL,

    -- FK to existing biometric data (JOIN pattern, no duplication)
    biometric_summary_id UUID REFERENCES biometric_daily_summaries(id),

    -- Mood signals (computed from moods table)
    mood_average DECIMAL(3,1), -- 1-10 scale
    mood_min INTEGER CHECK (mood_min BETWEEN 1 AND 10),
    mood_max INTEGER CHECK (mood_max BETWEEN 1 AND 10),
    mood_variance DECIMAL(4,2),
    mood_trend DECIMAL(4,2), -- Slope of recent moods (negative = declining)
    mood_entry_count INTEGER NOT NULL DEFAULT 0,

    -- Engagement signals (computed from app usage)
    app_sessions INTEGER NOT NULL DEFAULT 0,
    total_active_minutes INTEGER NOT NULL DEFAULT 0,
    features_used TEXT[] NOT NULL DEFAULT '{}',
    quests_completed INTEGER NOT NULL DEFAULT 0,
    exercises_completed INTEGER NOT NULL DEFAULT 0,
    chat_messages_sent INTEGER NOT NULL DEFAULT 0,

    -- Social signals (computed from circles)
    circle_posts INTEGER NOT NULL DEFAULT 0,
    circle_reactions_received INTEGER NOT NULL DEFAULT 0,
    circle_comments_made INTEGER NOT NULL DEFAULT 0,

    -- Computed composite scores (0-100)
    engagement_score INTEGER CHECK (engagement_score BETWEEN 0 AND 100),
    social_score INTEGER CHECK (social_score BETWEEN 0 AND 100),
    biometric_score INTEGER CHECK (biometric_score BETWEEN 0 AND 100),

    -- Streak status
    current_streak INTEGER NOT NULL DEFAULT 0,
    streak_broken_today BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_daily_signal UNIQUE (user_id, signal_date)
);

-- ============================================================================
-- RISK ASSESSMENTS (Risk scores history)
-- ============================================================================

CREATE TABLE IF NOT EXISTS risk_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Risk score and level
    risk_score INTEGER NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high', 'crisis')),

    -- Contributing factors (JSON for flexibility and explainability)
    factors JSONB NOT NULL DEFAULT '{}',
    -- Example: {
    --   "mood_trend": -15.5,
    --   "mood_volatility": 8.2,
    --   "app_engagement": -3.0,
    --   "sleep_quality": -2.5,
    --   "hrv_drop": -5.1,
    --   "streak_broken": true,
    --   "days_since_chat": 4,
    --   "social_engagement": -2.0
    -- }

    -- Top contributing factors (human-readable)
    top_factors TEXT[] NOT NULL DEFAULT '{}',

    -- Predictions
    predicted_mood_24h DECIMAL(3,1) CHECK (predicted_mood_24h BETWEEN 1 AND 10),
    predicted_trend_7d TEXT CHECK (predicted_trend_7d IN ('improving', 'stable', 'declining')),

    -- Model metadata
    model_version TEXT NOT NULL DEFAULT 'v1.0.0',
    confidence DECIMAL(3,2) CHECK (confidence BETWEEN 0 AND 1),

    -- Reference to signals used for assessment
    daily_signal_id UUID REFERENCES daily_signals(id),

    -- Trigger intervention if needed
    intervention_triggered BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INTERVENTIONS (Intervention history and tracking)
-- Coordinates with proactive_messages for 24h deduplication
-- ============================================================================

CREATE TABLE IF NOT EXISTS interventions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    risk_assessment_id UUID REFERENCES risk_assessments(id),

    -- Intervention type and channel
    intervention_type TEXT NOT NULL CHECK (intervention_type IN ('gentle_nudge', 'active_checkin', 'crisis_protocol', 'family_alert')),
    channel TEXT NOT NULL CHECK (channel IN ('push', 'in_app', 'sms', 'email')),

    -- Content
    message_template TEXT NOT NULL,
    personalization JSONB, -- Dynamic elements inserted into template

    -- Suggested actions
    suggested_actions TEXT[] NOT NULL DEFAULT '{}', -- ['breathing_exercise', 'chat', 'call_friend', 'crisis_line']
    suggested_exercise_id UUID REFERENCES exercises(id),

    -- Timing
    scheduled_at TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ, -- Intervention expires if not responded to

    -- Response tracking
    response TEXT CHECK (response IN ('accepted', 'dismissed', 'ignored', 'pending')),
    responded_at TIMESTAMPTZ,
    action_taken TEXT, -- 'started_chat', 'did_exercise', 'called_friend', etc.

    -- Outcome tracking for model improvement
    mood_before INTEGER CHECK (mood_before BETWEEN 1 AND 10),
    mood_24h_after INTEGER CHECK (mood_24h_after BETWEEN 1 AND 10),
    helpful_rating INTEGER CHECK (helpful_rating BETWEEN 1 AND 5),
    user_feedback TEXT,

    -- Deduplication: reference to proactive_messages if one was created
    proactive_message_id UUID REFERENCES proactive_messages(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Daily signals: user + date lookup (most common query)
CREATE INDEX IF NOT EXISTS idx_daily_signals_user_date
    ON daily_signals(user_id, signal_date DESC);

-- Risk assessments: user + time for history, level for filtering
CREATE INDEX IF NOT EXISTS idx_risk_assessments_user_time
    ON risk_assessments(user_id, assessed_at DESC);
CREATE INDEX IF NOT EXISTS idx_risk_assessments_level
    ON risk_assessments(user_id, risk_level) WHERE risk_level IN ('high', 'crisis');

-- Interventions: user + time, pending responses
CREATE INDEX IF NOT EXISTS idx_interventions_user_time
    ON interventions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_interventions_pending
    ON interventions(user_id) WHERE response = 'pending';
CREATE INDEX IF NOT EXISTS idx_interventions_scheduled
    ON interventions(scheduled_at) WHERE delivered_at IS NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE prediction_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE interventions ENABLE ROW LEVEL SECURITY;

-- Prediction settings: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own prediction settings') THEN
        CREATE POLICY "Users manage own prediction settings"
            ON prediction_settings FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Daily signals: users can read their own, service role inserts
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own daily signals') THEN
        CREATE POLICY "Users read own daily signals"
            ON daily_signals FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages daily signals') THEN
        CREATE POLICY "Service role manages daily signals"
            ON daily_signals FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- Risk assessments: users can read their own, service role inserts
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own risk assessments') THEN
        CREATE POLICY "Users read own risk assessments"
            ON risk_assessments FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages risk assessments') THEN
        CREATE POLICY "Service role manages risk assessments"
            ON risk_assessments FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- Interventions: users can read and update (for response), service role full access
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own interventions') THEN
        CREATE POLICY "Users read own interventions"
            ON interventions FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users update own intervention responses') THEN
        CREATE POLICY "Users update own intervention responses"
            ON interventions FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages interventions') THEN
        CREATE POLICY "Service role manages interventions"
            ON interventions FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- ============================================================================
-- FUNCTIONS FOR SIGNAL AGGREGATION
-- ============================================================================

-- Function to aggregate daily signals for a user
CREATE OR REPLACE FUNCTION aggregate_daily_signals(
    p_user_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_signal_id UUID;
    v_mood_stats RECORD;
    v_engagement_stats RECORD;
    v_social_stats RECORD;
    v_biometric_id UUID;
    v_streak INTEGER;
    v_streak_broken BOOLEAN;
    v_mood_trend DECIMAL(4,2);
BEGIN
    -- Calculate mood statistics for the day
    SELECT
        AVG(mood_score)::DECIMAL(3,1) as avg_mood,
        MIN(mood_score) as min_mood,
        MAX(mood_score) as max_mood,
        VARIANCE(mood_score)::DECIMAL(4,2) as variance,
        COUNT(*) as count
    INTO v_mood_stats
    FROM moods
    WHERE user_id = p_user_id
    AND DATE(created_at) = p_date;

    -- Calculate mood trend (linear regression slope over last 7 days)
    -- Negative slope = declining mood, positive = improving
    WITH recent_moods AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY created_at) - 1 as x,
            mood_score as y
        FROM moods
        WHERE user_id = p_user_id
        AND created_at >= p_date - INTERVAL '7 days'
        AND created_at < p_date + INTERVAL '1 day'
    ),
    regression AS (
        SELECT
            COUNT(*) as n,
            SUM(x) as sum_x,
            SUM(y) as sum_y,
            SUM(x * y) as sum_xy,
            SUM(x * x) as sum_x2
        FROM recent_moods
    )
    SELECT
        CASE
            WHEN n >= 3 AND (n * sum_x2 - sum_x * sum_x) != 0 THEN
                ((n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x))::DECIMAL(4,2)
            ELSE NULL
        END INTO v_mood_trend
    FROM regression;

    -- Calculate engagement statistics
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE completed_at IS NOT NULL), 0) as quests_completed,
        COALESCE((SELECT COUNT(*) FROM exercise_sessions es WHERE es.user_id = p_user_id AND DATE(es.created_at) = p_date), 0) as exercises_completed,
        COALESCE((SELECT COUNT(*) FROM messages m WHERE m.user_id = p_user_id AND DATE(m.created_at) = p_date AND m.role = 'user'), 0) as chat_messages
    INTO v_engagement_stats
    FROM quests
    WHERE user_id = p_user_id
    AND DATE(created_at) = p_date;

    -- Calculate social statistics
    SELECT
        COALESCE(COUNT(*), 0) as posts,
        COALESCE((SELECT COUNT(*) FROM circle_reactions cr
                  JOIN circle_posts cp ON cr.post_id = cp.id
                  WHERE cp.user_id = p_user_id AND DATE(cr.created_at) = p_date), 0) as reactions_received
    INTO v_social_stats
    FROM circle_posts
    WHERE user_id = p_user_id
    AND DATE(created_at) = p_date;

    -- Get biometric summary ID if exists
    SELECT id INTO v_biometric_id
    FROM biometric_daily_summaries
    WHERE user_id = p_user_id AND date = p_date;

    -- Get current streak
    SELECT current_streak INTO v_streak
    FROM profiles
    WHERE id = p_user_id;

    -- Check if streak was broken today (simplified check)
    v_streak_broken := (v_streak = 0 AND EXISTS (
        SELECT 1 FROM profiles WHERE id = p_user_id AND updated_at::DATE = p_date
    ));

    -- Upsert daily signals
    INSERT INTO daily_signals (
        user_id,
        signal_date,
        biometric_summary_id,
        mood_average,
        mood_min,
        mood_max,
        mood_variance,
        mood_trend,
        mood_entry_count,
        quests_completed,
        exercises_completed,
        chat_messages_sent,
        circle_posts,
        circle_reactions_received,
        current_streak,
        streak_broken_today,
        -- Compute composite scores
        engagement_score,
        social_score
    ) VALUES (
        p_user_id,
        p_date,
        v_biometric_id,
        v_mood_stats.avg_mood,
        v_mood_stats.min_mood,
        v_mood_stats.max_mood,
        v_mood_stats.variance,
        v_mood_trend,
        COALESCE(v_mood_stats.count, 0),
        v_engagement_stats.quests_completed,
        v_engagement_stats.exercises_completed,
        v_engagement_stats.chat_messages,
        v_social_stats.posts,
        v_social_stats.reactions_received,
        COALESCE(v_streak, 0),
        v_streak_broken,
        -- Engagement score: 0-100 based on activity
        LEAST(100, (
            v_engagement_stats.quests_completed * 20 +
            v_engagement_stats.exercises_completed * 15 +
            v_engagement_stats.chat_messages * 5
        )),
        -- Social score: 0-100 based on circle activity
        LEAST(100, (
            v_social_stats.posts * 25 +
            v_social_stats.reactions_received * 10
        ))
    )
    ON CONFLICT (user_id, signal_date) DO UPDATE SET
        biometric_summary_id = EXCLUDED.biometric_summary_id,
        mood_average = EXCLUDED.mood_average,
        mood_min = EXCLUDED.mood_min,
        mood_max = EXCLUDED.mood_max,
        mood_variance = EXCLUDED.mood_variance,
        mood_trend = EXCLUDED.mood_trend,
        mood_entry_count = EXCLUDED.mood_entry_count,
        quests_completed = EXCLUDED.quests_completed,
        exercises_completed = EXCLUDED.exercises_completed,
        chat_messages_sent = EXCLUDED.chat_messages_sent,
        circle_posts = EXCLUDED.circle_posts,
        circle_reactions_received = EXCLUDED.circle_reactions_received,
        current_streak = EXCLUDED.current_streak,
        streak_broken_today = EXCLUDED.streak_broken_today,
        engagement_score = EXCLUDED.engagement_score,
        social_score = EXCLUDED.social_score,
        updated_at = NOW()
    RETURNING id INTO v_signal_id;

    RETURN v_signal_id;
END;
$$;

-- ============================================================================
-- TRIGGER: Auto-create crisis_event when risk_level = 'crisis'
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_crisis_risk_assessment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- If risk level is crisis, also create a crisis_event for audit trail
    IF NEW.risk_level = 'crisis' THEN
        INSERT INTO crisis_events (
            user_id,
            trigger_type,
            trigger_content,
            intervention_type,
            response_shown
        ) VALUES (
            NEW.user_id,
            'predictive_risk',
            'Risk assessment score: ' || NEW.risk_score || '. Top factors: ' || array_to_string(NEW.top_factors, ', '),
            'crisis_protocol',
            'Proactive crisis resources shown'
        );
    END IF;

    RETURN NEW;
END;
$$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_crisis_risk_assessment') THEN
        CREATE TRIGGER trigger_crisis_risk_assessment
            AFTER INSERT ON risk_assessments
            FOR EACH ROW
            EXECUTE FUNCTION handle_crisis_risk_assessment();
    END IF;
END $$;

-- ============================================================================
-- TRIGGER: Update prediction_settings.updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION update_prediction_settings_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_prediction_settings_updated') THEN
        CREATE TRIGGER trigger_prediction_settings_updated
            BEFORE UPDATE ON prediction_settings
            FOR EACH ROW
            EXECUTE FUNCTION update_prediction_settings_timestamp();
    END IF;
END $$;

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE prediction_settings IS 'User opt-in settings for predictive intervention feature. predictions_enabled defaults to FALSE for privacy.';
COMMENT ON TABLE daily_signals IS 'Aggregated daily signals for risk scoring. Uses FK to biometric_daily_summaries to avoid data duplication.';
COMMENT ON TABLE risk_assessments IS 'Historical risk assessments with scores, levels, and contributing factors.';
COMMENT ON TABLE interventions IS 'Intervention history with response tracking and outcome measurement.';

COMMENT ON COLUMN prediction_settings.predictions_enabled IS 'User must explicitly opt-in. Defaults to FALSE for privacy.';
COMMENT ON COLUMN daily_signals.biometric_summary_id IS 'FK to biometric_daily_summaries - JOIN pattern instead of duplicating biometric fields.';
COMMENT ON COLUMN risk_assessments.factors IS 'JSONB containing all contributing factors with their values for explainability.';
COMMENT ON COLUMN risk_assessments.top_factors IS 'Human-readable list of top contributing factors for UI display.';
COMMENT ON COLUMN interventions.proactive_message_id IS 'Reference to proactive_messages for 24h deduplication coordination.';
