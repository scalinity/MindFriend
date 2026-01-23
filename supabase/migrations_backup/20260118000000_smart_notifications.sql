-- Smart Notifications Feature Migration
-- Adds: notification preferences, history tracking, weekly summaries
-- See: specs/04-smart-notifications.md

-- =============================================================================
-- MARK: - Push Tokens (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, token)
);

ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'push_tokens' AND policyname = 'Users can manage own tokens'
  ) THEN
    CREATE POLICY "Users can manage own tokens" ON push_tokens
      FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Extend Profiles for Smart Timing
-- =============================================================================

-- Track typical app open hour for smart notification timing
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS typical_active_hour INT
  CHECK (typical_active_hour >= 0 AND typical_active_hour <= 23);

COMMENT ON COLUMN profiles.typical_active_hour IS 'Hour (0-23) when user typically opens app, for smart notification timing';

-- =============================================================================
-- MARK: - User Settings (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  daily_quest_time_local TEXT NOT NULL DEFAULT '09:00',
  quiet_hours_start_local TEXT,
  quiet_hours_end_local TEXT,
  reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  nudge_after_days_inactive INT NOT NULL DEFAULT 3,
  share_mood_in_circles BOOLEAN NOT NULL DEFAULT true,
  ai_tone TEXT NOT NULL DEFAULT 'friendly' CHECK (ai_tone IN ('friendly', 'professional', 'motivational', 'gentle')),
  privacy_mode TEXT NOT NULL DEFAULT 'standard' CHECK (privacy_mode IN ('standard', 'enhanced')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

-- RLS policies for user_settings
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'Users can view own settings'
  ) THEN
    CREATE POLICY "Users can view own settings"
      ON user_settings FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'Users can insert own settings'
  ) THEN
    CREATE POLICY "Users can insert own settings"
      ON user_settings FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'Users can update own settings'
  ) THEN
    CREATE POLICY "Users can update own settings"
      ON user_settings FOR UPDATE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Extend User Settings for Notification Preferences
-- =============================================================================

-- Social notification toggles
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notify_circle_activity BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notify_hugs BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notify_challenges BOOLEAN NOT NULL DEFAULT true;

-- Motivation notification toggles
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notify_streak_risk BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS notify_weekly_summary BOOLEAN NOT NULL DEFAULT true;

-- Preferred notification time (0-23 hour)
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS preferred_notify_hour INT NOT NULL DEFAULT 9
  CHECK (preferred_notify_hour >= 0 AND preferred_notify_hour <= 23);

COMMENT ON COLUMN user_settings.notify_circle_activity IS 'Notify when circle members post check-ins';
COMMENT ON COLUMN user_settings.notify_hugs IS 'Notify when someone sends you a hug';
COMMENT ON COLUMN user_settings.notify_challenges IS 'Notify about challenge updates';
COMMENT ON COLUMN user_settings.notify_streak_risk IS 'Notify when streak is at risk';
COMMENT ON COLUMN user_settings.notify_weekly_summary IS 'Send weekly Quiet Wins summary';
COMMENT ON COLUMN user_settings.preferred_notify_hour IS 'Preferred hour (0-23) for non-urgent notifications';

-- =============================================================================
-- MARK: - Notification History Table
-- Track all sent notifications for analytics and queue processing
-- =============================================================================

CREATE TABLE IF NOT EXISTS notification_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL CHECK (notification_type IN (
    'circle_activity', 'hug', 'streak_risk', 'weekly_summary', 'challenge'
  )),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  deep_link TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,

  -- Status tracking
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',    -- Queued (e.g., during quiet hours)
    'sent',       -- Sent to APNs
    'delivered',  -- APNs confirmed delivery
    'opened',     -- User tapped notification
    'failed'      -- Delivery failed
  )),

  -- Timestamps
  scheduled_for TIMESTAMPTZ,  -- For quiet hours queueing
  sent_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_date DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX idx_notification_user_created ON notification_history(user_id, created_at DESC);
CREATE INDEX idx_notification_type ON notification_history(notification_type, created_at DESC);
CREATE INDEX idx_notification_pending ON notification_history(status, scheduled_for)
  WHERE status = 'pending';
CREATE INDEX idx_notification_user_type_day ON notification_history(user_id, notification_type, created_date);

ALTER TABLE notification_history ENABLE ROW LEVEL SECURITY;

-- Users can only see their own notification history
CREATE POLICY "Users can view own notifications"
  ON notification_history FOR SELECT
  USING (auth.uid() = user_id);

-- Service role inserts notifications (not users directly)
-- No INSERT policy for authenticated users - Edge Functions use service role

COMMENT ON TABLE notification_history IS 'Track all push notifications for analytics and quiet hours queueing';

-- =============================================================================
-- MARK: - Weekly Summaries Table
-- Aggregated weekly stats for the "Quiet Wins" notification
-- =============================================================================

CREATE TABLE IF NOT EXISTS weekly_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  checkin_count INT NOT NULL DEFAULT 0,
  quest_count INT NOT NULL DEFAULT 0,
  exercise_count INT NOT NULL DEFAULT 0,
  avg_mood FLOAT,
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining')),
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(user_id, week_start)
);

CREATE INDEX idx_weekly_user ON weekly_summaries(user_id, week_start DESC);

ALTER TABLE weekly_summaries ENABLE ROW LEVEL SECURITY;

-- Users can view their own summaries
CREATE POLICY "Users can view own summaries"
  ON weekly_summaries FOR SELECT
  USING (auth.uid() = user_id);

COMMENT ON TABLE weekly_summaries IS 'Aggregated weekly stats for Quiet Wins summary notification';

-- =============================================================================
-- MARK: - Get Streak At Risk Users Function
-- Returns users who have an active streak but haven't checked in today
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_streak_at_risk_users(p_target_hour INT)
RETURNS TABLE(
  user_id UUID,
  current_streak_days INT,
  timezone TEXT,
  push_token TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.current_streak_days,
    p.timezone,
    pt.token AS push_token
  FROM profiles p
  -- Join to push tokens to get device token
  INNER JOIN push_tokens pt ON pt.user_id = p.id
  -- Join to user settings to check notification preference
  INNER JOIN user_settings us ON us.user_id = p.id
  WHERE
    -- Has an active streak
    p.current_streak_days > 0
    -- Streak risk notifications enabled
    AND us.notify_streak_risk = true
    -- Current hour in user's timezone matches target hour
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE p.timezone) = p_target_hour
    -- Hasn't completed a quest today (in their timezone)
    AND NOT EXISTS (
      SELECT 1 FROM quests q
      WHERE q.user_id = p.id
        AND q.status = 'completed'
        AND q.local_date = (NOW() AT TIME ZONE p.timezone)::date::text
    )
    -- Hasn't already received a streak_risk notification today
    AND NOT EXISTS (
      SELECT 1 FROM notification_history nh
      WHERE nh.user_id = p.id
        AND nh.notification_type = 'streak_risk'
        AND nh.created_date = CURRENT_DATE
        AND nh.metadata->>'target_hour' = p_target_hour::text
    );
END;
$$;

COMMENT ON FUNCTION public.get_streak_at_risk_users IS 'Get users with active streaks who need streak risk notifications at the given hour';

-- =============================================================================
-- MARK: - Get Pending Notifications Function
-- Returns queued notifications ready to be sent (quiet hours ended)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_pending_notifications(p_limit INT DEFAULT 100)
RETURNS TABLE(
  id UUID,
  user_id UUID,
  notification_type TEXT,
  title TEXT,
  body TEXT,
  deep_link TEXT,
  metadata JSONB,
  push_token TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    nh.id,
    nh.user_id,
    nh.notification_type,
    nh.title,
    nh.body,
    nh.deep_link,
    nh.metadata,
    pt.token AS push_token
  FROM notification_history nh
  INNER JOIN push_tokens pt ON pt.user_id = nh.user_id
  INNER JOIN profiles p ON p.id = nh.user_id
  INNER JOIN user_settings us ON us.user_id = nh.user_id
  WHERE
    -- Is pending
    nh.status = 'pending'
    -- Scheduled time has passed
    AND nh.scheduled_for <= NOW()
    -- Not currently in quiet hours
    AND NOT public.is_in_quiet_hours(
      EXTRACT(HOUR FROM NOW() AT TIME ZONE p.timezone)::int,
      us.quiet_hours_start_local,
      us.quiet_hours_end_local
    )
  ORDER BY nh.scheduled_for ASC
  LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION public.get_pending_notifications IS 'Get queued notifications ready to send (quiet hours ended)';

-- =============================================================================
-- MARK: - Quiet Hours Helper Function
-- Check if a given hour is within quiet hours
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_in_quiet_hours(
  p_current_hour INT,
  p_quiet_start TEXT,
  p_quiet_end TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_start_hour INT;
  v_end_hour INT;
BEGIN
  -- If quiet hours not set, not in quiet hours
  IF p_quiet_start IS NULL OR p_quiet_end IS NULL THEN
    RETURN false;
  END IF;

  -- Parse hour from HH:MM format
  v_start_hour := SPLIT_PART(p_quiet_start, ':', 1)::int;
  v_end_hour := SPLIT_PART(p_quiet_end, ':', 1)::int;

  -- Handle wrap-around (e.g., 22:00 to 08:00)
  IF v_start_hour > v_end_hour THEN
    -- Quiet hours span midnight
    RETURN p_current_hour >= v_start_hour OR p_current_hour < v_end_hour;
  ELSE
    -- Normal range
    RETURN p_current_hour >= v_start_hour AND p_current_hour < v_end_hour;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.is_in_quiet_hours IS 'Check if hour is within quiet hours (handles midnight wrap-around)';

-- =============================================================================
-- MARK: - Update Typical Active Hour Function
-- Rolling average of app open times for smart timing
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_typical_active_hour(p_user_id UUID, p_hour INT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_hour INT;
BEGIN
  -- Get current typical hour
  SELECT typical_active_hour INTO v_current_hour
  FROM profiles
  WHERE id = p_user_id;

  -- If no current hour, just set it
  IF v_current_hour IS NULL THEN
    UPDATE profiles SET typical_active_hour = p_hour WHERE id = p_user_id;
  ELSE
    -- Rolling average (weight current slightly more for stability)
    UPDATE profiles
    SET typical_active_hour = ROUND((v_current_hour * 2 + p_hour) / 3.0)::int
    WHERE id = p_user_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.update_typical_active_hour IS 'Update rolling average of typical app open hour';

-- =============================================================================
-- MARK: - Get Users for Weekly Summary Function
-- Returns users who should receive the weekly summary notification
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_users_for_weekly_summary()
RETURNS TABLE(
  user_id UUID,
  push_token TEXT,
  timezone TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    pt.token AS push_token,
    p.timezone
  FROM profiles p
  INNER JOIN push_tokens pt ON pt.user_id = p.id
  INNER JOIN user_settings us ON us.user_id = p.id
  WHERE
    -- Weekly summary enabled
    us.notify_weekly_summary = true
    -- It's Sunday 6 PM in their timezone
    AND EXTRACT(DOW FROM NOW() AT TIME ZONE p.timezone) = 0  -- Sunday
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE p.timezone) = 18;  -- 6 PM
END;
$$;

COMMENT ON FUNCTION public.get_users_for_weekly_summary IS 'Get users who should receive weekly summary (Sunday 6 PM local)';

-- =============================================================================
-- MARK: - Calculate Weekly Stats Function
-- Aggregate stats for a user's week
-- =============================================================================

CREATE OR REPLACE FUNCTION public.calculate_weekly_stats(p_user_id UUID)
RETURNS TABLE(
  checkin_count INT,
  quest_count INT,
  exercise_count INT,
  avg_mood FLOAT,
  mood_trend TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start TIMESTAMPTZ;
  v_prev_week_start TIMESTAMPTZ;
  v_this_week_avg FLOAT;
  v_prev_week_avg FLOAT;
  v_trend TEXT;
BEGIN
  -- Get start of current week (Monday)
  v_week_start := date_trunc('week', NOW());
  v_prev_week_start := v_week_start - INTERVAL '7 days';

  -- Calculate this week's average mood
  SELECT AVG(mood_score) INTO v_this_week_avg
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_week_start;

  -- Calculate previous week's average mood for trend
  SELECT AVG(mood_score) INTO v_prev_week_avg
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_prev_week_start
    AND created_at < v_week_start;

  -- Determine trend
  IF v_this_week_avg IS NULL OR v_prev_week_avg IS NULL THEN
    v_trend := 'stable';
  ELSIF v_this_week_avg > v_prev_week_avg + 0.5 THEN
    v_trend := 'improving';
  ELSIF v_this_week_avg < v_prev_week_avg - 0.5 THEN
    v_trend := 'declining';
  ELSE
    v_trend := 'stable';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*)::int FROM moods WHERE user_id = p_user_id AND created_at >= v_week_start),
    (SELECT COUNT(*)::int FROM quests WHERE user_id = p_user_id AND status = 'completed' AND completed_at >= v_week_start),
    (SELECT COUNT(*)::int FROM exercise_sessions WHERE user_id = p_user_id AND created_at >= v_week_start),
    v_this_week_avg,
    v_trend;
END;
$$;

COMMENT ON FUNCTION public.calculate_weekly_stats IS 'Calculate weekly stats for a user (mood count, quests, exercises, mood trend)';

-- =============================================================================
-- MARK: - Grant Permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.is_in_quiet_hours(INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_typical_active_hour(UUID, INT) TO authenticated;
-- Note: Other functions use SECURITY DEFINER and are called by Edge Functions with service role
