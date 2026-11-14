-- Accepting a buddy code linked both people in the database and then told the invitee it failed.
-- accept_buddy_invite returned one composite row, which PostgREST sends as a JSON object, while
-- every released client (1.0.4, 1.0.5 and 2.0) decodes the response as an array of rows. The
-- function now returns SETOF, so PostgREST sends an array of the one accepted row.
--
-- The 1.x invite flow could leave a second pending row for the same contact with a different
-- code (the app inserted one, then send-buddy-invite inserted another when the email's letter
-- case differed). Either code still works; once one is accepted, the inviter's other pending
-- invites to that same contact expire so the pair is not linked twice.
--
-- The body is otherwise production's definition as of 13 November 2026.

DROP FUNCTION IF EXISTS public.accept_buddy_invite(text, uuid);

CREATE FUNCTION public.accept_buddy_invite(p_invite_code text, p_user_id uuid)
 RETURNS SETOF public.buddy_relationships
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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

  -- Other pending invites from the same inviter to the same contact are now settled.
  IF v_relationship.invitee_contact IS NOT NULL THEN
    UPDATE buddy_relationships SET status = 'expired'
    WHERE inviter_id = v_relationship.inviter_id
      AND status = 'pending'
      AND id <> v_relationship.id
      AND lower(invitee_contact) = lower(v_relationship.invitee_contact);
  END IF;

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

  RETURN NEXT v_relationship;
END;
$function$;

REVOKE ALL ON FUNCTION public.accept_buddy_invite(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_buddy_invite(text, uuid) TO authenticated, service_role;
