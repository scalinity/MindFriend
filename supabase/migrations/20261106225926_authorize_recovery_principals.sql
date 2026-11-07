-- Anonymous or missing identities cannot inspect or change recovery state.
BEGIN;

CREATE OR REPLACE FUNCTION "public"."complete_recovery_quest"("p_user_id" "uuid", "p_attempt_id" "uuid") RETURNS TABLE("success" boolean, "restored_streak" integer, "error_message" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_attempt RECORD;
  v_stats RECORD;
BEGIN
  -- Security check
  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
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
$$;
REVOKE ALL ON FUNCTION public.complete_recovery_quest(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_recovery_quest(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."fail_recovery_quest"("p_user_id" "uuid", "p_attempt_id" "uuid") RETURNS TABLE("success" boolean, "attempts_remaining" integer, "can_retry" boolean, "error_message" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_attempt RECORD;
  v_stats RECORD;
BEGIN
  -- Security check
  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
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
$$;
REVOKE ALL ON FUNCTION public.fail_recovery_quest(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fail_recovery_quest(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_shield_status"("p_user_id" "uuid") RETURNS TABLE("shields_remaining" integer, "shields_max" integer, "shields_reset_at" timestamp with time zone, "last_shield_used_at" timestamp with time zone, "recovery_quest_available" boolean, "recovery_quest_expires_at" timestamp with time zone, "streak_before_break" integer, "recovery_attempts_remaining" integer, "recovery_attempts_max" integer, "current_streak" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
BEGIN
  -- Security check
  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
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
$$;
REVOKE ALL ON FUNCTION public.get_shield_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shield_status(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."start_recovery_quest"("p_user_id" "uuid") RETURNS TABLE("success" boolean, "attempt_id" "uuid", "quest_template_id" "uuid", "quest_title" "text", "quest_description" "text", "quest_estimated_minutes" integer, "quest_instructions" "jsonb", "error_message" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_stats RECORD;
  v_template RECORD;
  v_attempt_id UUID;
  v_attempt_number INT;
  v_template_count INT;
BEGIN
  -- Security check
  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
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
$$;
REVOKE ALL ON FUNCTION public.start_recovery_quest(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_recovery_quest(uuid) TO authenticated, service_role;

COMMIT;
