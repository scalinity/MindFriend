-- Smart Notifications ML/Engagement Tracking Migration
-- Adds: notification_predictions table, engagement tracking functions
-- See: kimispecs/11-smart-notifications-context-spec.md

-- =============================================================================
-- MARK: - Notification Predictions Table
-- Stores ML predictions for notification engagement
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Notification Details
    notification_type VARCHAR(64) NOT NULL,
    scheduled_for TIMESTAMPTZ NOT NULL,

    -- Prediction
    engagement_probability DECIMAL(5,4) NOT NULL, -- 0-1
    optimal_delivery_window_start TIMESTAMPTZ NOT NULL,
    optimal_delivery_window_end TIMESTAMPTZ NOT NULL,

    -- Context
    context_signals JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Delivery
    delivered_at TIMESTAMPTZ NULL,
    engagement_result VARCHAR(16) NULL, -- opened, dismissed, ignored, completed
    user_feedback_score INT NULL,
    user_feedback_text TEXT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_predictions_user_created ON notification_predictions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_predictions_user_type ON notification_predictions(user_id, notification_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_predictions_scheduled ON notification_predictions(scheduled_for, delivered_at)
  WHERE delivered_at IS NULL;

-- Enable RLS
ALTER TABLE notification_predictions ENABLE ROW LEVEL SECURITY;

-- RLS policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notification_predictions' AND policyname = 'Users can view own predictions'
  ) THEN
    CREATE POLICY "Users can view own predictions"
      ON notification_predictions FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notification_predictions' AND policyname = 'Users can insert predictions'
  ) THEN
    CREATE POLICY "Users can insert predictions"
      ON notification_predictions FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notification_predictions' AND policyname = 'Users can update own predictions'
  ) THEN
    CREATE POLICY "Users can update own predictions"
      ON notification_predictions FOR UPDATE
      USING (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE notification_predictions IS 'ML predictions and engagement outcomes for smart notifications';

-- =============================================================================
-- MARK: - Notification Engagement Events Table
-- Stores individual engagement events for ML training
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_engagement_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NULL, -- Can be NULL for events without prediction
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    prediction_id UUID NULL REFERENCES notification_predictions(id) ON DELETE SET NULL,

    notification_type VARCHAR(64) NOT NULL,
    predicted_engagement DECIMAL(5,4) NULL,
    context_snapshot JSONB NULL,

    actual_outcome VARCHAR(16) NOT NULL CHECK (actual_outcome IN (
        'scheduled', 'suppressed', 'delivered', 'opened', 'completed', 'dismissed', 'ignored', 'expired'
    )),

    user_feedback_score INT NULL CHECK (user_feedback_score >= 1 AND user_feedback_score <= 5),
    user_feedback_text TEXT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_engagement_user_created ON notification_engagement_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_outcome ON notification_engagement_events(actual_outcome, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_type ON notification_engagement_events(notification_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_training ON notification_engagement_events(user_id, actual_outcome, created_at)
  WHERE actual_outcome IN ('opened', 'completed', 'dismissed', 'ignored');

-- Enable RLS
ALTER TABLE notification_engagement_events ENABLE ROW LEVEL SECURITY;

-- RLS policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notification_engagement_events' AND policyname = 'Users can view own engagement events'
  ) THEN
    CREATE POLICY "Users can view own engagement events"
      ON notification_engagement_events FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notification_engagement_events' AND policyname = 'Users can insert engagement events'
  ) THEN
    CREATE POLICY "Users can insert engagement events"
      ON notification_engagement_events FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE notification_engagement_events IS 'Individual engagement events for ML training and analytics';

-- =============================================================================
-- MARK: - Extend User Settings for Smart Notifications
-- =============================================================================

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS smart_notifications_enabled BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notification_max_per_day INT NOT NULL DEFAULT 5
  CHECK (notification_max_per_day >= 1 AND notification_max_per_day <= 10);
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notification_frequency VARCHAR(16) NOT NULL DEFAULT 'moderate'
  CHECK (notification_frequency IN ('minimal', 'moderate', 'frequent'));
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS enabled_notification_types TEXT[] NOT NULL DEFAULT ARRAY[
  'quest', 'mood', 'streak', 'circle', 'exercise', 'insight', 'achievement', 'reminder'
]::text[];
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS sync_quiet_hours_with_sleep BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS manual_dnd_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS beta_notifications_opt_in BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN user_settings.smart_notifications_enabled IS 'Enable/disable smart contextual notifications';
COMMENT ON COLUMN user_settings.notification_max_per_day IS 'Maximum notifications per day (1-10)';
COMMENT ON COLUMN user_settings.notification_frequency IS 'Notification frequency preference: minimal, moderate, frequent';
COMMENT ON COLUMN user_settings.enabled_notification_types IS 'Array of enabled notification type names';
COMMENT ON COLUMN user_settings.sync_quiet_hours_with_sleep IS 'Sync quiet hours with Sleep Focus';
COMMENT ON COLUMN user_settings.manual_dnd_enabled IS 'Manual Do Not Disturb toggle for iOS 17';
COMMENT ON COLUMN user_settings.beta_notifications_opt_in IS 'Opt-in to beta notification features';

-- =============================================================================
-- MARK: - Get Training Data Function
-- Returns engagement events for ML model training (last 30 days)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_notification_training_data(p_user_id UUID, p_days INT DEFAULT 30)
RETURNS TABLE(
    notification_type TEXT,
    hour_of_day INT,
    day_of_week INT,
    is_weekend BOOLEAN,
    predicted_engagement DECIMAL,
    actual_outcome TEXT,
    context_signals JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        nee.notification_type,
        EXTRACT(HOUR FROM nee.created_at)::int AS hour_of_day,
        EXTRACT(DOW FROM nee.created_at)::int AS day_of_week,
        EXTRACT(DOW FROM nee.created_at) IN (0, 6) AS is_weekend,
        nee.predicted_engagement,
        nee.actual_outcome,
        COALESCE(nee.context_snapshot, '{}'::jsonb) AS context_signals
    FROM notification_engagement_events nee
    WHERE nee.user_id = p_user_id
      AND nee.created_at >= NOW() - INTERVAL '1 day' * p_days
      AND nee.actual_outcome IN ('opened', 'completed', 'dismissed', 'ignored')
    ORDER BY nee.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_notification_training_data(UUID, INT) IS 'Get engagement events for ML model training';

-- =============================================================================
-- MARK: - Get Weekly Engagement Stats Function
-- Returns weekly engagement statistics
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_weekly_engagement_stats(p_user_id UUID)
RETURNS TABLE(
    delivered INT,
    opened INT,
    completed INT,
    dismissed INT,
    engagement_rate DECIMAL,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_start TIMESTAMPTZ;
    v_week_end TIMESTAMPTZ;
BEGIN
    v_week_start := date_trunc('week', NOW());
    v_week_end := v_week_start + INTERVAL '7 days';

    RETURN QUERY
    SELECT
        COUNT(*)::int AS delivered,
        COUNT(*) FILTER (WHERE actual_outcome = 'opened')::int AS opened,
        COUNT(*) FILTER (WHERE actual_outcome = 'completed')::int AS completed,
        COUNT(*) FILTER (WHERE actual_outcome = 'dismissed')::int AS dismissed,
        CASE
            WHEN COUNT(*) FILTER (WHERE actual_outcome IN ('opened', 'completed')) > 0
            THEN COUNT(*) FILTER (WHERE actual_outcome IN ('opened', 'completed'))::decimal / COUNT(*)::decimal
            ELSE 0
        END AS engagement_rate,
        v_week_start,
        v_week_end
    FROM notification_engagement_events
    WHERE user_id = p_user_id
      AND created_at >= v_week_start
      AND created_at < v_week_end
      AND actual_outcome IN ('delivered', 'opened', 'completed', 'dismissed');
END;
$$;

COMMENT ON FUNCTION public.get_weekly_engagement_stats(UUID) IS 'Get weekly engagement statistics for a user';

-- =============================================================================
-- MARK: - Log Notification Engagement Function
-- Insert engagement event from mobile app
-- =============================================================================

CREATE OR REPLACE FUNCTION public.log_notification_engagement(
    p_notification_id UUID,
    p_notification_type TEXT,
    p_actual_outcome TEXT,
    p_predicted_engagement DECIMAL DEFAULT NULL,
    p_context_snapshot JSONB DEFAULT NULL,
    p_user_feedback_score INT DEFAULT NULL,
    p_user_feedback_text TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_id UUID;
    v_user_id UUID;
BEGIN
    -- Get user_id from notification_id (lookup in predictions or history)
    SELECT user_id INTO v_user_id
    FROM notification_predictions
    WHERE id = p_notification_id
    LIMIT 1;

    -- If not found in predictions, try notification_history
    IF v_user_id IS NULL THEN
        SELECT user_id INTO v_user_id
        FROM notification_history
        WHERE id = p_notification_id
        LIMIT 1;
    END IF;

    -- Insert engagement event
    INSERT INTO notification_engagement_events (
        notification_id,
        user_id,
        prediction_id,
        notification_type,
        predicted_engagement,
        context_snapshot,
        actual_outcome,
        user_feedback_score,
        user_feedback_text
    ) VALUES (
        p_notification_id,
        COALESCE(v_user_id, auth.uid()), -- Fallback to current user
        p_notification_id, -- Use notification_id as prediction_id if they match
        p_notification_type,
        p_predicted_engagement,
        p_context_snapshot,
        p_actual_outcome,
        p_user_feedback_score,
        p_user_feedback_text
    )
    RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$;

COMMENT ON FUNCTION public.log_notification_engagement(UUID, TEXT, TEXT, DECIMAL, JSONB, INT, TEXT) IS 'Log notification engagement event from mobile app';
