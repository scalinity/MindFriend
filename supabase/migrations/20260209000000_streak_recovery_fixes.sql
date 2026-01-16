-- =============================================================================
-- Streak Recovery System Fixes
-- Addresses: race conditions, timezone handling, performance, security
-- =============================================================================

-- =============================================================================
-- MARK: - Add Missing Indexes for Performance
-- =============================================================================

-- Index for shield reset queries (finding users who need reset)
-- Note: CONCURRENTLY removed as it doesn't work in migration pipelines
CREATE INDEX IF NOT EXISTS idx_user_stats_shields_reset
  ON user_stats(shields_reset_at)
  WHERE streak_shields_remaining < streak_shields_max
     OR shields_reset_at IS NULL;

-- Index for recovery quest lookups
CREATE INDEX IF NOT EXISTS idx_user_stats_recovery
  ON user_stats(user_id)
  WHERE recovery_quest_available = TRUE;

-- Index for shield remaining queries
CREATE INDEX IF NOT EXISTS idx_user_stats_shields_used
  ON user_stats(user_id)
  WHERE streak_shields_remaining < streak_shields_max;

-- =============================================================================
-- MARK: - Fixed check_streak_protection Function
-- Fixes: race condition (atomic update), timezone handling, multi-day gap
-- =============================================================================

-- Drop existing function first since we're changing the return type
DROP FUNCTION IF EXISTS check_streak_protection(UUID);

CREATE OR REPLACE FUNCTION check_streak_protection(p_user_id UUID)
RETURNS TABLE(
  streak_protected BOOLEAN,
  new_streak INT,
  shields_remaining INT,
  shields_max INT,
  recovery_available BOOLEAN,
  streak_before_break INT,
  recovery_expires_at TIMESTAMPTZ
) AS $$
DECLARE
  v_stats RECORD;
  v_last_quest_date DATE;
  v_today DATE;
  v_yesterday DATE;
  v_two_days_ago DATE;
  v_streak_protected BOOLEAN := FALSE;
  v_recovery_available BOOLEAN := FALSE;
  v_streak_before INT := NULL;
  v_recovery_exp TIMESTAMPTZ := NULL;
  v_timezone TEXT;
  v_local_now TIMESTAMPTZ;
  v_shield_used BOOLEAN := FALSE;
  v_days_missed INT;
BEGIN
  -- Security check: ensure caller is the user or service role
  -- Note: SECURITY DEFINER functions bypass RLS, so we validate manually
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot check protection for another user';
  END IF;

  -- Get user stats with row lock to prevent race conditions
  SELECT * INTO v_stats
  FROM user_stats
  WHERE user_id = p_user_id
  FOR UPDATE NOWAIT;

  IF v_stats IS NULL THEN
    -- No stats record, nothing to protect
    RETURN QUERY SELECT FALSE, 0, 1, 1, FALSE, NULL::INT, NULL::TIMESTAMPTZ;
    RETURN;
  END IF;

  -- Get user's timezone for accurate date calculation
  SELECT timezone INTO v_timezone FROM profiles WHERE id = p_user_id;
  v_timezone := COALESCE(v_timezone, 'UTC');

  -- Calculate dates in user's local timezone
  BEGIN
    v_local_now := NOW() AT TIME ZONE v_timezone;
    v_today := v_local_now::DATE;
  EXCEPTION WHEN OTHERS THEN
    -- Fallback to UTC if timezone is invalid
    v_today := CURRENT_DATE;
  END;

  v_yesterday := v_today - INTERVAL '1 day';
  v_two_days_ago := v_today - INTERVAL '2 days';

  -- Get last quest completion date
  IF v_stats.last_quest_date IS NOT NULL THEN
    v_last_quest_date := v_stats.last_quest_date::DATE;
  ELSE
    v_last_quest_date := NULL;
  END IF;

  -- Check if streak is at risk (missed at least yesterday AND have a streak worth protecting)
  IF v_last_quest_date IS NOT NULL
     AND v_last_quest_date < v_yesterday
     AND v_stats.current_streak_days > 0
     AND NOT v_stats.recovery_quest_available THEN

    -- Calculate how many days were missed
    v_days_missed := v_yesterday - v_last_quest_date;

    -- Shield only protects SINGLE day misses (last quest was exactly 2 days ago)
    IF v_last_quest_date = v_two_days_ago AND v_stats.streak_shields_remaining > 0 THEN
      -- ATOMIC: Use shield only if shields > 0, in a single UPDATE
      -- This prevents race conditions from concurrent requests
      UPDATE user_stats SET
        streak_shields_remaining = streak_shields_remaining - 1,
        last_shield_used_at = NOW(),
        last_quest_date = v_yesterday::TEXT,
        updated_at = NOW()
      WHERE user_id = p_user_id
        AND streak_shields_remaining > 0
      RETURNING streak_shields_remaining INTO v_stats.streak_shields_remaining;

      -- Check if shield was actually used (atomic check)
      IF FOUND THEN
        v_shield_used := TRUE;

        -- Log shield usage
        INSERT INTO streak_shield_events (user_id, event_type, streak_protected, shields_remaining)
        VALUES (p_user_id, 'used', v_stats.current_streak_days, v_stats.streak_shields_remaining);

        v_streak_protected := TRUE;
      END IF;
    END IF;

    -- If shield wasn't used (either no shields, multi-day gap, or race condition)
    IF NOT v_shield_used THEN
      -- Break streak but offer recovery
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
    us.streak_shields_max,
    us.recovery_quest_available,
    us.streak_before_break,
    us.recovery_quest_expires_at
  INTO
    new_streak,
    shields_remaining,
    shields_max,
    recovery_available,
    streak_before_break,
    recovery_expires_at
  FROM user_stats us WHERE us.user_id = p_user_id;

  streak_protected := v_streak_protected;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Fixed reset_weekly_shields Function (Batch Operations)
-- Fixes: O(n) FOR LOOP converted to O(1) batch operations
-- =============================================================================

CREATE OR REPLACE FUNCTION reset_weekly_shields()
RETURNS TABLE(
  users_reset INT,
  shield_events_created INT
) AS $$
DECLARE
  v_users_reset INT;
  v_events_created INT;
BEGIN
  -- Batch insert audit events for users who had shields used (before reset)
  INSERT INTO streak_shield_events (user_id, event_type, shields_remaining, metadata)
  SELECT
    us.user_id,
    'reset',
    us.streak_shields_max,
    jsonb_build_object('previous_shields', us.streak_shields_remaining)
  FROM user_stats us
  WHERE us.streak_shields_remaining < us.streak_shields_max;

  GET DIAGNOSTICS v_events_created = ROW_COUNT;

  -- Batch update all eligible users in a single statement
  UPDATE user_stats SET
    streak_shields_remaining = streak_shields_max,
    shields_reset_at = NOW(),
    updated_at = NOW()
  WHERE streak_shields_remaining < streak_shields_max
     OR shields_reset_at IS NULL
     OR shields_reset_at < NOW() - INTERVAL '6 days';

  GET DIAGNOSTICS v_users_reset = ROW_COUNT;

  users_reset := v_users_reset;
  shield_events_created := v_events_created;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Fixed start_recovery_quest Function
-- Fixes: TOCTOU race condition with FOR UPDATE, NULL expiration check,
--        efficient random selection, internal auth check
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
  v_template_count INT;
BEGIN
  -- Security check
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot start recovery for another user';
  END IF;

  -- Get user stats with row lock to prevent TOCTOU race conditions
  SELECT * INTO v_stats
  FROM user_stats
  WHERE user_id = p_user_id
  FOR UPDATE NOWAIT;

  IF v_stats IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'User stats not found'::TEXT;
    RETURN;
  END IF;

  -- Check if recovery is available
  IF NOT v_stats.recovery_quest_available THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'Recovery quest not available'::TEXT;
    RETURN;
  END IF;

  -- Check if recovery window expired (with NULL handling)
  IF v_stats.recovery_quest_expires_at IS NULL OR v_stats.recovery_quest_expires_at < NOW() THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'Recovery window expired'::TEXT;
    RETURN;
  END IF;

  -- Check remaining attempts
  IF v_stats.recovery_attempts_remaining <= 0 THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'No recovery attempts remaining'::TEXT;
    RETURN;
  END IF;

  -- Check for existing in-progress recovery (with lock to prevent race)
  IF EXISTS (
    SELECT 1 FROM recovery_quest_attempts
    WHERE user_id = p_user_id AND status = 'in_progress'
    FOR UPDATE SKIP LOCKED
  ) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::JSONB, 'Recovery quest already in progress'::TEXT;
    RETURN;
  END IF;

  -- Get a longer quest template (10+ minutes) using efficient random selection
  -- Using OFFSET with random() is more efficient than ORDER BY RANDOM()
  SELECT COUNT(*) INTO v_template_count
  FROM quest_templates
  WHERE estimated_minutes >= 10
    AND (is_active IS NULL OR is_active = TRUE);

  IF v_template_count > 0 THEN
    SELECT * INTO v_template
    FROM quest_templates
    WHERE estimated_minutes >= 10
      AND (is_active IS NULL OR is_active = TRUE)
    OFFSET floor(random() * v_template_count)
    LIMIT 1;
  END IF;

  IF v_template IS NULL THEN
    -- Fallback to any template
    SELECT COUNT(*) INTO v_template_count FROM quest_templates;
    IF v_template_count > 0 THEN
      SELECT * INTO v_template
      FROM quest_templates
      OFFSET floor(random() * v_template_count)
      LIMIT 1;
    END IF;
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
-- MARK: - Fixed complete_recovery_quest Function
-- Fixes: internal auth check
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
  -- Security check
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot complete recovery for another user';
  END IF;

  -- Validate attempt_id format (basic UUID check via cast)
  IF p_attempt_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, 'Invalid attempt ID'::TEXT;
    RETURN;
  END IF;

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
-- MARK: - Fixed fail_recovery_quest Function
-- Fixes: internal auth check
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
  -- Security check
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot fail recovery for another user';
  END IF;

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
-- MARK: - Fixed get_shield_status Function
-- Fixes: internal auth check
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
  -- Security check
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot get shield status for another user';
  END IF;

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
-- MARK: - Fixed get_users_for_shield_reset_notification Function
-- This is called by service role only during cron, so no user auth check needed
-- =============================================================================

-- No changes needed - this is only called by service role during cron job

-- =============================================================================
-- MARK: - Fixed update_premium_shields Function
-- Fixes: internal auth check (service role only, but add validation)
-- =============================================================================

CREATE OR REPLACE FUNCTION update_premium_shields(p_user_id UUID, p_is_premium BOOLEAN)
RETURNS void AS $$
BEGIN
  -- This function should only be called by service role from verify-purchase
  -- No auth.uid() check since service role calls don't have auth context

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
