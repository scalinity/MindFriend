-- Security Fix: Add authorization checks to SECURITY DEFINER functions
-- Migration: Quest Arcs Security Hardening
-- Date: 2026-01-20

-- Fix: increment_arc_day - Add ownership verification
CREATE OR REPLACE FUNCTION increment_arc_day(p_user_arc_id UUID)
RETURNS void AS $$
DECLARE
  v_arc_duration INT;
  v_current_day INT;
  v_user_id UUID;
BEGIN
  -- SECURITY: Verify caller owns this arc enrollment
  SELECT ua.user_id, ua.current_day, ua.snapshot_duration_days
  INTO v_user_id, v_current_day, v_arc_duration
  FROM user_quest_arcs ua
  WHERE ua.id = p_user_arc_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User arc enrollment not found';
  END IF;

  -- AUTHORIZATION CHECK: Ensure caller owns this resource
  IF v_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Cannot modify another user''s arc progress';
  END IF;

  -- Increment day
  UPDATE user_quest_arcs
  SET current_day = current_day + 1,
      last_quest_completed_at = NOW(),
      -- Mark completed if final day
      status = CASE
        WHEN v_current_day + 1 >= v_arc_duration THEN 'completed'
        ELSE status
      END,
      completed_at = CASE
        WHEN v_current_day + 1 >= v_arc_duration THEN NOW()
        ELSE completed_at
      END
  WHERE id = p_user_arc_id
    AND user_id = auth.uid(); -- Double-check authorization
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Fix: get_arc_step_for_user - Already safe (uses p_user_id parameter which should match auth.uid())
-- But add explicit check for defense in depth
CREATE OR REPLACE FUNCTION get_arc_step_for_user(p_user_id UUID)
RETURNS TABLE (
  quest_template_id UUID,
  custom_title TEXT,
  custom_description TEXT,
  is_milestone BOOLEAN,
  milestone_xp_bonus INT,
  day_number INT,
  user_arc_id UUID
) AS $$
BEGIN
  -- SECURITY: Verify caller is requesting their own data
  IF p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access another user''s arc data';
  END IF;

  RETURN QUERY
  SELECT
    qas.quest_template_id,
    qas.custom_title,
    qas.custom_description,
    qas.is_milestone,
    qas.milestone_xp_bonus,
    qas.day_number,
    uqa.id as user_arc_id
  FROM user_quest_arcs uqa
  JOIN quest_arc_steps qas ON qas.arc_id = uqa.arc_id
    AND qas.day_number = uqa.current_day + 1
  WHERE uqa.user_id = p_user_id
    AND uqa.status = 'active'
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION increment_arc_day(UUID) IS 'Increments user arc progress after quest completion. SECURITY DEFINER with ownership validation.';
COMMENT ON FUNCTION get_arc_step_for_user(UUID) IS 'Gets next quest step for user arc. SECURITY DEFINER with caller verification.';
