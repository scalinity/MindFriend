-- Preserve account-owned operations; privileged enrollment/voting already use validated Edge handlers.
BEGIN;
-- Both existing invite RPCs use this capacity, and buddy circles explicitly set two.
ALTER TABLE public.circles ADD COLUMN IF NOT EXISTS max_members integer NOT NULL DEFAULT 10 CHECK (max_members > 0);

CREATE OR REPLACE FUNCTION "public"."accept_buddy_invite"("p_invite_code" "text", "p_user_id" "uuid") RETURNS "public"."buddy_relationships"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_relationship buddy_relationships;
  v_circle_id UUID;
  v_inviter_name TEXT;
  v_xp_reward INT := 100;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
  -- Find and validate invite
  SELECT * INTO v_relationship
  FROM buddy_relationships
  WHERE invite_code = UPPER(p_invite_code)
    AND status = 'pending'
    AND expires_at > NOW()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite code';
  END IF;

  -- Prevent self-buddy
  IF v_relationship.inviter_id = p_user_id THEN
    RAISE EXCEPTION 'Cannot accept your own invite';
  END IF;

  -- Get inviter name for circle
  SELECT display_name INTO v_inviter_name
  FROM profiles
  WHERE id = v_relationship.inviter_id;

  -- Create buddy circle (2-person private circle)
  INSERT INTO circles (name, description, owner_id, max_members, invite_code)
  VALUES (
    'Buddies',
    'Your wellness buddy circle',
    v_relationship.inviter_id,
    2,
    'BUDDY-' || UPPER(SUBSTRING(MD5(v_relationship.id::TEXT) FROM 1 FOR 6))
  )
  RETURNING id INTO v_circle_id;

  -- Add both users as circle members
  INSERT INTO circle_members (circle_id, user_id, role, joined_at)
  VALUES
    (v_circle_id, v_relationship.inviter_id, 'owner', NOW()),
    (v_circle_id, p_user_id, 'member', NOW());

  -- Update buddy relationship
  UPDATE buddy_relationships SET
    invitee_id = p_user_id,
    status = 'accepted',
    accepted_at = NOW(),
    buddy_circle_id = v_circle_id
  WHERE id = v_relationship.id
  RETURNING * INTO v_relationship;

  -- Update invitee profile: link referral and give fresh start bonus
  UPDATE profiles SET
    referred_by = v_relationship.inviter_id,
    current_streak_days = 2  -- Fresh start bonus: Day 2 streak
  WHERE id = p_user_id;

  -- Update inviter profile: increment referral count and add XP
  UPDATE profiles SET
    total_referrals = total_referrals + 1
  WHERE id = v_relationship.inviter_id;

  -- XP belongs to user_stats. The accepted relationship authorizes this fixed reward.
  UPDATE user_stats SET
    xp_total = COALESCE(xp_total, 0) + v_xp_reward,
    xp_this_week = COALESCE(xp_this_week, 0) + v_xp_reward,
    level = (SELECT lt.level FROM level_thresholds lt
      WHERE lt.xp_required <= COALESCE(user_stats.xp_total, 0) + v_xp_reward
      ORDER BY lt.level DESC LIMIT 1),
    level_title = (SELECT lt.title FROM level_thresholds lt
      WHERE lt.xp_required <= COALESCE(user_stats.xp_total, 0) + v_xp_reward
      ORDER BY lt.level DESC LIMIT 1)
  WHERE user_id = v_relationship.inviter_id;

  -- Award "Good Friend" badge to inviter if first referral
  INSERT INTO user_badges (user_id, badge_id)
  SELECT v_relationship.inviter_id, b.id
  FROM badges b
  WHERE b.code = 'good_friend'
  ON CONFLICT (user_id, badge_id) DO NOTHING;

  RETURN v_relationship;
END;
$$;
REVOKE ALL ON FUNCTION public.accept_buddy_invite(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_buddy_invite(text,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."award_xp"("p_user_id" "uuid", "p_amount" integer, "p_activity_type" "text", "p_skill_type" "text" DEFAULT NULL::"text") RETURNS TABLE("new_xp" integer, "new_level" integer, "new_title" "text", "level_up" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_current_xp INT;
  v_new_xp INT;
  v_current_level INT;
  v_new_level INT;
  v_new_title TEXT;
  v_level_changed BOOLEAN := FALSE;
  v_skill_xp INT;
  v_skill_level INT;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
  -- Lock the row to prevent race conditions
  SELECT xp_total, level INTO v_current_xp, v_current_level
  FROM user_stats
  WHERE user_id = p_user_id
  FOR UPDATE;

  -- Initialize if null (shouldn't happen due to trigger, but defensive)
  IF v_current_xp IS NULL THEN
    v_current_xp := 0;
    v_current_level := 1;
  END IF;

  -- Calculate new XP
  v_new_xp := v_current_xp + p_amount;

  -- Determine new level from thresholds
  SELECT lt.level, lt.title INTO v_new_level, v_new_title
  FROM level_thresholds lt
  WHERE lt.xp_required <= v_new_xp
  ORDER BY lt.level DESC
  LIMIT 1;

  -- Check for level up
  v_level_changed := v_new_level > v_current_level;

  -- Update user stats
  UPDATE user_stats
  SET xp_total = v_new_xp,
      xp_this_week = xp_this_week + p_amount,
      level = v_new_level,
      level_title = v_new_title,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Update skill progress if skill type provided
  IF p_skill_type IS NOT NULL AND p_skill_type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement') THEN
    -- Insert or update skill progress
    INSERT INTO skill_progress (user_id, skill_type, xp, exercises_completed)
    VALUES (p_user_id, p_skill_type, p_amount, 1)
    ON CONFLICT (user_id, skill_type) DO UPDATE
    SET xp = skill_progress.xp + EXCLUDED.xp,
        exercises_completed = skill_progress.exercises_completed + 1,
        updated_at = NOW();

    -- Get updated skill XP to calculate level
    SELECT xp INTO v_skill_xp
    FROM skill_progress
    WHERE user_id = p_user_id AND skill_type = p_skill_type;

    -- Determine skill level
    SELECT st.level INTO v_skill_level
    FROM skill_thresholds st
    WHERE st.xp_required <= v_skill_xp
    ORDER BY st.level DESC
    LIMIT 1;

    -- Update skill level
    UPDATE skill_progress
    SET level = v_skill_level
    WHERE user_id = p_user_id AND skill_type = p_skill_type;
  END IF;

  RETURN QUERY SELECT v_new_xp, v_new_level, v_new_title, v_level_changed;
END;
$$;
REVOKE ALL ON FUNCTION public.award_xp(uuid,integer,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_xp(uuid,integer,text,text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."perform_fresh_start"("p_user_id" "uuid") RETURNS TABLE("success" boolean, "new_streak" integer, "fresh_start_bonus" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_fresh_start_bonus INT := 2; -- Start at day 2 as bonus
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
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
$$;
REVOKE ALL ON FUNCTION public.perform_fresh_start(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.perform_fresh_start(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.enroll_user_in_pathway(uuid,uuid,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enroll_user_in_pathway(uuid,uuid,jsonb,text) TO service_role;
ALTER FUNCTION public.enroll_user_in_pathway(uuid,uuid,jsonb,text) SET search_path TO pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION public.upsert_strategy_vote(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_strategy_vote(uuid,uuid,text) TO service_role;
ALTER FUNCTION public.upsert_strategy_vote(uuid,uuid,text) SET search_path TO pg_catalog, public, pg_temp;

COMMIT;
