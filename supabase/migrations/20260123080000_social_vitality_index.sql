-- Social Vitality Index (N004) Migration
-- Created: 2026-01-23
-- Purpose: Implement social health scoring, withdrawal detection, and peer support system

-- ============================================================================
-- TABLE: social_vitality_scores
-- Purpose: Daily social vitality scores (0-100) with 4 components
-- ============================================================================

CREATE TABLE IF NOT EXISTS social_vitality_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    overall_score INTEGER NOT NULL CHECK (overall_score >= 0 AND overall_score <= 100),
    trend TEXT NOT NULL CHECK (trend IN ('improving', 'stable', 'declining', 'plummeting')),
    interaction_frequency INTEGER NOT NULL CHECK (interaction_frequency >= 0 AND interaction_frequency <= 25),
    interaction_depth INTEGER NOT NULL CHECK (interaction_depth >= 0 AND interaction_depth <= 25),
    reciprocity INTEGER NOT NULL CHECK (reciprocity >= 0 AND reciprocity <= 25),
    diversity INTEGER NOT NULL CHECK (diversity >= 0 AND diversity <= 25),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_social_vitality_user_date ON social_vitality_scores(user_id, date DESC);

COMMENT ON TABLE social_vitality_scores IS 'Daily social vitality scores calculated from circle interaction patterns';
COMMENT ON COLUMN social_vitality_scores.overall_score IS 'Overall social health score (0-100), sum of 4 components';
COMMENT ON COLUMN social_vitality_scores.trend IS 'Score trend: improving (+10 over 7 days), stable (-10 to +10), declining (-10 to -25), plummeting (-25+)';
COMMENT ON COLUMN social_vitality_scores.interaction_frequency IS 'Message count component (0-25 points)';
COMMENT ON COLUMN social_vitality_scores.interaction_depth IS 'Message quality component: length + response time (0-25 points)';
COMMENT ON COLUMN social_vitality_scores.reciprocity IS 'Give/receive balance component (0-25 points)';
COMMENT ON COLUMN social_vitality_scores.diversity IS 'Unique people + circles component (0-25 points)';

-- ============================================================================
-- TABLE: interaction_metrics
-- Purpose: Daily interaction data per user pair per circle (aggregated)
-- ============================================================================

CREATE TABLE IF NOT EXISTS interaction_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    other_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    messages_sent INTEGER DEFAULT 0 CHECK (messages_sent >= 0),
    messages_received INTEGER DEFAULT 0 CHECK (messages_received >= 0),
    avg_response_time_minutes DECIMAL(10,2) CHECK (avg_response_time_minutes >= 0),
    avg_message_length INTEGER CHECK (avg_message_length >= 0),
    reciprocity_ratio DECIMAL(4,3) CHECK (reciprocity_ratio >= 0),
    engagement_score DECIMAL(4,3) CHECK (engagement_score >= 0 AND engagement_score <= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, other_user_id, circle_id, date),
    CHECK (user_id != other_user_id)  -- Prevent self-interactions
);

CREATE INDEX IF NOT EXISTS idx_interaction_metrics_user_date ON interaction_metrics(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_interaction_metrics_other_user ON interaction_metrics(other_user_id);

COMMENT ON TABLE interaction_metrics IS 'Daily interaction metrics per user pair (messages, response time, length, balance)';
COMMENT ON COLUMN interaction_metrics.avg_response_time_minutes IS 'Average time to respond (reply timestamp - post timestamp)';
COMMENT ON COLUMN interaction_metrics.reciprocity_ratio IS 'sent / max(received, 1) - balance ratio';
COMMENT ON COLUMN interaction_metrics.engagement_score IS 'Composite depth score: 0.4*length + 0.6*response_time (0-1)';

-- ============================================================================
-- TABLE: relationship_correlations
-- Purpose: Pearson correlation between interactions with person and next-day mood
-- ============================================================================

CREATE TABLE IF NOT EXISTS relationship_correlations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    other_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    mood_correlation DECIMAL(4,3) NOT NULL CHECK (mood_correlation >= -1 AND mood_correlation <= 1),
    interaction_count INTEGER NOT NULL CHECK (interaction_count >= 0),
    confidence_level DECIMAL(4,3) NOT NULL CHECK (confidence_level >= 0 AND confidence_level <= 1),
    classification TEXT NOT NULL CHECK (classification IN ('support_pillar', 'neutral', 'draining')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, other_user_id),
    CHECK (user_id != other_user_id),
    CHECK (
        (classification = 'neutral') OR
        (interaction_count >= 10 AND confidence_level >= 0.8) OR
        (classification = 'draining' AND interaction_count >= 15 AND confidence_level >= 0.9)
    )  -- Enforce minimum data for classification
);

CREATE INDEX IF NOT EXISTS idx_relationship_correlations_user ON relationship_correlations(user_id);
CREATE INDEX IF NOT EXISTS idx_relationship_correlations_classification ON relationship_correlations(user_id, classification);

COMMENT ON TABLE relationship_correlations IS 'Mood correlation analysis for each relationship (support pillars vs draining)';
COMMENT ON COLUMN relationship_correlations.mood_correlation IS 'Pearson r between interaction count and next-day mood (-1 to +1)';
COMMENT ON COLUMN relationship_correlations.confidence_level IS 'Statistical confidence (1 - p_value from t-test)';
COMMENT ON COLUMN relationship_correlations.classification IS 'support_pillar (r>0.3), neutral (-0.3 to 0.3), draining (r<-0.3)';

-- ============================================================================
-- TABLE: peer_support_consent
-- Purpose: Supporters must explicitly accept before receiving alerts
-- ============================================================================

CREATE TABLE IF NOT EXISTS peer_support_consent (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    requesting_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    accepted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(supporter_id, requesting_user_id),
    CHECK (supporter_id != requesting_user_id)
);

CREATE INDEX IF NOT EXISTS idx_peer_support_consent_supporter ON peer_support_consent(supporter_id);
CREATE INDEX IF NOT EXISTS idx_peer_support_consent_requesting_user ON peer_support_consent(requesting_user_id);

COMMENT ON TABLE peer_support_consent IS 'Explicit consent from supporters before receiving withdrawal alerts';
COMMENT ON COLUMN peer_support_consent.accepted IS 'TRUE if supporter has consented to receive alerts from requesting user';

-- ============================================================================
-- TABLE: peer_alert_preferences
-- Purpose: User preferences for opt-in peer notification system
-- ============================================================================

CREATE TABLE IF NOT EXISTS peer_alert_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    enabled BOOLEAN DEFAULT FALSE,
    alert_threshold TEXT DEFAULT 'severe' CHECK (alert_threshold IN ('moderate', 'severe')),
    designated_supporters UUID[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (array_length(designated_supporters, 1) IS NULL OR array_length(designated_supporters, 1) <= 3)  -- Max 3 supporters
);

CREATE INDEX IF NOT EXISTS idx_peer_alert_preferences_user ON peer_alert_preferences(user_id);

COMMENT ON TABLE peer_alert_preferences IS 'User preferences for peer support alerts (opt-in, threshold, designated supporters)';
COMMENT ON COLUMN peer_alert_preferences.enabled IS 'User has opted in to peer support notifications';
COMMENT ON COLUMN peer_alert_preferences.alert_threshold IS 'minimum withdrawal severity to trigger alert: moderate or severe';
COMMENT ON COLUMN peer_alert_preferences.designated_supporters IS 'Array of up to 3 supporter user IDs (must be in circles)';

-- ============================================================================
-- TABLE: peer_alerts
-- Purpose: Log of peer support alerts sent to supporters
-- ============================================================================

CREATE TABLE IF NOT EXISTS peer_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    supporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL CHECK (alert_type IN ('withdrawal_detected', 'reach_out_reminder')),
    message TEXT NOT NULL,
    acknowledged BOOLEAN DEFAULT FALSE,
    delivery_failed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (user_id != supporter_id)
);

CREATE INDEX IF NOT EXISTS idx_peer_alerts_user_date ON peer_alerts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_peer_alerts_supporter ON peer_alerts(supporter_id, created_at DESC);

COMMENT ON TABLE peer_alerts IS 'Log of all peer support alerts sent (for rate limiting and audit)';
COMMENT ON COLUMN peer_alerts.alert_type IS 'withdrawal_detected (user declining) or reach_out_reminder (follow-up)';
COMMENT ON COLUMN peer_alerts.delivery_failed IS 'TRUE if push notification failed (supporter uninstalled, disabled notifications)';

-- ============================================================================
-- TABLE: withdrawal_detections
-- Purpose: Record of withdrawal pattern detections
-- ============================================================================

CREATE TABLE IF NOT EXISTS withdrawal_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('moderate', 'severe')),
    decline_percent INTEGER NOT NULL CHECK (decline_percent >= 0 AND decline_percent <= 100),
    days_since_peak INTEGER NOT NULL CHECK (days_since_peak >= 0),
    should_alert BOOLEAN NOT NULL,
    alert_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_withdrawal_detections_user_date ON withdrawal_detections(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_withdrawal_detections_pending_alerts ON withdrawal_detections(user_id, should_alert, alert_sent) WHERE should_alert = TRUE AND alert_sent = FALSE;

COMMENT ON TABLE withdrawal_detections IS 'Record of detected social withdrawal patterns (declining score over 7+ days)';
COMMENT ON COLUMN withdrawal_detections.severity IS 'moderate (decline 15-25 points) or severe (decline 25+ points)';
COMMENT ON COLUMN withdrawal_detections.decline_percent IS 'Percentage decline from recent_avg to older_avg';
COMMENT ON COLUMN withdrawal_detections.should_alert IS 'TRUE if withdrawal is severe (should notify supporters)';
COMMENT ON COLUMN withdrawal_detections.alert_sent IS 'TRUE if peer alerts have been sent for this detection';

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

ALTER TABLE social_vitality_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE interaction_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE relationship_correlations ENABLE ROW LEVEL SECURITY;
ALTER TABLE peer_support_consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE peer_alert_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE peer_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawal_detections ENABLE ROW LEVEL SECURITY;

-- social_vitality_scores policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'social_vitality_scores' AND policyname = 'Users can read own social_vitality_scores'
    ) THEN
        CREATE POLICY "Users can read own social_vitality_scores"
            ON social_vitality_scores FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- interaction_metrics policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'interaction_metrics' AND policyname = 'Users can read own interaction_metrics'
    ) THEN
        CREATE POLICY "Users can read own interaction_metrics"
            ON interaction_metrics FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- relationship_correlations policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'relationship_correlations' AND policyname = 'Users can read own relationship_correlations'
    ) THEN
        CREATE POLICY "Users can read own relationship_correlations"
            ON relationship_correlations FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- peer_support_consent policies (supporters can read/update their consent)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_support_consent' AND policyname = 'Supporters can read own peer_support_consent'
    ) THEN
        CREATE POLICY "Supporters can read own peer_support_consent"
            ON peer_support_consent FOR SELECT
            USING (auth.uid() = supporter_id OR auth.uid() = requesting_user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_support_consent' AND policyname = 'Supporters can update own peer_support_consent'
    ) THEN
        CREATE POLICY "Supporters can update own peer_support_consent"
            ON peer_support_consent FOR UPDATE
            USING (auth.uid() = supporter_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_support_consent' AND policyname = 'Users can insert peer_support_consent'
    ) THEN
        CREATE POLICY "Users can insert peer_support_consent"
            ON peer_support_consent FOR INSERT
            WITH CHECK (auth.uid() = requesting_user_id);
    END IF;
END $$;

-- peer_alert_preferences policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_alert_preferences' AND policyname = 'Users can read own peer_alert_preferences'
    ) THEN
        CREATE POLICY "Users can read own peer_alert_preferences"
            ON peer_alert_preferences FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_alert_preferences' AND policyname = 'Users can update own peer_alert_preferences'
    ) THEN
        CREATE POLICY "Users can update own peer_alert_preferences"
            ON peer_alert_preferences FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_alert_preferences' AND policyname = 'Users can insert own peer_alert_preferences'
    ) THEN
        CREATE POLICY "Users can insert own peer_alert_preferences"
            ON peer_alert_preferences FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- peer_alerts policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_alerts' AND policyname = 'Supporters can read peer_alerts sent to them'
    ) THEN
        CREATE POLICY "Supporters can read peer_alerts sent to them"
            ON peer_alerts FOR SELECT
            USING (auth.uid() = supporter_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'peer_alerts' AND policyname = 'Supporters can update peer_alerts acknowledgement'
    ) THEN
        CREATE POLICY "Supporters can update peer_alerts acknowledgement"
            ON peer_alerts FOR UPDATE
            USING (auth.uid() = supporter_id)
            WITH CHECK (auth.uid() = supporter_id);
    END IF;
END $$;

-- withdrawal_detections policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'withdrawal_detections' AND policyname = 'Users can read own withdrawal_detections'
    ) THEN
        CREATE POLICY "Users can read own withdrawal_detections"
            ON withdrawal_detections FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function: Get dashboard data for a user
CREATE OR REPLACE FUNCTION get_social_vitality_dashboard(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    -- SECURITY: Validate that the requesting user can only access their own dashboard
    IF p_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot access another user''s dashboard'
            USING ERRCODE = 'PAUTH';
    END IF;

    WITH current_score AS (
        SELECT
            overall_score,
            trend,
            interaction_frequency,
            interaction_depth,
            reciprocity,
            diversity
        FROM social_vitality_scores
        WHERE user_id = p_user_id
        AND date = CURRENT_DATE
        LIMIT 1
    ),
    weekly_change AS (
        SELECT
            s_today.overall_score - s_week_ago.overall_score AS change
        FROM social_vitality_scores s_today
        LEFT JOIN social_vitality_scores s_week_ago
            ON s_week_ago.user_id = s_today.user_id
            AND s_week_ago.date = CURRENT_DATE - INTERVAL '7 days'
        WHERE s_today.user_id = p_user_id
        AND s_today.date = CURRENT_DATE
    ),
    top_supporters AS (
        SELECT json_agg(
            json_build_object(
                'id', rc.other_user_id,
                'name', COALESCE(p.full_name, p.email),
                'correlation', rc.mood_correlation
            )
            ORDER BY rc.mood_correlation DESC
        ) AS supporters
        FROM relationship_correlations rc
        JOIN profiles p ON p.id = rc.other_user_id
        WHERE rc.user_id = p_user_id
        AND rc.classification = 'support_pillar'
        LIMIT 3
    ),
    alert_status AS (
        SELECT
            COALESCE(enabled, FALSE) AS enabled,
            COALESCE(array_length(designated_supporters, 1), 0) AS supporters_configured
        FROM peer_alert_preferences
        WHERE user_id = p_user_id
    )
    SELECT json_build_object(
        'currentScore', COALESCE(cs.overall_score, 0),
        'trend', COALESCE(cs.trend, 'stable'),
        'components', json_build_object(
            'frequency', COALESCE(cs.interaction_frequency, 0),
            'depth', COALESCE(cs.interaction_depth, 0),
            'reciprocity', COALESCE(cs.reciprocity, 0),
            'diversity', COALESCE(cs.diversity, 0)
        ),
        'weeklyChange', COALESCE(wc.change, 0),
        'topSupporters', COALESCE(ts.supporters, '[]'::json),
        'alertStatus', json_build_object(
            'enabled', COALESCE(ast.enabled, FALSE),
            'supportersConfigured', COALESCE(ast.supporters_configured, 0)
        )
    ) INTO v_result
    FROM current_score cs
    LEFT JOIN weekly_change wc ON TRUE
    LEFT JOIN top_supporters ts ON TRUE
    LEFT JOIN alert_status ast ON TRUE;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_social_vitality_dashboard IS 'Fetch complete dashboard data for a user (current score, trend, components, weekly change, top supporters, alert status)';

-- Function: Get users with sufficient data for withdrawal detection
CREATE OR REPLACE FUNCTION get_users_with_scores(p_min_days INTEGER DEFAULT 14)
RETURNS TABLE (
    user_id UUID,
    days_of_data BIGINT
) AS $$
BEGIN
    -- SECURITY: This function should only be called by Edge Functions (service role)
    IF current_setting('request.jwt.claim.role', true) != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: This function can only be called by Edge Functions'
            USING ERRCODE = 'PAUTH';
    END IF;

    RETURN QUERY
    SELECT
        svs.user_id,
        COUNT(DISTINCT svs.date) AS days_of_data
    FROM social_vitality_scores svs
    WHERE svs.date >= CURRENT_DATE - (p_min_days || ' days')::INTERVAL
    GROUP BY svs.user_id
    HAVING COUNT(DISTINCT svs.date) >= p_min_days;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_users_with_scores IS 'Get all users with at least N days of social vitality scores (for withdrawal detection)';

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Verify tables were created
DO $$
DECLARE
    v_table_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name IN (
        'social_vitality_scores',
        'interaction_metrics',
        'relationship_correlations',
        'peer_support_consent',
        'peer_alert_preferences',
        'peer_alerts',
        'withdrawal_detections'
    );

    IF v_table_count = 7 THEN
        RAISE NOTICE 'Social Vitality Index migration completed successfully (7 tables created)';
    ELSE
        RAISE WARNING 'Migration incomplete: only % out of 7 tables created', v_table_count;
    END IF;
END $$;
