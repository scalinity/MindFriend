-- Smart Notifications: Engagement Tracking Table
-- For ML training data and notification analytics
-- See: docs/specs/smart-notifications-impl.md

-- =============================================================================
-- MARK: - Notification Engagement Table
-- Tracks all notification events for ML training and analytics
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_engagement (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_id UUID,
    notification_type TEXT NOT NULL,

    -- Prediction data
    predicted_engagement DECIMAL(5,4),

    -- Outcome tracking
    actual_outcome TEXT CHECK (actual_outcome IN (
        'scheduled', 'suppressed', 'delivered',
        'opened', 'completed', 'dismissed', 'ignored', 'expired'
    )),

    -- Context snapshot (for ML training)
    context_snapshot JSONB,

    -- User feedback (optional)
    user_feedback_score INT CHECK (user_feedback_score BETWEEN 1 AND 5),
    user_feedback_text TEXT,

    -- Timestamps
    predicted_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    outcome_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_engagement_user_type
    ON notification_engagement(user_id, notification_type);

CREATE INDEX IF NOT EXISTS idx_engagement_outcome
    ON notification_engagement(actual_outcome, created_at);

CREATE INDEX IF NOT EXISTS idx_engagement_training
    ON notification_engagement(user_id, created_at)
    WHERE actual_outcome IN ('opened', 'completed', 'dismissed', 'ignored');

CREATE INDEX IF NOT EXISTS idx_engagement_user_created
    ON notification_engagement(user_id, created_at DESC);

-- =============================================================================
-- MARK: - Row Level Security
-- =============================================================================

ALTER TABLE notification_engagement ENABLE ROW LEVEL SECURITY;

-- Users can insert their own engagement events
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'notification_engagement'
        AND policyname = 'Users can insert own engagement events'
    ) THEN
        CREATE POLICY "Users can insert own engagement events"
            ON notification_engagement FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Users can read their own engagement events
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'notification_engagement'
        AND policyname = 'Users can read own engagement events'
    ) THEN
        CREATE POLICY "Users can read own engagement events"
            ON notification_engagement FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users can update their own engagement events (for feedback)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'notification_engagement'
        AND policyname = 'Users can update own engagement events'
    ) THEN
        CREATE POLICY "Users can update own engagement events"
            ON notification_engagement FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- MARK: - Extend User Settings for Smart Notifications
-- =============================================================================

-- Smart notification master toggle
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS smart_notifications_enabled BOOLEAN DEFAULT true;

-- Max notifications per day (1-5)
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notification_max_per_day INT DEFAULT 3
    CHECK (notification_max_per_day >= 1 AND notification_max_per_day <= 5);

-- Notification frequency preference
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notification_frequency TEXT DEFAULT 'moderate'
    CHECK (notification_frequency IN ('minimal', 'moderate', 'frequent'));

-- Enabled notification types (JSON array of type strings)
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS enabled_notification_types JSONB
    DEFAULT '["quest", "meditation", "streak", "weekly_summary", "crisis"]'::jsonb;

-- Sync quiet hours with HealthKit sleep schedule
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS sync_quiet_hours_with_sleep BOOLEAN DEFAULT false;

-- Beta features opt-in
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS beta_notifications_opt_in BOOLEAN DEFAULT false;

-- Manual DND toggle for iOS 17 (no Focus Mode API)
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS manual_dnd_enabled BOOLEAN DEFAULT false;

-- Comments for documentation
COMMENT ON COLUMN user_settings.smart_notifications_enabled IS 'Master toggle for smart notification features';
COMMENT ON COLUMN user_settings.notification_max_per_day IS 'Maximum notifications per day (1-5)';
COMMENT ON COLUMN user_settings.notification_frequency IS 'Frequency preference: minimal, moderate, frequent';
COMMENT ON COLUMN user_settings.enabled_notification_types IS 'JSON array of enabled notification types';
COMMENT ON COLUMN user_settings.sync_quiet_hours_with_sleep IS 'Sync quiet hours with HealthKit sleep schedule';
COMMENT ON COLUMN user_settings.beta_notifications_opt_in IS 'Opt-in for experimental notification features';
COMMENT ON COLUMN user_settings.manual_dnd_enabled IS 'Manual DND toggle for iOS 17 (no Focus Mode API)';

-- =============================================================================
-- MARK: - Helper Functions
-- =============================================================================

-- Get weekly engagement stats for a user
CREATE OR REPLACE FUNCTION public.get_notification_engagement_stats(p_user_id UUID)
RETURNS TABLE(
    delivered INT,
    opened INT,
    completed INT,
    dismissed INT,
    engagement_rate DECIMAL(5,4)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_start TIMESTAMPTZ;
BEGIN
    v_week_start := date_trunc('week', NOW());

    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'delivered')::int AS delivered,
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'opened')::int AS opened,
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'completed')::int AS completed,
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'dismissed')::int AS dismissed,
        CASE
            WHEN COUNT(*) FILTER (WHERE ne.actual_outcome = 'delivered') > 0 THEN
                (COUNT(*) FILTER (WHERE ne.actual_outcome IN ('opened', 'completed'))::decimal /
                 COUNT(*) FILTER (WHERE ne.actual_outcome = 'delivered')::decimal)
            ELSE 0.0
        END AS engagement_rate
    FROM notification_engagement ne
    WHERE ne.user_id = p_user_id
        AND ne.created_at >= v_week_start;
END;
$$;

COMMENT ON FUNCTION public.get_notification_engagement_stats IS 'Get weekly notification engagement statistics for a user';

-- Get training data for ML model (last 30 days)
CREATE OR REPLACE FUNCTION public.get_notification_training_data(p_user_id UUID)
RETURNS TABLE(
    notification_type TEXT,
    predicted_engagement DECIMAL(5,4),
    actual_outcome TEXT,
    context_snapshot JSONB,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ne.notification_type,
        ne.predicted_engagement,
        ne.actual_outcome,
        ne.context_snapshot,
        ne.created_at
    FROM notification_engagement ne
    WHERE ne.user_id = p_user_id
        AND ne.created_at >= NOW() - INTERVAL '30 days'
        AND ne.actual_outcome IN ('opened', 'completed', 'dismissed', 'ignored')
    ORDER BY ne.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_notification_training_data IS 'Get notification training data for ML model (last 30 days)';

-- Mark old notifications as ignored (run daily at 3am)
CREATE OR REPLACE FUNCTION public.mark_ignored_notifications()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated_count INT;
BEGIN
    WITH updated AS (
        UPDATE notification_engagement
        SET actual_outcome = 'ignored',
            outcome_at = NOW()
        WHERE actual_outcome = 'delivered'
            AND delivered_at < NOW() - INTERVAL '24 hours'
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_updated_count FROM updated;

    RETURN v_updated_count;
END;
$$;

COMMENT ON FUNCTION public.mark_ignored_notifications IS 'Mark delivered notifications as ignored after 24h with no action';

-- =============================================================================
-- MARK: - Grants
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.get_notification_engagement_stats(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_training_data(UUID) TO authenticated;
-- mark_ignored_notifications is called by Edge Function with service role
