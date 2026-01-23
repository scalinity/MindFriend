-- Re-engagement Flows Migration
-- Tracks user absences and enables personalized welcome-back experiences

-- =============================================================================
-- PROFILES EXTENSION: Session tracking columns
-- =============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_session_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS session_count INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_absence_days INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fresh_start_used_at TIMESTAMPTZ;

-- Initialize last_session_at for existing users
UPDATE profiles
SET last_session_at = COALESCE(updated_at, created_at)
WHERE last_session_at IS NULL;

-- =============================================================================
-- REENGAGEMENT EVENTS: Track user reengagement interactions
-- =============================================================================

CREATE TABLE IF NOT EXISTS reengagement_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'welcome_back_shown',
    'welcome_back_dismissed',
    'fresh_start_chosen',
    'continue_chosen',
    'notification_sent',
    'notification_opened'
  )),
  absence_days INT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reengagement_user ON reengagement_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reengagement_type ON reengagement_events(event_type, created_at DESC);

ALTER TABLE reengagement_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'reengagement_events'
    AND policyname = 'Users see own reengagement events'
  ) THEN
    CREATE POLICY "Users see own reengagement events" ON reengagement_events
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'reengagement_events'
    AND policyname = 'Users insert own reengagement events'
  ) THEN
    CREATE POLICY "Users insert own reengagement events" ON reengagement_events
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MISSED ACTIVITY SUMMARIES: Cached summary of what user missed
-- =============================================================================

CREATE TABLE IF NOT EXISTS missed_activity_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  since_date DATE NOT NULL,
  hugs_received INT DEFAULT 0,
  circle_posts_count INT DEFAULT 0,
  friend_milestones JSONB DEFAULT '[]'::jsonb, -- [{name, milestone, type}]
  challenges_missed INT DEFAULT 0,
  generated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, since_date)
);

CREATE INDEX IF NOT EXISTS idx_missed_activity_user ON missed_activity_summaries(user_id);

ALTER TABLE missed_activity_summaries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'missed_activity_summaries'
    AND policyname = 'Users see own missed activity'
  ) THEN
    CREATE POLICY "Users see own missed activity" ON missed_activity_summaries
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- FUNCTION: Calculate user absence and activity summary
-- =============================================================================

CREATE OR REPLACE FUNCTION calculate_user_absence(p_user_id UUID)
RETURNS TABLE(
  absence_days INT,
  lapse_tier TEXT,
  hugs_received INT,
  circle_posts INT,
  friend_milestones JSONB
) AS $$
DECLARE
  v_last_session TIMESTAMPTZ;
  v_days INT;
  v_tier TEXT;
  v_hugs INT;
  v_posts INT;
  v_milestones JSONB;
BEGIN
  -- Get last session
  SELECT last_session_at INTO v_last_session FROM profiles WHERE id = p_user_id;

  -- Calculate days absent
  v_days := COALESCE(EXTRACT(DAY FROM NOW() - v_last_session)::INT, 0);

  -- Determine tier per spec
  v_tier := CASE
    WHEN v_days < 3 THEN 'active'
    WHEN v_days < 7 THEN 'brief_break'
    WHEN v_days < 14 THEN 'extended_break'
    WHEN v_days < 30 THEN 'long_absence'
    ELSE 'hiatus'
  END;

  -- Count hugs received since last session
  SELECT COUNT(*)::INT INTO v_hugs
  FROM circle_hugs
  WHERE recipient_id = p_user_id
    AND created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days');

  -- Count circle posts from others in user's circles
  SELECT COUNT(*)::INT INTO v_posts
  FROM circle_posts cp
  JOIN circle_members cm ON cm.circle_id = cp.circle_id
  WHERE cm.user_id = p_user_id
    AND cp.user_id != p_user_id
    AND cp.created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days');

  -- Get friend milestones (streak achievements, badges, etc.)
  SELECT COALESCE(json_agg(json_build_object(
    'name', p.display_name,
    'milestone', cp.body_text,
    'isStreak', CASE WHEN cp.body_text ILIKE '%streak%' THEN TRUE ELSE FALSE END
  )), '[]'::json)::jsonb INTO v_milestones
  FROM circle_posts cp
  JOIN profiles p ON p.id = cp.user_id
  JOIN circle_members cm ON cm.circle_id = cp.circle_id
  WHERE cm.user_id = p_user_id
    AND cp.kind = 'milestone'
    AND cp.user_id != p_user_id
    AND cp.created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days')
  LIMIT 5;

  -- Return the results
  RETURN QUERY SELECT v_days, v_tier, COALESCE(v_hugs, 0), COALESCE(v_posts, 0), COALESCE(v_milestones, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- FUNCTION: Record session start and update absence tracking
-- =============================================================================

CREATE OR REPLACE FUNCTION record_session_start(p_user_id UUID)
RETURNS TABLE(
  previous_absence_days INT,
  lapse_tier TEXT,
  is_returning BOOLEAN
) AS $$
DECLARE
  v_last_session TIMESTAMPTZ;
  v_days INT;
  v_tier TEXT;
BEGIN
  -- Get last session before updating
  SELECT last_session_at INTO v_last_session FROM profiles WHERE id = p_user_id;

  -- Calculate days absent
  v_days := COALESCE(EXTRACT(DAY FROM NOW() - v_last_session)::INT, 0);

  -- Determine tier
  v_tier := CASE
    WHEN v_days < 3 THEN 'active'
    WHEN v_days < 7 THEN 'brief_break'
    WHEN v_days < 14 THEN 'extended_break'
    WHEN v_days < 30 THEN 'long_absence'
    ELSE 'hiatus'
  END;

  -- Update the profile with new session timestamp
  UPDATE profiles SET
    last_session_at = NOW(),
    session_count = COALESCE(session_count, 0) + 1,
    last_absence_days = v_days
  WHERE id = p_user_id;

  -- Return info about the previous absence
  RETURN QUERY SELECT v_days, v_tier, (v_days >= 3);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- FUNCTION: Perform fresh start (resets visible streak but preserves history)
-- =============================================================================

CREATE OR REPLACE FUNCTION perform_fresh_start(p_user_id UUID)
RETURNS TABLE(
  success BOOLEAN,
  new_streak INT,
  fresh_start_bonus INT
) AS $$
DECLARE
  v_fresh_start_bonus INT := 2; -- Start at day 2 as bonus
BEGIN
  -- Update profile with fresh start
  UPDATE profiles SET
    current_streak_days = v_fresh_start_bonus,
    fresh_start_used_at = NOW()
  WHERE id = p_user_id;

  -- Log the fresh start event
  INSERT INTO reengagement_events (user_id, event_type, absence_days, metadata)
  SELECT
    p_user_id,
    'fresh_start_chosen',
    COALESCE(last_absence_days, 0),
    jsonb_build_object('previous_streak', current_streak_days)
  FROM profiles WHERE id = p_user_id;

  RETURN QUERY SELECT TRUE, v_fresh_start_bonus, v_fresh_start_bonus;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- FUNCTION: Get lapsed users for notification (used by Edge Function cron)
-- This function is more flexible than a view and works regardless of push_tokens table
-- =============================================================================

CREATE OR REPLACE FUNCTION get_lapsed_users_for_notification()
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  last_session_at TIMESTAMPTZ,
  days_absent INT,
  notification_type TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.display_name,
    p.last_session_at,
    EXTRACT(DAY FROM NOW() - p.last_session_at)::INT AS days_absent,
    CASE
      WHEN EXTRACT(DAY FROM NOW() - p.last_session_at)::INT = 3 THEN 'gentle_checkin'
      WHEN EXTRACT(DAY FROM NOW() - p.last_session_at)::INT = 7 THEN 'social_hook'
      WHEN EXTRACT(DAY FROM NOW() - p.last_session_at)::INT = 14 THEN 'progress_saved'
      WHEN EXTRACT(DAY FROM NOW() - p.last_session_at)::INT = 30 THEN 'fresh_start_offer'
      ELSE NULL
    END AS notification_type
  FROM profiles p
  LEFT JOIN user_settings us ON us.user_id = p.id
  WHERE p.last_session_at IS NOT NULL
    AND EXTRACT(DAY FROM NOW() - p.last_session_at)::INT IN (3, 7, 14, 30)
    AND COALESCE(us.reminders_enabled, TRUE) = TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: Welcome back quest template will be assigned dynamically by assign-quest Edge Function
-- using existing quest templates tagged appropriately, rather than requiring a schema change.
