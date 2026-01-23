-- =============================================================================
-- Streak Recovery System
-- Adds streak shields (automatic protection) and recovery quests
-- =============================================================================

-- =============================================================================
-- MARK: - Add Streak Shield Columns to user_stats
-- =============================================================================

ALTER TABLE user_stats
  ADD COLUMN IF NOT EXISTS streak_shields_remaining INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS streak_shields_max INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS shields_reset_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_shield_used_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS recovery_quest_available BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS recovery_quest_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS streak_before_break INT,
  ADD COLUMN IF NOT EXISTS recovery_attempts_remaining INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS recovery_attempts_max INT NOT NULL DEFAULT 1;

-- =============================================================================
-- MARK: - Streak Shield Events (Audit Log)
-- =============================================================================

CREATE TABLE IF NOT EXISTS streak_shield_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('used', 'expired', 'reset', 'purchased')),
  streak_protected INT,
  shields_remaining INT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shield_events_user_date ON streak_shield_events(user_id, created_at DESC);

ALTER TABLE streak_shield_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'streak_shield_events' AND policyname = 'Users can view own shield events'
  ) THEN
    CREATE POLICY "Users can view own shield events" ON streak_shield_events
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Recovery Quest Attempts
-- =============================================================================

CREATE TABLE IF NOT EXISTS recovery_quest_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  streak_to_recover INT NOT NULL,
  quest_template_id UUID REFERENCES quest_templates(id),
  attempt_number INT NOT NULL DEFAULT 1,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'expired', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recovery_attempts_user_status ON recovery_quest_attempts(user_id, status);
CREATE INDEX IF NOT EXISTS idx_recovery_attempts_expires ON recovery_quest_attempts(expired_at) WHERE status IN ('pending', 'in_progress');

ALTER TABLE recovery_quest_attempts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'recovery_quest_attempts' AND policyname = 'Users can view own recovery attempts'
  ) THEN
    CREATE POLICY "Users can view own recovery attempts" ON recovery_quest_attempts
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'recovery_quest_attempts' AND policyname = 'Users can insert own recovery attempts'
  ) THEN
    CREATE POLICY "Users can insert own recovery attempts" ON recovery_quest_attempts
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'recovery_quest_attempts' AND policyname = 'Users can update own recovery attempts'
  ) THEN
    CREATE POLICY "Users can update own recovery attempts" ON recovery_quest_attempts
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Check Streak Protection Function
-- Called when user opens app to check if streak needs protection
-- =============================================================================

CREATE OR REPLACE FUNCTION check_streak_protection(p_user_id UUID)
RETURNS TABLE(
  streak_protected BOOLEAN,
  new_streak INT,
  shields_remaining INT,
  recovery_available BOOLEAN,
  streak_before_break INT,
  recovery_expires_at TIMESTAMPTZ
) AS $$
DECLARE
  v_stats RECORD;
  v_last_quest_date DATE;
  v_today DATE;
  v_yesterday DATE;
  v_streak_protected BOOLEAN := FALSE;
  v_recovery_available BOOLEAN := FALSE;
  v_streak_before INT := NULL;
  v_recovery_exp TIMESTAMPTZ := NULL;
BEGIN
  -- Get user stats
  SELECT * INTO v_stats FROM user_stats WHERE user_id = p_user_id;

  IF v_stats IS NULL THEN
    -- No stats record, nothing to protect
    RETURN QUERY SELECT FALSE, 0, 1, FALSE, NULL::INT, NULL::TIMESTAMPTZ;
    RETURN;
  END IF;

  -- Parse dates
  v_today := CURRENT_DATE;
  v_yesterday := v_today - INTERVAL '1 day';

  -- Get last quest completion date
  IF v_stats.last_quest_date IS NOT NULL THEN
    v_last_quest_date := v_stats.last_quest_date::DATE;
  ELSE
    v_last_quest_date := NULL;
  END IF;

  -- Check if streak is at risk (missed yesterday AND have a streak worth protecting)
  IF v_last_quest_date IS NOT NULL
     AND v_last_quest_date < v_yesterday
     AND v_stats.current_streak_days > 0
     AND NOT v_stats.recovery_quest_available THEN

    -- Streak at risk - try to use shield
    IF v_stats.streak_shields_remaining > 0 THEN
      -- Use shield to protect streak
      UPDATE user_stats SET
        streak_shields_remaining = streak_shields_remaining - 1,
        last_shield_used_at = NOW(),
        -- Update last_quest_date to yesterday so streak continues properly
        last_quest_date = v_yesterday::TEXT,
        updated_at = NOW()
      WHERE user_id = p_user_id;

      -- Log shield usage
      INSERT INTO streak_shield_events (user_id, event_type, streak_protected, shields_remaining)
      VALUES (p_user_id, 'used', v_stats.current_streak_days, v_stats.streak_shields_remaining - 1);

      v_streak_protected := TRUE;
    ELSE
      -- No shields available - break streak but offer recovery
      v_streak_before := v_stats.current_streak_days;
      v_recovery_exp := NOW() + INTERVAL '24 hours';

      UPDATE user_stats SET
        recovery_quest_available = TRUE,
        recovery_quest_expires_at = v_recovery_exp,
        streak_before_break = v_stats.current_streak_days,
        recovery_attempts_remaining = recovery_attempts_max,
        current_streak_days = 0,
        last_quest_date = NULL,
        updated_at = NOW()
      WHERE user_id = p_user_id;

      v_recovery_available := TRUE;
    END IF;
  END IF;

  -- Check if existing recovery quest expired
  IF v_stats.recovery_quest_available
     AND v_stats.recovery_quest_expires_at IS NOT NULL
     AND v_stats.recovery_quest_expires_at < NOW() THEN
    -- Recovery window expired
    UPDATE user_stats SET
      recovery_quest_available = FALSE,
      recovery_quest_expires_at = NULL,
      streak_before_break = NULL,
      recovery_attempts_remaining = recovery_attempts_max,
      updated_at = NOW()
    WHERE user_id = p_user_id;

    -- Mark any pending recovery attempts as expired
    UPDATE recovery_quest_attempts SET
      status = 'expired',
      expired_at = NOW()
    WHERE user_id = p_user_id AND status IN ('pending', 'in_progress');
  END IF;

  -- Return current state after any updates
  SELECT
    us.current_streak_days,
    us.streak_shields_remaining,
    us.recovery_quest_available,
    us.streak_before_break,
    us.recovery_quest_expires_at
  INTO
    new_streak,
    shields_remaining,
    recovery_available,
    streak_before_break,
    recovery_expires_at
  FROM user_stats us WHERE us.user_id = p_user_id;

  streak_protected := v_streak_protected;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Reset Weekly Shields Function
-- Called by cron Edge Function every Monday at 05:00 UTC
-- =============================================================================

CREATE OR REPLACE FUNCTION reset_weekly_shields()
RETURNS TABLE(
  users_reset INT,
  shield_events_created INT
) AS $$
DECLARE
  v_users_reset INT := 0;
  v_events_created INT := 0;
  v_user RECORD;
BEGIN
  -- Get users who need shield reset (shields < max OR never reset OR reset > 7 days ago)
  FOR v_user IN
    SELECT id, user_id, streak_shields_remaining, streak_shields_max
    FROM user_stats
    WHERE streak_shields_remaining < streak_shields_max
       OR shields_reset_at IS NULL
       OR shields_reset_at < NOW() - INTERVAL '6 days'
  LOOP
    -- Only log reset event if shields were actually used
    IF v_user.streak_shields_remaining < v_user.streak_shields_max THEN
      INSERT INTO streak_shield_events (user_id, event_type, shields_remaining, metadata)
      VALUES (v_user.user_id, 'reset', v_user.streak_shields_max,
              jsonb_build_object('previous_shields', v_user.streak_shields_remaining));
      v_events_created := v_events_created + 1;
    END IF;

    -- Reset shields
    UPDATE user_stats SET
      streak_shields_remaining = streak_shields_max,
      shields_reset_at = NOW(),
      updated_at = NOW()
    WHERE id = v_user.id;

    v_users_reset := v_users_reset + 1;
  END LOOP;

  users_reset := v_users_reset;
  shield_events_created := v_events_created;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Start Recovery Quest Function
-- =============================================================================

CREATE OR REPLACE FUNCTION start_recovery_quest(p_user_id UUID)
RETURNS TABLE(
  success BOOLEAN,
  attempt_id UUID,
  quest_template_id UUID,
  quest_title TEXT,
  quest_description TEXT,
  quest_estimated_minutes INT,
  quest_instructions JSONB,
  error_message TEXT
) AS $$
DECLARE
  v_stats RECORD;
  v_template RECORD;
  v_attempt_id UUID;
  v_attempt_number INT;
BEGIN
  -- Get user stats
  SELECT * INTO v_stats FROM user_stats WHERE user_id = p_user_id;

  IF v_stats IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'User stats not found'::TEXT;
    RETURN;
  END IF;

  -- Check if recovery is available
  IF NOT v_stats.recovery_quest_available THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'Recovery quest not available'::TEXT;
    RETURN;
  END IF;

  -- Check if recovery window expired
  IF v_stats.recovery_quest_expires_at < NOW() THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'Recovery window expired'::TEXT;
    RETURN;
  END IF;

  -- Check remaining attempts
  IF v_stats.recovery_attempts_remaining <= 0 THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'No recovery attempts remaining'::TEXT;
    RETURN;
  END IF;

  -- Check for existing in-progress recovery
  IF EXISTS (
    SELECT 1 FROM recovery_quest_attempts
    WHERE user_id = p_user_id AND status = 'in_progress'
  ) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'Recovery quest already in progress'::TEXT;
    RETURN;
  END IF;

  -- Get a longer quest template (10+ minutes)
  SELECT * INTO v_template
  FROM quest_templates
  WHERE estimated_minutes >= 10
    AND (is_active IS NULL OR is_active = TRUE)
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_template IS NULL THEN
    -- Fallback to any template
    SELECT * INTO v_template FROM quest_templates ORDER BY RANDOM() LIMIT 1;
  END IF;

  IF v_template IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'No quest templates available'::TEXT;
    RETURN;
  END IF;

  -- Calculate attempt number
  v_attempt_number := v_stats.recovery_attempts_max - v_stats.recovery_attempts_remaining + 1;

  -- Create recovery attempt
  INSERT INTO recovery_quest_attempts (
    user_id,
    streak_to_recover,
    quest_template_id,
    attempt_number,
    status,
    expired_at
  )
  VALUES (
    p_user_id,
    v_stats.streak_before_break,
    v_template.id,
    v_attempt_number,
    'in_progress',
    v_stats.recovery_quest_expires_at
  )
  RETURNING id INTO v_attempt_id;

  -- Decrement remaining attempts
  UPDATE user_stats SET
    recovery_attempts_remaining = recovery_attempts_remaining - 1,
    updated_at = NOW()
  WHERE user_id = p_user_id;

  RETURN QUERY SELECT
    TRUE,
    v_attempt_id,
    v_template.id,
    v_template.title,
    v_template.description,
    v_template.estimated_minutes,
    v_template.instructions,
    NULL::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Complete Recovery Quest Function
-- =============================================================================

CREATE OR REPLACE FUNCTION complete_recovery_quest(p_user_id UUID, p_attempt_id UUID)
RETURNS TABLE(
  success BOOLEAN,
  restored_streak INT,
  error_message TEXT
) AS $$
DECLARE
  v_attempt RECORD;
  v_stats RECORD;
BEGIN
  -- Get the recovery attempt
  SELECT * INTO v_attempt
  FROM recovery_quest_attempts
  WHERE id = p_attempt_id AND user_id = p_user_id;

  IF v_attempt IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, 'Recovery attempt not found'::TEXT;
    RETURN;
  END IF;

  IF v_attempt.status != 'in_progress' THEN
    RETURN QUERY SELECT FALSE, 0, ('Recovery attempt status is ' || v_attempt.status)::TEXT;
    RETURN;
  END IF;

  -- Check if expired
  IF v_attempt.expired_at IS NOT NULL AND v_attempt.expired_at < NOW() THEN
    UPDATE recovery_quest_attempts SET status = 'expired' WHERE id = p_attempt_id;
    RETURN QUERY SELECT FALSE, 0, 'Recovery attempt has expired'::TEXT;
    RETURN;
  END IF;

  -- Get user stats
  SELECT * INTO v_stats FROM user_stats WHERE user_id = p_user_id;

  -- Mark attempt as completed
  UPDATE recovery_quest_attempts SET
    status = 'completed',
    completed_at = NOW()
  WHERE id = p_attempt_id;

  -- Restore streak
  UPDATE user_stats SET
    current_streak_days = v_attempt.streak_to_recover,
    last_quest_date = CURRENT_DATE::TEXT,
    recovery_quest_available = FALSE,
    recovery_quest_expires_at = NULL,
    streak_before_break = NULL,
    recovery_attempts_remaining = recovery_attempts_max,
    updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Update longest streak if applicable
  UPDATE user_stats SET
    longest_streak_days = v_attempt.streak_to_recover
  WHERE user_id = p_user_id
    AND longest_streak_days < v_attempt.streak_to_recover;

  RETURN QUERY SELECT TRUE, v_attempt.streak_to_recover, NULL::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Fail Recovery Quest Function (for when user abandons)
-- =============================================================================

CREATE OR REPLACE FUNCTION fail_recovery_quest(p_user_id UUID, p_attempt_id UUID)
RETURNS TABLE(
  success BOOLEAN,
  attempts_remaining INT,
  can_retry BOOLEAN,
  error_message TEXT
) AS $$
DECLARE
  v_attempt RECORD;
  v_stats RECORD;
BEGIN
  -- Get the recovery attempt
  SELECT * INTO v_attempt
  FROM recovery_quest_attempts
  WHERE id = p_attempt_id AND user_id = p_user_id;

  IF v_attempt IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, FALSE, 'Recovery attempt not found'::TEXT;
    RETURN;
  END IF;

  IF v_attempt.status != 'in_progress' THEN
    RETURN QUERY SELECT FALSE, 0, FALSE, ('Recovery attempt status is ' || v_attempt.status)::TEXT;
    RETURN;
  END IF;

  -- Mark attempt as failed
  UPDATE recovery_quest_attempts SET
    status = 'failed'
  WHERE id = p_attempt_id;

  -- Get updated stats
  SELECT * INTO v_stats FROM user_stats WHERE user_id = p_user_id;

  RETURN QUERY SELECT
    TRUE,
    v_stats.recovery_attempts_remaining,
    (v_stats.recovery_attempts_remaining > 0 AND v_stats.recovery_quest_expires_at > NOW()),
    NULL::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Get Shield Status Function (for iOS to fetch current state)
-- =============================================================================

CREATE OR REPLACE FUNCTION get_shield_status(p_user_id UUID)
RETURNS TABLE(
  shields_remaining INT,
  shields_max INT,
  shields_reset_at TIMESTAMPTZ,
  last_shield_used_at TIMESTAMPTZ,
  recovery_quest_available BOOLEAN,
  recovery_quest_expires_at TIMESTAMPTZ,
  streak_before_break INT,
  recovery_attempts_remaining INT,
  recovery_attempts_max INT,
  current_streak INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    us.streak_shields_remaining,
    us.streak_shields_max,
    us.shields_reset_at,
    us.last_shield_used_at,
    us.recovery_quest_available,
    us.recovery_quest_expires_at,
    us.streak_before_break,
    us.recovery_attempts_remaining,
    us.recovery_attempts_max,
    us.current_streak_days
  FROM user_stats us
  WHERE us.user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Update shields on premium subscription
-- Called by verify-purchase Edge Function
-- =============================================================================

CREATE OR REPLACE FUNCTION update_premium_shields(p_user_id UUID, p_is_premium BOOLEAN)
RETURNS void AS $$
BEGIN
  IF p_is_premium THEN
    -- Upgrade to premium shields (3 per week, 2 recovery attempts)
    UPDATE user_stats SET
      streak_shields_max = 3,
      streak_shields_remaining = GREATEST(streak_shields_remaining, 3),
      recovery_attempts_max = 2,
      recovery_attempts_remaining = CASE
        WHEN recovery_quest_available THEN GREATEST(recovery_attempts_remaining, 2)
        ELSE 2
      END,
      updated_at = NOW()
    WHERE user_id = p_user_id;
  ELSE
    -- Downgrade to free shields (1 per week, 1 recovery attempt)
    UPDATE user_stats SET
      streak_shields_max = 1,
      streak_shields_remaining = LEAST(streak_shields_remaining, 1),
      recovery_attempts_max = 1,
      recovery_attempts_remaining = LEAST(recovery_attempts_remaining, 1),
      updated_at = NOW()
    WHERE user_id = p_user_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Helper function to get users who need shield reset notification
-- =============================================================================

CREATE OR REPLACE FUNCTION get_users_for_shield_reset_notification()
RETURNS TABLE(
  user_id UUID,
  shields_used INT,
  new_shields INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    us.user_id,
    us.streak_shields_max - us.streak_shields_remaining AS shields_used,
    us.streak_shields_max AS new_shields
  FROM user_stats us
  WHERE us.streak_shields_remaining < us.streak_shields_max;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
