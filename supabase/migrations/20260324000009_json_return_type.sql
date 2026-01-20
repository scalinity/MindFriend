-- Complete rewrite with JSON return type to avoid TABLE/set issues
DROP FUNCTION IF EXISTS check_and_increment_ai_quota(UUID, BOOLEAN);

CREATE FUNCTION check_and_increment_ai_quota(
  p_user_id UUID,
  p_is_premium BOOLEAN DEFAULT FALSE
)
RETURNS JSON
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
  v_result JSON;
BEGIN
  -- Disable RLS
  SET LOCAL row_security = off;

  -- Check and create profile if needed
  SELECT COUNT(*) > 0 INTO v_profile_exists FROM profiles WHERE id = p_user_id;

  IF NOT v_profile_exists THEN
    INSERT INTO profiles (id, handle, display_name, email, daily_ai_used, daily_ai_quota, quota_reset_at)
    SELECT au.id, 'user_' || substr(md5(random()::text), 1, 8),
           COALESCE(au.raw_user_meta_data->>'full_name', 'MindFriend User'),
           au.email, 0, 10, NOW()
    FROM auth.users au WHERE au.id = p_user_id;

    INSERT INTO user_settings (user_id) VALUES (p_user_id) ON CONFLICT DO NOTHING;
    INSERT INTO user_stats (user_id) VALUES (p_user_id) ON CONFLICT DO NOTHING;
  END IF;

  -- Get quota info
  SELECT daily_ai_used, daily_ai_quota, quota_reset_at
  INTO v_quota_used, v_quota_limit, v_quota_reset_at
  FROM profiles WHERE id = p_user_id FOR UPDATE;

  -- Reset if new day
  IF DATE(v_quota_reset_at) < CURRENT_DATE THEN
    v_quota_used := 0;
    v_was_reset := TRUE;
    UPDATE profiles SET daily_ai_used = 0, quota_reset_at = NOW() WHERE id = p_user_id;
  END IF;

  -- Premium users
  IF p_is_premium THEN
    UPDATE profiles SET daily_ai_used = v_quota_used + 1 WHERE id = p_user_id;
    v_result := json_build_object('allowed', TRUE, 'quota_used', v_quota_used + 1, 'quota_limit', -1, 'was_reset', v_was_reset);
    RETURN v_result;
  END IF;

  -- Free users quota check
  IF v_quota_used >= v_quota_limit THEN
    v_result := json_build_object('allowed', FALSE, 'quota_used', v_quota_used, 'quota_limit', v_quota_limit, 'was_reset', v_was_reset);
    RETURN v_result;
  END IF;

  -- Increment
  UPDATE profiles SET daily_ai_used = v_quota_used + 1 WHERE id = p_user_id;
  v_result := json_build_object('allowed', TRUE, 'quota_used', v_quota_used + 1, 'quota_limit', v_quota_limit, 'was_reset', v_was_reset);
  RETURN v_result;
END;
$$;

-- Test will be done after triggers are disabled
