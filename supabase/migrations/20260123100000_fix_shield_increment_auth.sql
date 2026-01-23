-- Fix P0 Critical: Add authentication validation to increment_shield_count()
-- Prevents privilege escalation where any user could manipulate another user's shields

CREATE OR REPLACE FUNCTION public.increment_shield_count(p_user_id UUID)
RETURNS TABLE(shields_awarded BOOLEAN, new_shields_count INT) AS $$
DECLARE
  v_rows_updated INT;
  v_current_count INT;
BEGIN
  -- Security check: prevent cross-user manipulation (P0 Critical Fix)
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot increment shields for another user';
  END IF;

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
  -- Return actual current count instead of 0 (P2 Bug Fix)
  IF v_rows_updated = 0 THEN
    SELECT streak_shields_remaining INTO v_current_count
    FROM user_stats
    WHERE user_id = p_user_id;

    RETURN QUERY SELECT FALSE, COALESCE(v_current_count, 0);
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

-- Restrict execution to service_role only (called from Edge Functions)
REVOKE EXECUTE ON FUNCTION public.increment_shield_count FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.increment_shield_count FROM anon;
REVOKE EXECUTE ON FUNCTION public.increment_shield_count FROM authenticated;
GRANT EXECUTE ON FUNCTION public.increment_shield_count TO service_role;

-- Update comment to reflect security measures
COMMENT ON FUNCTION public.increment_shield_count IS
  'Atomically increments streak_shields_remaining by 1 if below max. Returns shields_awarded=true and new count on success, false with current count if already at max. SECURITY: Validates caller matches user_id. Restricted to service_role execution.';
