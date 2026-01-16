-- Proactive Intelligence Feature Migration
-- Transforms MindFriend's AI from reactive to proactive
-- See: docs/specs/01-proactive-intelligence.md

-- =============================================================================
-- MARK: - User Engagement States Table
-- Tracks user engagement level for smart outreach cadence
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_engagement_states (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  current_state TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (current_state IN ('HIGHLY_ACTIVE', 'ACTIVE', 'MODERATE', 'DRIFTING', 'LAPSED', 'HIBERNATING')),
  state_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_proactive_at TIMESTAMPTZ,
  proactive_ignore_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_engagement_states_state ON user_engagement_states(current_state);
CREATE INDEX IF NOT EXISTS idx_engagement_states_last_activity ON user_engagement_states(last_activity_at);

ALTER TABLE user_engagement_states ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_engagement_states' AND policyname = 'Users can view own engagement state'
  ) THEN
    CREATE POLICY "Users can view own engagement state" ON user_engagement_states
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE user_engagement_states IS 'Tracks user engagement level for smart proactive outreach cadence';
COMMENT ON COLUMN user_engagement_states.current_state IS 'HIGHLY_ACTIVE (daily) -> ACTIVE (4-6/wk) -> MODERATE (2-3/wk) -> DRIFTING (1/wk) -> LAPSED (7+ days) -> HIBERNATING (30+ days)';
COMMENT ON COLUMN user_engagement_states.proactive_ignore_count IS 'Count of consecutive ignored proactive messages for backoff logic';

-- =============================================================================
-- MARK: - Proactive Messages Table
-- Log of all proactive outreach messages
-- =============================================================================

CREATE TABLE IF NOT EXISTS proactive_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  trigger_type TEXT NOT NULL
    CHECK (trigger_type IN ('mood_decline', 'missed_routine', 'streak_risk',
           'post_low_mood', 'milestone_approach', 'reengagement',
           'pattern_insight', 'calendar_prep', 'weather_correlation')),
  message_content TEXT NOT NULL,
  delivery_channel TEXT NOT NULL CHECK (delivery_channel IN ('push', 'in_app', 'both')),
  scheduled_for TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  engaged_at TIMESTAMPTZ,
  dismissed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled', 'sent', 'opened', 'engaged', 'dismissed', 'expired', 'cancelled')),
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_proactive_messages_user_scheduled ON proactive_messages(user_id, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_proactive_messages_status ON proactive_messages(status, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_proactive_messages_user_status ON proactive_messages(user_id, status);
CREATE INDEX IF NOT EXISTS idx_proactive_messages_trigger ON proactive_messages(trigger_type, created_at);

ALTER TABLE proactive_messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'proactive_messages' AND policyname = 'Users can view own proactive messages'
  ) THEN
    CREATE POLICY "Users can view own proactive messages" ON proactive_messages
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE proactive_messages IS 'Log of all proactive outreach messages with engagement tracking';
COMMENT ON COLUMN proactive_messages.trigger_type IS 'What triggered this message: mood_decline, streak_risk, milestone_approach, etc.';
COMMENT ON COLUMN proactive_messages.engaged_at IS 'When user took action (opened app, did quest, etc.)';

-- =============================================================================
-- MARK: - User Patterns Table
-- Detected behavioral patterns for personalized insights
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_patterns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pattern_type TEXT NOT NULL
    CHECK (pattern_type IN ('day_of_week', 'time_of_day', 'exercise_correlation',
           'sleep_proxy', 'quest_preference', 'streak_recovery', 'custom')),
  pattern_key TEXT NOT NULL,
  pattern_data JSONB NOT NULL,
  confidence FLOAT NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  first_detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_confirmed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  times_surfaced INT NOT NULL DEFAULT 0,
  user_acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, pattern_type, pattern_key)
);

CREATE INDEX IF NOT EXISTS idx_user_patterns_user_active ON user_patterns(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_user_patterns_type ON user_patterns(pattern_type, confidence DESC);

ALTER TABLE user_patterns ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_patterns' AND policyname = 'Users can view own patterns'
  ) THEN
    CREATE POLICY "Users can view own patterns" ON user_patterns
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_patterns' AND policyname = 'Users can acknowledge patterns'
  ) THEN
    CREATE POLICY "Users can acknowledge patterns" ON user_patterns
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE user_patterns IS 'Detected behavioral patterns (mood by day-of-week, exercise correlation, etc.)';
COMMENT ON COLUMN user_patterns.pattern_key IS 'Unique identifier like monday_dip, morning_person, exercise_mood_boost';
COMMENT ON COLUMN user_patterns.confidence IS 'Pattern confidence 0-1 based on sample size and consistency';

-- =============================================================================
-- MARK: - Extend User Settings for Proactive Preferences
-- =============================================================================

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS proactive_enabled BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS proactive_max_daily INT DEFAULT 2
  CHECK (proactive_max_daily >= 0 AND proactive_max_daily <= 10);
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS proactive_types_enabled TEXT[] DEFAULT
  ARRAY['mood_decline', 'streak_risk', 'milestone_approach', 'pattern_insight'];
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS calendar_integration_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS weather_insights_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';

COMMENT ON COLUMN user_settings.proactive_enabled IS 'Master toggle for proactive check-ins';
COMMENT ON COLUMN user_settings.proactive_max_daily IS 'Maximum proactive messages per day (default 2)';
COMMENT ON COLUMN user_settings.proactive_types_enabled IS 'Array of enabled trigger types';
COMMENT ON COLUMN user_settings.calendar_integration_enabled IS 'Enable calendar-aware breathing exercises';
COMMENT ON COLUMN user_settings.weather_insights_enabled IS 'Enable weather-correlated suggestions';

-- =============================================================================
-- MARK: - Update Engagement State Function
-- Calculates and updates user engagement state based on activity
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_engagement_state(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days_since_activity INT;
  v_activity_last_7_days INT;
  v_current_state TEXT;
  v_new_state TEXT;
  v_last_activity TIMESTAMPTZ;
BEGIN
  -- Find most recent activity
  SELECT GREATEST(
    COALESCE((SELECT MAX(created_at) FROM moods WHERE user_id = p_user_id), '1970-01-01'::timestamptz),
    COALESCE((SELECT MAX(completed_at) FROM quests WHERE user_id = p_user_id AND status = 'completed'), '1970-01-01'::timestamptz),
    COALESCE((SELECT MAX(created_at) FROM messages WHERE conversation_id IN
      (SELECT id FROM conversations WHERE user_id = p_user_id)), '1970-01-01'::timestamptz)
  ) INTO v_last_activity;

  -- Calculate days since last activity
  v_days_since_activity := GREATEST(0, EXTRACT(EPOCH FROM NOW() - v_last_activity) / 86400)::INT;

  -- Count activity days in last 7 days
  SELECT COUNT(DISTINCT activity_date) INTO v_activity_last_7_days
  FROM (
    SELECT local_date::date AS activity_date FROM moods
    WHERE user_id = p_user_id AND created_at > NOW() - INTERVAL '7 days'
    UNION
    SELECT local_date::date AS activity_date FROM quests
    WHERE user_id = p_user_id AND status = 'completed' AND completed_at > NOW() - INTERVAL '7 days'
    UNION
    SELECT created_at::date AS activity_date FROM messages
    WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = p_user_id)
      AND created_at > NOW() - INTERVAL '7 days'
  ) activities;

  -- Determine new state based on activity
  v_new_state := CASE
    WHEN v_days_since_activity >= 30 THEN 'HIBERNATING'
    WHEN v_days_since_activity >= 7 THEN 'LAPSED'
    WHEN v_activity_last_7_days <= 1 THEN 'DRIFTING'
    WHEN v_activity_last_7_days <= 3 THEN 'MODERATE'
    WHEN v_activity_last_7_days <= 5 THEN 'ACTIVE'
    ELSE 'HIGHLY_ACTIVE'
  END;

  -- Get current state
  SELECT current_state INTO v_current_state
  FROM user_engagement_states
  WHERE user_id = p_user_id;

  -- Upsert engagement state
  INSERT INTO user_engagement_states (user_id, current_state, last_activity_at)
  VALUES (p_user_id, v_new_state, COALESCE(v_last_activity, NOW()))
  ON CONFLICT (user_id) DO UPDATE SET
    current_state = CASE
      WHEN user_engagement_states.current_state != v_new_state
      THEN v_new_state
      ELSE user_engagement_states.current_state
    END,
    state_changed_at = CASE
      WHEN user_engagement_states.current_state != v_new_state
      THEN NOW()
      ELSE user_engagement_states.state_changed_at
    END,
    last_activity_at = COALESCE(v_last_activity, NOW()),
    updated_at = NOW();

  RETURN v_new_state;
END;
$$;

COMMENT ON FUNCTION public.update_engagement_state IS 'Calculate and update user engagement state based on recent activity';

-- =============================================================================
-- MARK: - Detect Mood Patterns Function
-- Analyzes user mood data to detect patterns
-- =============================================================================

CREATE OR REPLACE FUNCTION public.detect_mood_patterns(p_user_id UUID)
RETURNS TABLE(pattern_type TEXT, pattern_key TEXT, pattern_data JSONB, confidence FLOAT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Day-of-week pattern detection (needs 3+ weeks of data)
  RETURN QUERY
  WITH daily_moods AS (
    SELECT
      EXTRACT(DOW FROM created_at) AS day_of_week,
      AVG(mood_score) AS avg_mood,
      COUNT(*) AS sample_count
    FROM moods
    WHERE user_id = p_user_id
      AND created_at > NOW() - INTERVAL '28 days'
    GROUP BY EXTRACT(DOW FROM created_at)
    HAVING COUNT(*) >= 3
  ),
  overall_avg AS (
    SELECT AVG(mood_score) AS avg FROM moods
    WHERE user_id = p_user_id AND created_at > NOW() - INTERVAL '28 days'
  )
  SELECT
    'day_of_week'::TEXT AS pattern_type,
    CASE dm.day_of_week
      WHEN 0 THEN 'sunday' WHEN 1 THEN 'monday' WHEN 2 THEN 'tuesday'
      WHEN 3 THEN 'wednesday' WHEN 4 THEN 'thursday' WHEN 5 THEN 'friday'
      ELSE 'saturday'
    END || '_' || CASE WHEN dm.avg_mood < oa.avg - 0.5 THEN 'dip' ELSE 'peak' END AS pattern_key,
    jsonb_build_object(
      'day_of_week', dm.day_of_week,
      'avg_mood', ROUND(dm.avg_mood::numeric, 2),
      'overall_avg', ROUND(oa.avg::numeric, 2),
      'sample_count', dm.sample_count,
      'delta', ROUND((dm.avg_mood - oa.avg)::numeric, 2)
    ) AS pattern_data,
    LEAST(1.0, dm.sample_count::float / 10.0)::FLOAT AS confidence
  FROM daily_moods dm, overall_avg oa
  WHERE ABS(dm.avg_mood - oa.avg) > 0.5;

  -- Exercise-mood correlation pattern
  RETURN QUERY
  WITH exercise_days AS (
    SELECT DISTINCT local_date::date AS exercise_date
    FROM exercise_sessions es
    WHERE es.user_id = p_user_id
      AND es.completed = TRUE
      AND es.created_at > NOW() - INTERVAL '28 days'
  ),
  mood_comparison AS (
    SELECT
      CASE WHEN ed.exercise_date IS NOT NULL THEN 'exercise' ELSE 'no_exercise' END AS day_type,
      AVG(m.mood_score) AS avg_mood,
      COUNT(*) AS sample_count
    FROM moods m
    LEFT JOIN exercise_days ed ON m.local_date::date = ed.exercise_date
    WHERE m.user_id = p_user_id
      AND m.created_at > NOW() - INTERVAL '28 days'
    GROUP BY CASE WHEN ed.exercise_date IS NOT NULL THEN 'exercise' ELSE 'no_exercise' END
    HAVING COUNT(*) >= 5
  )
  SELECT
    'exercise_correlation'::TEXT AS pattern_type,
    'exercise_mood_boost'::TEXT AS pattern_key,
    jsonb_build_object(
      'exercise_day_avg', ROUND((SELECT avg_mood FROM mood_comparison WHERE day_type = 'exercise')::numeric, 2),
      'non_exercise_day_avg', ROUND((SELECT avg_mood FROM mood_comparison WHERE day_type = 'no_exercise')::numeric, 2),
      'delta', ROUND(((SELECT avg_mood FROM mood_comparison WHERE day_type = 'exercise') -
               (SELECT avg_mood FROM mood_comparison WHERE day_type = 'no_exercise'))::numeric, 2)
    ) AS pattern_data,
    0.8::FLOAT AS confidence
  WHERE (SELECT COUNT(*) FROM mood_comparison) = 2
    AND (SELECT avg_mood FROM mood_comparison WHERE day_type = 'exercise') >
        (SELECT avg_mood FROM mood_comparison WHERE day_type = 'no_exercise') + 0.3;

  -- Quest type preference pattern
  RETURN QUERY
  WITH quest_completions AS (
    SELECT
      qt.type AS quest_type,
      COUNT(*) AS completed_count,
      COUNT(*)::float / NULLIF(SUM(COUNT(*)) OVER (), 0) AS completion_rate
    FROM quests q
    JOIN quest_templates qt ON q.quest_template_id = qt.id
    WHERE q.user_id = p_user_id
      AND q.status = 'completed'
      AND q.completed_at > NOW() - INTERVAL '28 days'
    GROUP BY qt.type
    HAVING COUNT(*) >= 3
  )
  SELECT
    'quest_preference'::TEXT AS pattern_type,
    'favorite_' || quest_type::TEXT AS pattern_key,
    jsonb_build_object(
      'quest_type', quest_type,
      'completed_count', completed_count,
      'completion_rate', ROUND(completion_rate::numeric, 2)
    ) AS pattern_data,
    LEAST(1.0, completed_count::float / 10.0)::FLOAT AS confidence
  FROM quest_completions
  WHERE completion_rate > 0.4;  -- Clearly prefers this type
END;
$$;

COMMENT ON FUNCTION public.detect_mood_patterns IS 'Detect mood patterns (day-of-week, exercise correlation, quest preference)';

-- =============================================================================
-- MARK: - Find Mood Decline Users Function
-- Returns users with consecutive low mood days
-- =============================================================================

CREATE OR REPLACE FUNCTION public.find_mood_decline_users(
  p_threshold INT DEFAULT 2,
  p_consecutive_days INT DEFAULT 2
)
RETURNS TABLE(user_id UUID, avg_mood FLOAT, consecutive_days INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH recent_moods AS (
    SELECT
      m.user_id,
      m.mood_score,
      m.local_date,
      ROW_NUMBER() OVER (PARTITION BY m.user_id ORDER BY m.local_date DESC) AS rn
    FROM moods m
    WHERE m.created_at > NOW() - INTERVAL '7 days'
  ),
  low_mood_streaks AS (
    SELECT
      rm.user_id,
      COUNT(*) AS consecutive_low_days,
      AVG(rm.mood_score) AS avg_mood
    FROM recent_moods rm
    WHERE rm.rn <= p_consecutive_days
      AND rm.mood_score <= p_threshold
    GROUP BY rm.user_id
    HAVING COUNT(*) >= p_consecutive_days
  )
  SELECT
    lms.user_id,
    lms.avg_mood::FLOAT,
    lms.consecutive_low_days::INT
  FROM low_mood_streaks lms
  -- Exclude users who already received a mood_decline message in last 24h
  WHERE NOT EXISTS (
    SELECT 1 FROM proactive_messages pm
    WHERE pm.user_id = lms.user_id
      AND pm.trigger_type = 'mood_decline'
      AND pm.created_at > NOW() - INTERVAL '24 hours'
  )
  -- Only users with proactive enabled
  AND EXISTS (
    SELECT 1 FROM user_settings us
    WHERE us.user_id = lms.user_id
      AND us.proactive_enabled = TRUE
      AND 'mood_decline' = ANY(us.proactive_types_enabled)
  );
END;
$$;

COMMENT ON FUNCTION public.find_mood_decline_users IS 'Find users with consecutive low mood days for proactive outreach';

-- =============================================================================
-- MARK: - Find Streak Risk Users Function
-- Returns users with active streaks who haven't completed today's quest
-- =============================================================================

CREATE OR REPLACE FUNCTION public.find_streak_risk_users(p_min_streak INT DEFAULT 3)
RETURNS TABLE(user_id UUID, current_streak_days INT, timezone TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.current_streak_days,
    COALESCE(us.timezone, 'UTC') AS timezone
  FROM profiles p
  JOIN user_settings us ON us.user_id = p.id
  WHERE
    p.current_streak_days >= p_min_streak
    -- It's past 6 PM local time
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE COALESCE(us.timezone, 'UTC')) >= 18
    -- No activity today
    AND NOT EXISTS (
      SELECT 1 FROM quests q
      WHERE q.user_id = p.id
        AND q.status = 'completed'
        AND q.local_date = (NOW() AT TIME ZONE COALESCE(us.timezone, 'UTC'))::date::text
    )
    -- No streak_risk message sent today
    AND NOT EXISTS (
      SELECT 1 FROM proactive_messages pm
      WHERE pm.user_id = p.id
        AND pm.trigger_type = 'streak_risk'
        AND pm.created_at > NOW() - INTERVAL '24 hours'
    )
    -- Proactive enabled
    AND us.proactive_enabled = TRUE
    AND 'streak_risk' = ANY(us.proactive_types_enabled);
END;
$$;

COMMENT ON FUNCTION public.find_streak_risk_users IS 'Find users with streaks at risk (no activity today, past 6 PM)';

-- =============================================================================
-- MARK: - Find Milestone Approaching Users Function
-- Returns users 1 day away from streak milestones
-- =============================================================================

CREATE OR REPLACE FUNCTION public.find_milestone_approaching_users()
RETURNS TABLE(user_id UUID, current_streak_days INT, next_milestone INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  milestones INT[] := ARRAY[7, 14, 30, 60, 100, 365];
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.current_streak_days,
    m AS next_milestone
  FROM profiles p
  JOIN user_settings us ON us.user_id = p.id
  CROSS JOIN UNNEST(milestones) AS m
  WHERE
    p.current_streak_days = m - 1  -- One day away from milestone
    -- No milestone message sent today
    AND NOT EXISTS (
      SELECT 1 FROM proactive_messages pm
      WHERE pm.user_id = p.id
        AND pm.trigger_type = 'milestone_approach'
        AND pm.created_at > NOW() - INTERVAL '24 hours'
    )
    -- Proactive enabled
    AND us.proactive_enabled = TRUE
    AND 'milestone_approach' = ANY(us.proactive_types_enabled);
END;
$$;

COMMENT ON FUNCTION public.find_milestone_approaching_users IS 'Find users 1 day away from streak milestones (7, 14, 30, 60, 100, 365)';

-- =============================================================================
-- MARK: - Find Re-engagement Users Function
-- Returns users who have been inactive for specified days
-- =============================================================================

CREATE OR REPLACE FUNCTION public.find_reengagement_users(p_days_inactive INT DEFAULT 3)
RETURNS TABLE(user_id UUID, days_inactive INT, last_activity_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ues.user_id,
    EXTRACT(EPOCH FROM NOW() - ues.last_activity_at)::INT / 86400 AS days_inactive,
    ues.last_activity_at
  FROM user_engagement_states ues
  JOIN user_settings us ON us.user_id = ues.user_id
  WHERE
    ues.current_state IN ('DRIFTING', 'LAPSED')
    AND EXTRACT(EPOCH FROM NOW() - ues.last_activity_at) / 86400 >= p_days_inactive
    -- Only send on specific days: 3, 7, 14 days
    AND EXTRACT(EPOCH FROM NOW() - ues.last_activity_at)::INT / 86400 IN (3, 7, 14)
    -- No reengagement message sent recently
    AND NOT EXISTS (
      SELECT 1 FROM proactive_messages pm
      WHERE pm.user_id = ues.user_id
        AND pm.trigger_type = 'reengagement'
        AND pm.created_at > NOW() - INTERVAL '3 days'
    )
    -- Proactive enabled
    AND us.proactive_enabled = TRUE
    AND 'reengagement' = ANY(us.proactive_types_enabled)
    -- Not too many ignored messages
    AND ues.proactive_ignore_count < 3;
END;
$$;

COMMENT ON FUNCTION public.find_reengagement_users IS 'Find inactive users for re-engagement (day 3, 7, 14)';

-- =============================================================================
-- MARK: - Get Pattern Eligible Users Function
-- Returns users with sufficient data for pattern detection
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_pattern_eligible_users(p_min_days INT DEFAULT 14)
RETURNS TABLE(user_id UUID, mood_count INT, first_mood_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.user_id,
    COUNT(*)::INT AS mood_count,
    MIN(m.created_at) AS first_mood_at
  FROM moods m
  JOIN user_settings us ON us.user_id = m.user_id
  WHERE us.proactive_enabled = TRUE
    AND 'pattern_insight' = ANY(us.proactive_types_enabled)
  GROUP BY m.user_id
  HAVING
    COUNT(*) >= p_min_days
    AND MIN(m.created_at) < NOW() - (p_min_days || ' days')::INTERVAL;
END;
$$;

COMMENT ON FUNCTION public.get_pattern_eligible_users IS 'Find users with enough mood data for pattern detection';

-- =============================================================================
-- MARK: - Record Proactive Engagement Function
-- Updates proactive message status and engagement tracking
-- =============================================================================

CREATE OR REPLACE FUNCTION public.record_proactive_engagement(
  p_message_id UUID,
  p_action TEXT  -- 'opened', 'engaged', 'dismissed'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- Get user_id from message
  SELECT user_id INTO v_user_id FROM proactive_messages WHERE id = p_message_id;

  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  -- Update message status
  UPDATE proactive_messages
  SET
    status = p_action,
    opened_at = CASE WHEN p_action IN ('opened', 'engaged') AND opened_at IS NULL THEN NOW() ELSE opened_at END,
    engaged_at = CASE WHEN p_action = 'engaged' THEN NOW() ELSE engaged_at END,
    dismissed_at = CASE WHEN p_action = 'dismissed' THEN NOW() ELSE dismissed_at END
  WHERE id = p_message_id;

  -- Update engagement state
  IF p_action = 'engaged' THEN
    -- Reset ignore count on engagement
    UPDATE user_engagement_states
    SET
      proactive_ignore_count = 0,
      last_activity_at = NOW(),
      updated_at = NOW()
    WHERE user_id = v_user_id;
  ELSIF p_action = 'dismissed' THEN
    -- Increment ignore count
    UPDATE user_engagement_states
    SET
      proactive_ignore_count = proactive_ignore_count + 1,
      updated_at = NOW()
    WHERE user_id = v_user_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.record_proactive_engagement IS 'Record user response to proactive message (opened/engaged/dismissed)';

-- =============================================================================
-- MARK: - Get User Proactive Count Today Function
-- Returns count of proactive messages sent to user today
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_user_proactive_count_today(p_user_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM proactive_messages
  WHERE user_id = p_user_id
    AND sent_at IS NOT NULL
    AND sent_at > NOW() - INTERVAL '24 hours';

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.get_user_proactive_count_today IS 'Count proactive messages sent to user in last 24 hours';

-- =============================================================================
-- MARK: - Acknowledge Pattern Function (for authenticated users)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.acknowledge_pattern(p_pattern_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_patterns
  SET
    user_acknowledged = TRUE,
    times_surfaced = times_surfaced + 1,
    updated_at = NOW()
  WHERE id = p_pattern_id
    AND user_id = auth.uid();
END;
$$;

COMMENT ON FUNCTION public.acknowledge_pattern IS 'Mark a pattern as acknowledged by the user';

-- =============================================================================
-- MARK: - Grant Permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION public.update_engagement_state(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_pattern(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_proactive_count_today(UUID) TO authenticated;
-- Note: Scheduler functions use SECURITY DEFINER and are called by Edge Functions with service role

-- =============================================================================
-- MARK: - Trigger to Update Engagement State on Activity
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trigger_update_engagement_on_mood()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.update_engagement_state(NEW.user_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_engagement_on_mood ON moods;
CREATE TRIGGER update_engagement_on_mood
  AFTER INSERT ON moods
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_update_engagement_on_mood();

CREATE OR REPLACE FUNCTION public.trigger_update_engagement_on_quest()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'completed' THEN
    PERFORM public.update_engagement_state(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_engagement_on_quest ON quests;
CREATE TRIGGER update_engagement_on_quest
  AFTER UPDATE OF status ON quests
  FOR EACH ROW
  WHEN (NEW.status = 'completed')
  EXECUTE FUNCTION public.trigger_update_engagement_on_quest();

COMMENT ON FUNCTION public.trigger_update_engagement_on_mood IS 'Auto-update engagement state when mood is logged';
COMMENT ON FUNCTION public.trigger_update_engagement_on_quest IS 'Auto-update engagement state when quest is completed';
