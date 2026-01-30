-- Fix Free Tier Quota: Ensure 5 messages/day everywhere
-- This migration fixes all places where the old 20 or 10 message quota was hardcoded

-- 1. Update ALL free tier users to 5 messages (catch-all fix)
UPDATE profiles
SET daily_ai_quota = 5
WHERE subscription_tier IN ('free', NULL)
  AND daily_ai_quota > 5;

-- 2. Fix the check_and_increment_ai_quota function to use 5 for new profiles
CREATE OR REPLACE FUNCTION "public"."check_and_increment_ai_quota"("p_user_id" "uuid", "p_is_premium" boolean DEFAULT false) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
    -- Create new profile with 5 message daily quota (free tier)
    INSERT INTO profiles (id, handle, display_name, email, daily_ai_used, daily_ai_quota, quota_reset_at)
    SELECT au.id, 'user_' || substr(md5(random()::text), 1, 8),
           COALESCE(au.raw_user_meta_data->>'full_name', 'MindFriend User'),
           au.email, 0, 5, NOW()  -- Changed from 10 to 5
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

-- 3. Fix the family subscription expiry trigger to use 5 instead of 20
-- Find and update the handle_subscription_status_change function
CREATE OR REPLACE FUNCTION handle_family_subscription_expiry()
RETURNS TRIGGER AS $$
DECLARE
    v_member RECORD;
BEGIN
    -- Only handle family subscription expirations
    IF NEW.status = 'expired' AND OLD.status != 'expired' AND NEW.family_id IS NOT NULL THEN
        -- If admin subscription expires, downgrade all family members
        IF NEW.is_family_admin = true THEN
            -- Get all non-admin family members
            FOR v_member IN
                SELECT user_id
                FROM subscriptions
                WHERE family_id = NEW.family_id
                  AND is_family_admin = false
                  AND status = 'active'
            LOOP
                -- Expire member subscription
                UPDATE subscriptions
                SET status = 'expired',
                    expires_at = now(),
                    updated_at = now()
                WHERE user_id = v_member.user_id
                  AND family_id = NEW.family_id
                  AND is_family_admin = false;

                -- Downgrade member's profile to free tier with 5 messages/day
                UPDATE profiles
                SET subscription_tier = 'free',
                    daily_ai_quota = 5  -- Changed from 20 to 5
                WHERE id = v_member.user_id;

                -- Log the event
                INSERT INTO billing_events (event_type, user_id, family_id, subscription_id, payload)
                VALUES (
                    'subscription_expired',
                    v_member.user_id,
                    NEW.family_id,
                    NEW.id,
                    jsonb_build_object(
                        'reason', 'admin_subscription_expired',
                        'admin_user_id', NEW.user_id
                    )
                );
            END LOOP;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
