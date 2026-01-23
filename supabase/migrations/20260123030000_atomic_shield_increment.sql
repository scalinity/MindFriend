-- Atomic Shield Increment Function
-- Prevents race conditions when awarding shields at 7-day milestones

CREATE OR REPLACE FUNCTION public.increment_shield_count(p_user_id UUID)
RETURNS TABLE(shields_awarded BOOLEAN, new_shields_count INT) AS $$
DECLARE
  v_rows_updated INT;
BEGIN
  -- Atomic update: increment shields_remaining by 1 only if below max
  -- The WHERE clause ensures we don't exceed the maximum
  UPDATE user_stats
  SET
    streak_shields_remaining = streak_shields_remaining + 1,
    updated_at = NOW()
  WHERE user_id = p_user_id
    AND streak_shields_remaining < streak_shields_max;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  -- If no rows were updated, user is already at max shields
  IF v_rows_updated = 0 THEN
    RETURN QUERY SELECT FALSE, 0;
    RETURN;
  END IF;

  -- Return success with the new shield count
  RETURN QUERY
  SELECT
    TRUE as shields_awarded,
    streak_shields_remaining as new_shields_count
  FROM user_stats
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add helpful comment
COMMENT ON FUNCTION public.increment_shield_count IS
  'Atomically increments streak_shields_remaining by 1 if below max. Returns shields_awarded=true and new count on success, false if already at max.';
