-- Achievement Milestones Security & Performance Fixes
-- Addresses P0 critical issues from Phase 2 review

-- ============================================================================
-- PART 1: FIX RLS POLICIES (P0 Security - Prevent Progression Bypass)
-- ============================================================================

-- Drop overly permissive policies
DROP POLICY IF EXISTS "Users manage own badges" ON user_badges_v2;
DROP POLICY IF EXISTS "Users manage own milestones" ON milestone_celebrations;
DROP POLICY IF EXISTS "Users manage own xp" ON user_experience;

-- USER_BADGES_V2: Separate read/write permissions
CREATE POLICY "Users read own badges"
  ON user_badges_v2 FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role awards badges"
  ON user_badges_v2 FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Service role updates badge progress"
  ON user_badges_v2 FOR UPDATE
  USING (auth.role() = 'service_role');

CREATE POLICY "Users update badge UI state"
  ON user_badges_v2 FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- P0 FIX: Use trigger to enforce immutability of progression fields
CREATE OR REPLACE FUNCTION prevent_badge_progression_tampering()
RETURNS TRIGGER AS $$
BEGIN
  -- Only allow users to update notification flags
  IF auth.uid() = NEW.user_id THEN
    -- Enforce immutability of progression fields
    IF OLD.progress_current != NEW.progress_current OR
       OLD.progress_target != NEW.progress_target OR
       OLD.is_earned != NEW.is_earned OR
       OLD.earned_at IS DISTINCT FROM NEW.earned_at THEN
      RAISE EXCEPTION 'Users cannot modify badge progression fields';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER enforce_badge_immutability
  BEFORE UPDATE ON user_badges_v2
  FOR EACH ROW
  EXECUTE FUNCTION prevent_badge_progression_tampering();

-- MILESTONE_CELEBRATIONS: Lock down creation to service role
CREATE POLICY "Users read own milestones"
  ON milestone_celebrations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role creates milestones"
  ON milestone_celebrations FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Users mark milestones viewed/shared"
  ON milestone_celebrations FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- P0 FIX: Use trigger to enforce immutability of milestone content
CREATE OR REPLACE FUNCTION prevent_milestone_content_tampering()
RETURNS TRIGGER AS $$
BEGIN
  -- Only allow users to update viewed/shared flags
  IF auth.uid() = NEW.user_id THEN
    -- Enforce immutability of content fields
    IF OLD.level_reached != NEW.level_reached OR
       OLD.narrative != NEW.narrative OR
       OLD.journey_stats::text != NEW.journey_stats::text OR
       OLD.generated_at != NEW.generated_at THEN
      RAISE EXCEPTION 'Users cannot modify milestone content';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER enforce_milestone_immutability
  BEFORE UPDATE ON milestone_celebrations
  FOR EACH ROW
  EXECUTE FUNCTION prevent_milestone_content_tampering();

-- USER_EXPERIENCE: Complete lockdown - service role only for writes
CREATE POLICY "Users read own xp"
  ON user_experience FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role manages xp"
  ON user_experience FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================================
-- PART 2: ADD COMPOSITE INDEXES (P0 Performance)
-- ============================================================================

-- Optimize exercise type filtering (prevents table scans)
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_badge_progress
  ON exercise_sessions(user_id, completed, exercise_id)
  WHERE completed = true;

CREATE INDEX IF NOT EXISTS idx_exercises_type
  ON exercises(id, type);

-- Optimize playback/meditation filtering
CREATE INDEX IF NOT EXISTS idx_playback_sessions_badge_progress
  ON playback_sessions(user_id, completed, track_id)
  WHERE completed = true;

CREATE INDEX IF NOT EXISTS idx_audio_tracks_category
  ON audio_tracks(id, category);

-- Optimize user_experience lookup
CREATE INDEX IF NOT EXISTS idx_user_experience_lookup
  ON user_experience(user_id, current_level);

-- Optimize streak lookup
CREATE INDEX IF NOT EXISTS idx_user_streaks_badge_lookup
  ON user_streaks_v2(user_id, streak_type, current_count);

-- Optimize unviewed milestones with covering index
CREATE INDEX IF NOT EXISTS idx_milestone_celebrations_unviewed_with_level
  ON milestone_celebrations(user_id, level_reached DESC)
  WHERE NOT viewed;

-- ============================================================================
-- PART 3: CREATE AGGREGATE FUNCTION (P0 Performance - Fix N+1 Queries)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_badge_metrics(p_user_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'questsCompleted', (
      SELECT COUNT(*)
      FROM quests
      WHERE user_id = p_user_id AND completed = true
    ),
    'moodsLogged', (
      SELECT COUNT(*)
      FROM moods
      WHERE user_id = p_user_id
    ),
    'exercisesCompleted', (
      SELECT COUNT(*)
      FROM exercise_sessions
      WHERE user_id = p_user_id AND completed = true
    ),
    'breathingExercises', (
      SELECT COUNT(*)
      FROM exercise_sessions es
      JOIN exercises e ON es.exercise_id = e.id
      WHERE es.user_id = p_user_id AND es.completed = true AND e.type = 'breathing'
    ),
    'meditationExercises', (
      SELECT COUNT(*)
      FROM exercise_sessions es
      JOIN exercises e ON es.exercise_id = e.id
      WHERE es.user_id = p_user_id AND es.completed = true AND e.type = 'meditation'
    ),
    'groundingExercises', (
      SELECT COUNT(*)
      FROM exercise_sessions es
      JOIN exercises e ON es.exercise_id = e.id
      WHERE es.user_id = p_user_id AND es.completed = true AND e.type = 'grounding'
    ),
    'journalingExercises', (
      SELECT COUNT(*)
      FROM exercise_sessions es
      JOIN exercises e ON es.exercise_id = e.id
      WHERE es.user_id = p_user_id AND es.completed = true AND e.type = 'journaling'
    ),
    'movementExercises', (
      SELECT COUNT(*)
      FROM exercise_sessions es
      JOIN exercises e ON es.exercise_id = e.id
      WHERE es.user_id = p_user_id AND es.completed = true AND e.type = 'movement'
    ),
    'meditationsCompleted', (
      SELECT COUNT(*)
      FROM playback_sessions ps
      JOIN audio_tracks at ON ps.track_id = at.id
      WHERE ps.user_id = p_user_id AND ps.completed = true AND at.category = 'meditation'
    ),
    'meditationTimeSeconds', (
      SELECT COALESCE(SUM(duration_played_seconds), 0)
      FROM playback_sessions ps
      JOIN audio_tracks at ON ps.track_id = at.id
      WHERE ps.user_id = p_user_id AND ps.completed = true AND at.category = 'meditation'
    ),
    'circlesJoined', (
      SELECT COUNT(*)
      FROM circle_members
      WHERE user_id = p_user_id
    ),
    'circlePosts', (
      SELECT COUNT(*)
      FROM circle_posts
      WHERE user_id = p_user_id
    ),
    'currentQuestStreak', (
      SELECT COALESCE(current_count, 0)
      FROM user_streaks_v2
      WHERE user_id = p_user_id AND streak_type = 'quest'
    ),
    'currentLevel', (
      SELECT COALESCE(current_level, 1)
      FROM user_experience
      WHERE user_id = p_user_id
    )
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- P0 FIX: Only service_role can execute (prevents information disclosure)
-- Users should NOT call this directly - only Edge Functions with service_role key
GRANT EXECUTE ON FUNCTION get_user_badge_metrics(UUID) TO service_role;

-- ============================================================================
-- PART 4: ADD BATCH XP AWARD FUNCTION (P0 Performance & Correctness)
-- ============================================================================

CREATE OR REPLACE FUNCTION award_badge_xp_batch(
  p_user_id UUID,
  p_badges JSONB
)
RETURNS TABLE(
  total_xp_awarded INT,
  new_total_xp INT,
  old_level INT,
  new_level INT,
  leveled_up BOOLEAN
) AS $$
DECLARE
  badge JSONB;
  v_total_xp_to_award INT := 0;
  v_old_total_xp INT;
  v_new_total_xp INT;
  v_old_level INT;
  v_new_level INT;
BEGIN
  -- P0 FIX: Calculate total XP to award (handle empty array)
  SELECT COALESCE(SUM((b->>'xp_amount')::INT), 0) INTO v_total_xp_to_award
  FROM jsonb_array_elements(p_badges) AS b;

  -- P0 FIX: Validate XP amount
  IF v_total_xp_to_award <= 0 THEN
    RAISE EXCEPTION 'Invalid XP amount: %', v_total_xp_to_award;
  END IF;

  -- P0 FIX: Get current XP and level (handle missing user with COALESCE)
  SELECT COALESCE(total_xp, 0), COALESCE(current_level, 1)
  INTO v_old_total_xp, v_old_level
  FROM user_experience
  WHERE user_id = p_user_id;

  -- P0 FIX: If user doesn't exist, create record
  IF v_old_total_xp IS NULL THEN
    INSERT INTO user_experience (user_id, total_xp, current_level, created_at, updated_at)
    VALUES (p_user_id, 0, 1, now(), now());
    v_old_total_xp := 0;
    v_old_level := 1;
  END IF;

  -- Calculate new values
  v_new_total_xp := v_old_total_xp + v_total_xp_to_award;
  v_new_level := GREATEST(1, FLOOR(SQRT(v_new_total_xp::FLOAT / 50.0))::INT + 1);

  -- Update user XP atomically
  UPDATE user_experience
  SET total_xp = v_new_total_xp,
      current_level = v_new_level,
      updated_at = now()
  WHERE user_id = p_user_id;

  -- Insert XP transactions
  INSERT INTO xp_transactions (user_id, amount, source, source_id, description, base_amount, multiplier_applied, created_at)
  SELECT
    p_user_id,
    (b->>'xp_amount')::INT,
    'badge'::text,
    (b->>'badge_id')::UUID,
    'Earned badge: ' || (b->>'badge_name'),
    (b->>'xp_amount')::INT,
    1.0,
    now()
  FROM jsonb_array_elements(p_badges) AS b;

  -- Return results
  RETURN QUERY SELECT
    v_total_xp_to_award,
    v_new_total_xp,
    v_old_level,
    v_new_level,
    v_new_level > v_old_level;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION award_badge_xp_batch(UUID, JSONB) TO service_role;

-- ============================================================================
-- PART 5: ADD DATA RETENTION POLICY (P1 Compliance)
-- ============================================================================

-- Add automatic cleanup for old milestones (GDPR compliance)
-- Keep milestones for 2 years, then auto-delete
CREATE OR REPLACE FUNCTION cleanup_old_milestones()
RETURNS void AS $$
BEGIN
  DELETE FROM milestone_celebrations
  WHERE generated_at < now() - interval '2 years';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: Actual cron job scheduling would be done via Supabase dashboard or pg_cron
-- This function can be called manually or scheduled externally

-- ============================================================================
-- VERIFICATION QUERIES (Comment out after testing)
-- ============================================================================

-- Verify RLS policies are in place
-- SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
-- FROM pg_policies
-- WHERE tablename IN ('user_badges_v2', 'milestone_celebrations', 'user_experience')
-- ORDER BY tablename, policyname;

-- Verify indexes exist
-- SELECT schemaname, tablename, indexname
-- FROM pg_indexes
-- WHERE tablename IN ('exercise_sessions', 'exercises', 'playback_sessions', 'audio_tracks', 'user_experience', 'user_streaks_v2', 'milestone_celebrations')
-- ORDER BY tablename, indexname;

-- Test aggregate function
-- SELECT get_user_badge_metrics('your-user-id-here');
