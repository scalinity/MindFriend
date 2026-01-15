-- Migration: join_circle_by_invite_code RPC
-- Issue #006: Circles Join/Create fix
-- SECURITY DEFINER allows bypassing RLS to join circles via invite code

CREATE OR REPLACE FUNCTION join_circle_by_invite_code(p_invite_code TEXT)
RETURNS TABLE (
  circle_id UUID,
  circle_name TEXT,
  member_count INT,
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_circle_id UUID;
  v_circle_name TEXT;
  v_max_members INT;
  v_current_members INT;
BEGIN
  -- Get the authenticated user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, NULL::TEXT, 0, false, 'Not authenticated'::TEXT;
    RETURN;
  END IF;

  -- Normalize invite code (uppercase, trim whitespace)
  p_invite_code := UPPER(TRIM(p_invite_code));

  -- Find the circle by invite code
  SELECT c.id, c.name, c.max_members
  INTO v_circle_id, v_circle_name, v_max_members
  FROM circles c
  WHERE c.invite_code = p_invite_code;

  IF v_circle_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, NULL::TEXT, 0, false, 'Invalid invite code'::TEXT;
    RETURN;
  END IF;

  -- Check if user is already a member
  IF EXISTS (
    SELECT 1 FROM circle_members cm
    WHERE cm.circle_id = v_circle_id AND cm.user_id = v_user_id
  ) THEN
    -- Already a member - return success with circle info
    SELECT COUNT(*) INTO v_current_members
    FROM circle_members cm WHERE cm.circle_id = v_circle_id;

    RETURN QUERY SELECT v_circle_id, v_circle_name, v_current_members::INT, true, 'Already a member'::TEXT;
    RETURN;
  END IF;

  -- Check member limit
  SELECT COUNT(*) INTO v_current_members
  FROM circle_members cm WHERE cm.circle_id = v_circle_id;

  IF v_current_members >= v_max_members THEN
    RETURN QUERY SELECT v_circle_id, v_circle_name, v_current_members::INT, false, 'Circle is full'::TEXT;
    RETURN;
  END IF;

  -- Add user as member
  INSERT INTO circle_members (circle_id, user_id, role, joined_at)
  VALUES (v_circle_id, v_user_id, 'member', NOW());

  -- Return success
  RETURN QUERY SELECT v_circle_id, v_circle_name, (v_current_members + 1)::INT, true, 'Joined successfully'::TEXT;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION join_circle_by_invite_code(TEXT) TO authenticated;
