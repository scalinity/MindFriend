-- Migration: Quest Arcs Security Fixes
-- Description: Add authorization checks to SECURITY DEFINER functions and revoke unsafe grants
-- Related: Security audit findings P0-CRITICAL

-- =============================================================================
-- MARK: - Fix increment_arc_day Authorization (P0-CRITICAL)
-- =============================================================================

-- DROP the unsafe version
DROP FUNCTION IF EXISTS increment_arc_day(UUID);

-- Recreate with proper authorization check
CREATE OR REPLACE FUNCTION increment_arc_day(p_user_arc_id UUID)
RETURNS void AS $$
DECLARE
  v_arc_duration INT;
  v_current_day INT;
  v_user_id UUID;
BEGIN
  -- CRITICAL: Verify caller owns the arc enrollment
  SELECT ua.current_day, ua.snapshot_duration_days, ua.user_id
  INTO v_current_day, v_arc_duration, v_user_id
  FROM user_quest_arcs ua
  WHERE ua.id = p_user_arc_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User arc enrollment not found';
  END IF;

  -- Authorization check: only owner or service role can increment
  IF v_user_id != auth.uid() AND auth.role() != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: cannot increment arc day for another user';
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
  WHERE id = p_user_arc_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Revoke and Re-grant with Restrictions
-- =============================================================================

-- Revoke from authenticated (was overly permissive)
REVOKE EXECUTE ON FUNCTION increment_arc_day(UUID) FROM authenticated;

-- Grant only to service_role (Edge Functions use service role key)
GRANT EXECUTE ON FUNCTION increment_arc_day(UUID) TO service_role;

-- Keep get_arc_step_for_user for authenticated (it's safe - has user_id check in query)
GRANT EXECUTE ON FUNCTION get_arc_step_for_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_arc_step_for_user(UUID) TO service_role;

-- =============================================================================
-- MARK: - Add Helper Function for Client-Safe Arc Progress Check
-- =============================================================================

-- Clients can check their own arc progress without calling increment_arc_day
CREATE OR REPLACE FUNCTION get_my_arc_progress()
RETURNS TABLE (
  user_arc_id UUID,
  arc_id UUID,
  arc_title TEXT,
  current_day INT,
  total_days INT,
  status TEXT,
  milestone_days INT[],
  next_milestone_day INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    uqa.id as user_arc_id,
    uqa.arc_id,
    qa.title as arc_title,
    uqa.current_day,
    uqa.snapshot_duration_days as total_days,
    uqa.status,
    uqa.snapshot_milestone_days as milestone_days,
    (
      SELECT MIN(day)
      FROM unnest(uqa.snapshot_milestone_days) as day
      WHERE day > uqa.current_day
    ) as next_milestone_day
  FROM user_quest_arcs uqa
  JOIN quest_arcs qa ON qa.id = uqa.arc_id
  WHERE uqa.user_id = auth.uid()
    AND uqa.status IN ('active', 'paused');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_my_arc_progress() TO authenticated;

-- =============================================================================
-- MARK: - Audit Log for Security Events
-- =============================================================================

-- Create audit log table for arc security events
CREATE TABLE IF NOT EXISTS quest_arc_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_arc_id UUID REFERENCES user_quest_arcs(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('increment_day', 'start_arc', 'pause_arc', 'resume_arc', 'exit_arc')),
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quest_arc_audit_user ON quest_arc_audit_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quest_arc_audit_arc ON quest_arc_audit_log(user_arc_id, created_at DESC);

-- RLS: Users can only see their own audit logs
ALTER TABLE quest_arc_audit_log ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own arc audit logs' AND tablename = 'quest_arc_audit_log'
  ) THEN
    CREATE POLICY "Users can view own arc audit logs" ON quest_arc_audit_log
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Update increment_arc_day to Log Events
-- =============================================================================

CREATE OR REPLACE FUNCTION increment_arc_day(p_user_arc_id UUID)
RETURNS void AS $$
DECLARE
  v_arc_duration INT;
  v_current_day INT;
  v_user_id UUID;
BEGIN
  -- CRITICAL: Verify caller owns the arc enrollment
  SELECT ua.current_day, ua.snapshot_duration_days, ua.user_id
  INTO v_current_day, v_arc_duration, v_user_id
  FROM user_quest_arcs ua
  WHERE ua.id = p_user_arc_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User arc enrollment not found';
  END IF;

  -- Authorization check: only owner or service role can increment
  IF v_user_id != auth.uid() AND auth.role() != 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized: cannot increment arc day for another user';
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
  WHERE id = p_user_arc_id;

  -- Audit log
  INSERT INTO quest_arc_audit_log (user_id, user_arc_id, action, metadata)
  VALUES (v_user_id, p_user_arc_id, 'increment_day', jsonb_build_object(
    'old_day', v_current_day,
    'new_day', v_current_day + 1,
    'caller_role', auth.role()
  ));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION increment_arc_day(UUID) TO service_role;

-- =============================================================================
-- MARK: - End of Migration
-- =============================================================================
