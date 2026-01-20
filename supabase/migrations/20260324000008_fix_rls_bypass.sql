-- Fix RLS bypass issue in quota function
DROP FUNCTION IF EXISTS check_and_increment_ai_quota(UUID, BOOLEAN);

CREATE FUNCTION check_and_increment_ai_quota(
  p_user_id UUID,
  p_is_premium BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
  allowed BOOLEAN,
  quota_used INT,
  quota_limit INT,
  was_reset BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quota_used INT;
  v_quota_limit INT;
  v_quota_reset_at TIMESTAMPTZ;
  v_was_reset BOOLEAN := FALSE;
  v_profile_exists BOOLEAN;
BEGIN
  -- Temporarily disable RLS for this function's operations
  SET LOCAL row_security = off;

  -- Check if profile exists
  SELECT EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) INTO v_profile_exists;

  -- If profile doesn't exist, create it
  IF NOT v_profile_exists THEN
    -- Create profile
    INSERT INTO profiles (
      id,
      handle,
      display_name,
      email,
      daily_ai_used,
      daily_ai_quota,
      quota_reset_at
    )
    SELECT
      au.id,
      'user_' || substr(md5(random()::text), 1, 8),
      COALESCE(au.raw_user_meta_data->>'full_name', 'MindFriend User'),
      au.email,
      0,
      10,
      NOW()
    FROM auth.users au
    WHERE au.id = p_user_id;

    -- Create settings and stats (RLS is already disabled)
    INSERT INTO user_settings (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO user_stats (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  END IF;

  -- Lock the row to prevent concurrent updates
  SELECT daily_ai_used, daily_ai_quota, quota_reset_at
  INTO v_quota_used, v_quota_limit, v_quota_reset_at
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  -- Check if quota needs reset (new day)
  IF DATE(v_quota_reset_at) < CURRENT_DATE THEN
    v_quota_used := 0;
    v_was_reset := TRUE;
    UPDATE profiles
    SET daily_ai_used = 0, quota_reset_at = NOW()
    WHERE id = p_user_id;
  END IF;

  -- Premium users always allowed
  IF p_is_premium THEN
    UPDATE profiles
    SET daily_ai_used = v_quota_used + 1
    WHERE id = p_user_id;

    RETURN QUERY SELECT TRUE, v_quota_used + 1, -1, v_was_reset;
    RETURN;
  END IF;

  -- Check quota for free users
  IF v_quota_used >= v_quota_limit THEN
    RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, v_was_reset;
    RETURN;
  END IF;

  -- Atomically increment quota
  UPDATE profiles
  SET daily_ai_used = v_quota_used + 1
  WHERE id = p_user_id;

  RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, v_was_reset;
END;
$$;

COMMENT ON FUNCTION check_and_increment_ai_quota IS 'Atomically checks and increments AI quota. Auto-creates missing profiles. Bypasses RLS.';
