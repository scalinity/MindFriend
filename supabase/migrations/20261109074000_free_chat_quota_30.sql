-- Free accounts get 30 AI chat messages per server (UTC) day. Every writer
-- of the free limit uses the same value: sign-up, lazy profile creation, the
-- insert guard, entitlement refresh, family expiry and the quota admission's
-- own profile creation. Bodies match production except for the limit, and
-- the admission also reports the UTC day it counted the message in
-- (quota_day), so clients attribute a late or replayed receipt to that day.
BEGIN;

ALTER TABLE public.profiles ALTER COLUMN daily_ai_quota SET DEFAULT 30;

CREATE OR REPLACE FUNCTION public.enforce_profiles_insert_defaults()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Only apply restrictions to authenticated users creating their own profiles
  -- Service role and admin operations bypass this
  IF (SELECT COALESCE(auth.role(), 'unknown') = 'authenticated') THEN
    -- Force default values for revenue-critical columns
    -- These can only be set by Edge Functions/service role after purchase verification
    NEW.subscription_tier := 'free';
    NEW.daily_ai_quota := 30;
    NEW.daily_ai_used := 0;
    NEW.quota_reset_at := NOW();
    NEW.premium_badge := FALSE;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    random_handle TEXT;
BEGIN
    -- Generate a random handle
    random_handle := 'user_' || substr(md5(random()::text), 1, 8);

    -- Create profile with ALL required fields
    INSERT INTO public.profiles (
        id,
        email,
        display_name,
        handle,
        timezone,
        subscription_tier,
        daily_ai_used,
        daily_ai_quota,
        quota_reset_at,
        created_at,
        updated_at
    )
    VALUES (
        new.id,
        new.email,
        COALESCE(
            new.raw_user_meta_data->>'full_name',
            new.raw_user_meta_data->>'name',
            split_part(new.email, '@', 1)
        ),
        random_handle,
        'UTC',  -- Default timezone
        'free', -- Default subscription tier
        0,
        30,
        NOW(),
        NOW(),
        NOW()
    );

    -- Create user_settings with defaults
    INSERT INTO public.user_settings (user_id)
    VALUES (new.id)
    ON CONFLICT (user_id) DO NOTHING;

    -- Create user_stats with defaults
    INSERT INTO public.user_stats (user_id)
    VALUES (new.id)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_profile_exists(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_email TEXT;
  v_user_metadata JSONB;
  random_handle TEXT;
BEGIN
  -- Check if profile already exists
  IF EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RETURN;
  END IF;

  -- Get user info from auth.users
  SELECT email, raw_user_meta_data
  INTO v_user_email, v_user_metadata
  FROM auth.users
  WHERE id = p_user_id;

  -- If user doesn't exist in auth.users, we can't create profile
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % does not exist in auth.users', p_user_id;
  END IF;

  -- Generate random handle
  random_handle := 'user_' || substr(md5(random()::text), 1, 8);

  -- Create profile with defaults
  INSERT INTO profiles (
    id,
    handle,
    display_name,
    email,
    daily_ai_used,
    daily_ai_quota,
    quota_reset_at
  )
  VALUES (
    p_user_id,
    random_handle,
    COALESCE(v_user_metadata->>'full_name', 'MindFriend User'),
    v_user_email,
    0,  -- Start with 0 quota used
    30, -- Default free tier quota
    NOW() -- Reset time is now
  );

  -- Create settings if missing
  INSERT INTO user_settings (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- Create stats if missing
  INSERT INTO user_stats (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- Log this for monitoring
  RAISE NOTICE 'Created missing profile for user %', p_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_and_increment_ai_quota(p_user_id uuid, p_is_premium boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- Create new profile with the free daily quota
    INSERT INTO profiles (id, handle, display_name, email, daily_ai_used, daily_ai_quota, quota_reset_at)
    SELECT au.id, 'user_' || substr(md5(random()::text), 1, 8),
           COALESCE(au.raw_user_meta_data->>'full_name', 'MindFriend User'),
           au.email, 0, 30, NOW()
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
    v_result := json_build_object('allowed', TRUE, 'quota_used', v_quota_used + 1, 'quota_limit', -1, 'was_reset', v_was_reset, 'quota_day', CURRENT_DATE);
    RETURN v_result;
  END IF;

  -- Free users quota check
  IF v_quota_used >= v_quota_limit THEN
    v_result := json_build_object('allowed', FALSE, 'quota_used', v_quota_used, 'quota_limit', v_quota_limit, 'was_reset', v_was_reset, 'quota_day', CURRENT_DATE);
    RETURN v_result;
  END IF;

  -- Increment
  UPDATE profiles SET daily_ai_used = v_quota_used + 1 WHERE id = p_user_id;
  v_result := json_build_object('allowed', TRUE, 'quota_used', v_quota_used + 1, 'quota_limit', v_quota_limit, 'was_reset', v_was_reset, 'quota_day', CURRENT_DATE);
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_user_entitlement(p_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_premium boolean;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Missing entitlement owner' USING ERRCODE = '22023';
  END IF;
  -- Same per-user ordering as organization admission; do not rewrite purchases.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  v_premium := public.has_current_premium_access(p_user_id);
  UPDATE public.profiles SET
    subscription_tier = (CASE WHEN v_premium THEN 'premium' ELSE 'free' END)::public.subscription_tier,
    daily_ai_quota = CASE WHEN v_premium THEN -1 ELSE 30 END,
    premium_badge = CASE WHEN v_premium THEN premium_badge ELSE NULL END
  WHERE id = p_user_id AND (subscription_tier, daily_ai_quota,
    CASE WHEN v_premium THEN NULL ELSE premium_badge END)
    IS DISTINCT FROM ((CASE WHEN v_premium THEN 'premium' ELSE 'free' END)::public.subscription_tier,
      CASE WHEN v_premium THEN -1 ELSE 30 END, NULL::text);
  RETURN v_premium;
END $function$;

CREATE OR REPLACE FUNCTION public.revoke_family_premium_on_expiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_member record; v_premium boolean; v_changed integer;
BEGIN
  IF NEW.is_family_admin = true AND NEW.family_id IS NOT NULL
     AND OLD.status IN ('active', 'grace_period')
     AND (NEW.status IN ('expired', 'cancelled') OR NEW.expires_at <= now())
     AND (OLD.status, OLD.expires_at) IS DISTINCT FROM (NEW.status, NEW.expires_at) THEN
    -- Do not take member advisory/family-row locks after the admin row is locked:
    -- family admission takes those locks before its admin subscription lock.
    FOR v_member IN SELECT user_id FROM public.family_members
      WHERE family_id = NEW.family_id AND user_id <> NEW.user_id AND status = 'active'
    LOOP
      UPDATE public.subscriptions SET status = 'expired', expires_at = now(), updated_at = now()
        WHERE user_id = v_member.user_id AND family_id = NEW.family_id AND is_family_admin = false
          AND plan_type IN ('family', 'couples') AND status IN ('active', 'grace_period')
          AND original_transaction_id IN (
            'family-' || NEW.family_id::text || '-' || v_member.user_id::text,
            'family-' || OLD.original_transaction_id
          );
      GET DIAGNOSTICS v_changed = ROW_COUNT;
      v_premium := public.compute_current_premium_access(v_member.user_id);
      UPDATE public.profiles SET
        subscription_tier = (CASE WHEN v_premium THEN 'premium' ELSE 'free' END)::public.subscription_tier,
        daily_ai_quota = CASE WHEN v_premium THEN -1 ELSE 30 END,
        premium_badge = CASE WHEN v_premium THEN premium_badge ELSE NULL END
        WHERE id = v_member.user_id;
      IF v_changed > 0 THEN
        INSERT INTO public.billing_events(event_type,user_id,family_id,subscription_id,payload)
        VALUES ('subscription_expired',v_member.user_id,NEW.family_id,NEW.id,
          jsonb_build_object('reason','admin_subscription_expired','admin_user_id',NEW.user_id));
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END $function$;

-- Existing free accounts move to the new limit; premium (-1) is unchanged.
UPDATE public.profiles SET daily_ai_quota = 30
  WHERE subscription_tier = 'free' AND daily_ai_quota IS DISTINCT FROM 30;

COMMIT;
