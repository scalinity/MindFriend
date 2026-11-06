-- Manual database rollback: production approval is required.

-- This restores known vulnerable legacy grants/guards. Prefer an app/code rollback

-- while retaining security fixes. New request receipts and budget records are kept.

BEGIN;

CREATE OR REPLACE FUNCTION public.add_family_member(p_family_id uuid, p_user_id uuid, p_role text DEFAULT 'child'::text, p_nickname text DEFAULT NULL::text, p_birth_date text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_family_record RECORD;
  v_existing_member RECORD;
  v_member_record RECORD;
  v_error_code TEXT;
BEGIN
  -- Step 0: CRITICAL SECURITY CHECK - Users can only add themselves to families
  -- Prevents IDOR privilege escalation where user A adds user B without consent
  IF p_user_id != auth.uid() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Unauthorized: can only add yourself to a family',
      'code', 'UNAUTHORIZED'
    );
  END IF;

  -- Step 1: Lock family_groups row for atomic check-and-insert
  -- FOR UPDATE prevents concurrent modifications to this family
  SELECT id, max_members
  INTO v_family_record
  FROM family_groups
  WHERE id = p_family_id
  FOR UPDATE;

  -- Step 2: Family not found
  IF v_family_record IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Family not found',
      'code', 'FAMILY_NOT_FOUND'
    );
  END IF;

  -- Step 3: Check if user is already a member (prevent duplicates)
  SELECT id INTO v_existing_member
  FROM family_members
  WHERE family_id = p_family_id
    AND user_id = p_user_id
    AND status = 'active'
  LIMIT 1;

  IF v_existing_member IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User is already a member of this family',
      'code', 'ALREADY_MEMBER'
    );
  END IF;

  -- Step 4: Check member limit (atomic check within same transaction)
  -- Count active members and verify against max_members
  -- Using COUNT(*) LIMIT 1 pattern prevents unnecessary full table scan
  IF (
    SELECT COUNT(*)
    FROM family_members
    WHERE family_id = p_family_id
      AND status = 'active'
  ) >= COALESCE(v_family_record.max_members, 6) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Family has reached maximum members',
      'code', 'MEMBER_LIMIT_EXCEEDED'
    );
  END IF;

  -- Step 5: Insert new family member (atomic - within same transaction with lock held)
  INSERT INTO family_members (
    family_id,
    user_id,
    role,
    nickname,
    birth_date,
    status,
    joined_at,
    created_at,
    updated_at
  )
  VALUES (
    p_family_id,
    p_user_id,
    p_role,
    p_nickname,
    CASE WHEN p_birth_date IS NOT NULL AND p_birth_date != '' THEN p_birth_date::DATE ELSE NULL END,
    'active',
    NOW(),
    NOW(),
    NOW()
  )
  RETURNING * INTO v_member_record;

  -- Step 6: Return success with member details
  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_member_record.id,
    'user_id', v_member_record.user_id,
    'family_id', v_member_record.family_id,
    'role', v_member_record.role,
    'joined_at', v_member_record.joined_at
  );

EXCEPTION WHEN OTHERS THEN
  -- Log unexpected errors and return generic failure
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to add family member',
    'code', 'RPC_ERROR'
  );
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) TO "anon";

GRANT EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) TO "service_role";

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
$function$
;

REVOKE EXECUTE ON FUNCTION public.check_and_increment_ai_quota(uuid,boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.check_and_increment_ai_quota(uuid,boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.check_and_increment_ai_quota(uuid,boolean) TO "anon";

GRANT EXECUTE ON FUNCTION public.check_and_increment_ai_quota(uuid,boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.check_and_increment_ai_quota(uuid,boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.check_and_increment_synthesis_quota(p_user_id uuid, p_is_premium boolean DEFAULT false)
 RETURNS TABLE(allowed boolean, quota_used integer, quota_limit integer, was_reset boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_quota_used INT;
    v_quota_limit INT;
BEGIN
    -- Set quota limit based on tier
    -- Free tier is blocked at Edge Function level, but enforce here too as safety
    IF p_is_premium THEN
        v_quota_limit := 20;  -- Premium: 20 synthesis requests per day (cost control)
    ELSE
        v_quota_limit := 0;   -- Free: 0 (blocked at Edge Function, this is fallback)
    END IF;

    -- Count today's synthesis requests
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE;

    -- Check if user has exceeded quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Quota not exceeded, record this request and allow
    INSERT INTO synthesis_requests (user_id) VALUES (p_user_id);

    RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, FALSE;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.check_and_increment_synthesis_quota(p_user_id uuid, p_is_premium boolean DEFAULT false, p_character_count integer DEFAULT 0)
 RETURNS TABLE(allowed boolean, quota_used integer, quota_limit integer, was_reset boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_quota_used INT;
    v_quota_limit INT;
BEGIN
    -- Set quota limit based on tier
    IF p_is_premium THEN
        v_quota_limit := 10;  -- Premium: 10/day (reduced from 20, monthly budget is primary control)
    ELSE
        v_quota_limit := 0;   -- Free: blocked at Edge Function level
    END IF;

    -- Count today's synthesis requests
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE;

    -- Check if user has exceeded daily quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Record this request with character count
    INSERT INTO synthesis_requests (user_id, character_count)
    VALUES (p_user_id, p_character_count);

    RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, FALSE;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean,integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean,integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean,integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.check_capacity_rate_limit(p_user_id uuid, p_window_ms bigint, p_max_requests integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_rate_limit RECORD;
    v_now TIMESTAMPTZ := now();
    v_window_age_ms BIGINT;
    v_reset_at TIMESTAMPTZ;
    v_remaining INT;
    v_calling_uid UUID;
BEGIN
    -- Get the calling user ID (can be NULL for service role)
    v_calling_uid := auth.uid();

    -- SECURITY: Verify caller is either checking their own rate limit OR using service role
    -- Service role has NULL auth.uid() but elevated permissions
    IF v_calling_uid IS NOT NULL AND v_calling_uid != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: Can only check own rate limit';
    END IF;

    -- Atomic SELECT FOR UPDATE to prevent race conditions
    SELECT * INTO v_rate_limit
    FROM capacity_rate_limits
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- First request: create record
        INSERT INTO capacity_rate_limits (user_id, request_count, window_start)
        VALUES (p_user_id, 1, v_now);

        v_reset_at := v_now + (p_window_ms || ' milliseconds')::INTERVAL;
        v_remaining := p_max_requests - 1;

        RETURN json_build_object(
            'allowed', true,
            'resetAt', v_reset_at,
            'remaining', v_remaining
        );
    END IF;

    -- Calculate window age
    v_window_age_ms := EXTRACT(EPOCH FROM (v_now - v_rate_limit.window_start)) * 1000;

    IF v_window_age_ms < p_window_ms THEN
        -- Within current window
        IF v_rate_limit.request_count >= p_max_requests THEN
            -- Rate limit exceeded
            v_reset_at := v_rate_limit.window_start + (p_window_ms || ' milliseconds')::INTERVAL;
            RETURN json_build_object(
                'allowed', false,
                'resetAt', v_reset_at,
                'remaining', 0
            );
        ELSE
            -- Increment count
            UPDATE capacity_rate_limits
            SET request_count = request_count + 1
            WHERE user_id = p_user_id;

            v_reset_at := v_rate_limit.window_start + (p_window_ms || ' milliseconds')::INTERVAL;
            v_remaining := p_max_requests - v_rate_limit.request_count - 1;

            RETURN json_build_object(
                'allowed', true,
                'resetAt', v_reset_at,
                'remaining', v_remaining
            );
        END IF;
    ELSE
        -- Window expired: reset
        UPDATE capacity_rate_limits
        SET request_count = 1, window_start = v_now
        WHERE user_id = p_user_id;

        v_reset_at := v_now + (p_window_ms || ' milliseconds')::INTERVAL;
        v_remaining := p_max_requests - 1;

        RETURN json_build_object(
            'allowed', true,
            'resetAt', v_reset_at,
            'remaining', v_remaining
        );
    END IF;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) TO "anon";

GRANT EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) TO "service_role";

-- Exact original check_rate_limit body from 20260122000000_remote_schema.sql.
-- The captured pre-restoration ACL below grants PUBLIC and service_role execution.
CREATE OR REPLACE FUNCTION public.check_rate_limit(p_user_id uuid, p_endpoint text, p_window_start timestamp with time zone, p_max_requests integer, p_window_ms integer)
 RETURNS TABLE(allowed boolean, remaining integer, reset_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT;
  v_window_start TIMESTAMPTZ;
  v_reset_at TIMESTAMPTZ;
BEGIN
  SELECT request_count, window_start
  INTO v_count, v_window_start
  FROM rate_limits
  WHERE user_id = p_user_id AND endpoint = p_endpoint
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO rate_limits (user_id, endpoint, request_count, window_start)
    VALUES (p_user_id, p_endpoint, 1, NOW())
    ON CONFLICT (user_id, endpoint) DO UPDATE
    SET request_count = 1, window_start = NOW();

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  IF v_window_start < p_window_start THEN
    UPDATE rate_limits
    SET request_count = 1, window_start = NOW()
    WHERE user_id = p_user_id AND endpoint = p_endpoint;

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  v_reset_at := v_window_start + (p_window_ms || ' milliseconds')::interval;

  IF v_count >= p_max_requests THEN
    RETURN QUERY SELECT FALSE, 0, v_reset_at;
    RETURN;
  END IF;

  UPDATE rate_limits
  SET request_count = v_count + 1
  WHERE user_id = p_user_id AND endpoint = p_endpoint;

  RETURN QUERY SELECT TRUE, p_max_requests - v_count - 1, v_reset_at;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.claim_family_seat(p_family_id uuid, p_user_id uuid, p_invited_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_admin_sub RECORD;
    v_existing_member RECORD;
    v_seats_available INT;
    v_result JSONB;
BEGIN
    -- Lock the admin subscription row for update to prevent race conditions
    SELECT *
    INTO v_admin_sub
    FROM subscriptions
    WHERE family_id = p_family_id
      AND is_family_admin = true
      AND status = 'active'
    FOR UPDATE;

    IF v_admin_sub IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Family subscription not found or inactive',
            'code', 'NO_ACTIVE_SUBSCRIPTION'
        );
    END IF;

    -- Calculate available seats
    v_seats_available := v_admin_sub.seats_total - v_admin_sub.seats_used;

    IF v_seats_available <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No seats available in this family plan',
            'code', 'NO_SEATS_AVAILABLE',
            'seats_used', v_admin_sub.seats_used,
            'seats_total', v_admin_sub.seats_total
        );
    END IF;

    -- Check if user is already an active member
    SELECT *
    INTO v_existing_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id
      AND status = 'active';

    IF v_existing_member IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User is already an active member of this family',
            'code', 'ALREADY_MEMBER'
        );
    END IF;

    -- Atomically increment seats_used
    UPDATE subscriptions
    SET seats_used = seats_used + 1,
        updated_at = now()
    WHERE id = v_admin_sub.id
      AND seats_used < seats_total;  -- Double-check constraint

    IF NOT FOUND THEN
        -- Race condition occurred - another request claimed the last seat
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Seat was claimed by another request',
            'code', 'SEAT_RACE_CONDITION'
        );
    END IF;

    -- Check for existing inactive member to reactivate
    SELECT *
    INTO v_existing_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id;

    IF v_existing_member IS NOT NULL THEN
        -- Reactivate existing membership
        UPDATE family_members
        SET status = 'active',
            joined_at = now(),
            removed_at = NULL
        WHERE id = v_existing_member.id;
    ELSE
        -- Create new family member
        INSERT INTO family_members (family_id, user_id, invited_email, status, joined_at)
        VALUES (p_family_id, p_user_id, p_invited_email, 'active', now());
    END IF;

    -- Log the event
    INSERT INTO billing_events (event_type, user_id, family_id, payload)
    VALUES (
        'family_seat_claimed',
        p_user_id,
        p_family_id,
        jsonb_build_object(
            'seats_used', v_admin_sub.seats_used + 1,
            'seats_total', v_admin_sub.seats_total,
            'admin_subscription_id', v_admin_sub.id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Seat claimed successfully',
        'seats_used', v_admin_sub.seats_used + 1,
        'seats_total', v_admin_sub.seats_total,
        'admin_subscription_id', v_admin_sub.id
    );
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) TO "anon";

GRANT EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) TO "service_role";

CREATE OR REPLACE FUNCTION public.create_voice_session(p_user_id uuid, p_voice text DEFAULT 'ara'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_session_id UUID;
BEGIN
    INSERT INTO voice_sessions (user_id, voice_used, started_at)
    VALUES (p_user_id, p_voice, NOW())
    RETURNING id INTO v_session_id;

    RETURN v_session_id;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.create_voice_session(uuid,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.create_voice_session(uuid,text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_voice_session(uuid,text) TO "anon";

GRANT EXECUTE ON FUNCTION public.create_voice_session(uuid,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.create_voice_session(uuid,text) TO "service_role";

CREATE OR REPLACE FUNCTION public.end_voice_session(p_session_id uuid, p_duration_seconds integer, p_messages_count integer DEFAULT 0, p_was_quota_limited boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID;
    v_duration_minutes FLOAT;
    v_period_start DATE;
BEGIN
    -- Get user ID from session
    SELECT user_id INTO v_user_id
    FROM voice_sessions
    WHERE id = p_session_id;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Calculate minutes
    v_duration_minutes := p_duration_seconds / 60.0;
    v_period_start := DATE_TRUNC('month', NOW())::DATE;

    -- Update session record
    UPDATE voice_sessions
    SET
        ended_at = NOW(),
        duration_seconds = p_duration_seconds,
        messages_count = p_messages_count,
        was_quota_limited = p_was_quota_limited
    WHERE id = p_session_id;

    -- Increment usage
    PERFORM increment_voice_usage(v_user_id, v_duration_minutes, v_period_start);
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.end_voice_session(uuid,integer,integer,boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.end_voice_session(uuid,integer,integer,boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.end_voice_session(uuid,integer,integer,boolean) TO "anon";

GRANT EXECUTE ON FUNCTION public.end_voice_session(uuid,integer,integer,boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.end_voice_session(uuid,integer,integer,boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_cron_secret()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_secret TEXT;
BEGIN
    -- Try to get from vault
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'cron_secret'
    LIMIT 1;

    RETURN COALESCE(v_secret, '');
EXCEPTION
    WHEN OTHERS THEN
        RETURN '';
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.get_cron_secret() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_cron_secret() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_cron_secret() TO "anon";

GRANT EXECUTE ON FUNCTION public.get_cron_secret() TO "authenticated";

GRANT EXECUTE ON FUNCTION public.get_cron_secret() TO "service_role";

CREATE OR REPLACE FUNCTION public.get_moods_for_pattern_analysis(p_user_id uuid, p_weeks integer DEFAULT 4)
 RETURNS TABLE(mood_score integer, created_at timestamp with time zone, day_of_week integer, hour_of_day integer, source text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    m.mood_score,
    m.created_at,
    EXTRACT(DOW FROM m.created_at)::int as day_of_week,
    EXTRACT(HOUR FROM m.created_at)::int as hour_of_day,
    m.source
  FROM moods m
  WHERE m.user_id = p_user_id
    AND m.created_at >= NOW() - (p_weeks || ' weeks')::interval
  ORDER BY m.created_at DESC;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) TO "anon";

GRANT EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_pending_notifications(p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, user_id uuid, notification_type text, title text, body text, deep_link text, metadata jsonb, push_token text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    nh.id,
    nh.user_id,
    nh.notification_type,
    nh.title,
    nh.body,
    nh.deep_link,
    nh.metadata,
    pt.token AS push_token
  FROM notification_history nh
  INNER JOIN push_tokens pt ON pt.user_id = nh.user_id
  INNER JOIN profiles p ON p.id = nh.user_id
  INNER JOIN user_settings us ON us.user_id = nh.user_id
  WHERE
    -- Is pending
    nh.status = 'pending'
    -- Scheduled time has passed
    AND nh.scheduled_for <= NOW()
    -- Not currently in quiet hours
    AND NOT public.is_in_quiet_hours(
      EXTRACT(HOUR FROM NOW() AT TIME ZONE p.timezone)::int,
      us.quiet_hours_start_local,
      us.quiet_hours_end_local
    )
  ORDER BY nh.scheduled_for ASC
  LIMIT p_limit;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.get_pending_notifications(integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_pending_notifications(integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_pending_notifications(integer) TO "anon";

GRANT EXECUTE ON FUNCTION public.get_pending_notifications(integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.get_pending_notifications(integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_streak_at_risk_users(p_target_hour integer)
 RETURNS TABLE(user_id uuid, current_streak_days integer, timezone text, push_token text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.current_streak_days,
    p.timezone,
    pt.token AS push_token
  FROM profiles p
  -- Join to push tokens to get device token
  INNER JOIN push_tokens pt ON pt.user_id = p.id
  -- Join to user settings to check notification preference
  INNER JOIN user_settings us ON us.user_id = p.id
  WHERE
    -- Has an active streak
    p.current_streak_days > 0
    -- Streak risk notifications enabled
    AND us.notify_streak_risk = true
    -- Current hour in user's timezone matches target hour
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE p.timezone) = p_target_hour
    -- Hasn't completed a quest today (in their timezone)
    AND NOT EXISTS (
      SELECT 1 FROM quests q
      WHERE q.user_id = p.id
        AND q.status = 'completed'
        AND q.local_date = (NOW() AT TIME ZONE p.timezone)::date::text
    )
    -- Hasn't already received a streak_risk notification today
    AND NOT EXISTS (
      SELECT 1 FROM notification_history nh
      WHERE nh.user_id = p.id
        AND nh.notification_type = 'streak_risk'
        AND nh.created_date = CURRENT_DATE
        AND nh.metadata->>'target_hour' = p_target_hour::text
    );
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) TO "anon";

GRANT EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_stress_signature(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result JSONB;
  v_pattern_count INT;
BEGIN
  -- Verify caller owns the data
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access patterns for other users';
  END IF;

  -- Rate limiting check
  IF NOT check_signature_fetch_rate_limit(p_user_id) THEN
    RAISE EXCEPTION 'Rate limit exceeded: Maximum 10 requests per minute';
  END IF;

  -- Count matching patterns separately for accurate audit log
  SELECT COUNT(*)
  INTO v_pattern_count
  FROM user_patterns
  WHERE user_id = p_user_id
    AND pattern_type LIKE 'signature_%'
    AND confidence >= 0.5
    AND is_active = TRUE;

  -- Aggregate patterns into signature format
  SELECT jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'category', pattern_key,
        'type', pattern_type,
        'confidenceScore', confidence,
        'evidenceCount', evidence_count,
        'firstDetected', first_detected_at,
        'lastDetected', last_confirmed_at,
        'data', pattern_data
      )
      ORDER BY confidence DESC, evidence_count DESC
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM user_patterns
  WHERE user_id = p_user_id
    AND pattern_type LIKE 'signature_%'
    AND confidence >= 0.5
    AND is_active = TRUE;

  -- Audit log (anonymized - only count, no pattern details)
  INSERT INTO pattern_access_audit (user_id, access_type, pattern_count)
  VALUES (p_user_id, 'signature_fetch', v_pattern_count);

  RETURN COALESCE(v_result, jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', '[]'::jsonb
  ));
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.get_stress_signature(uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_stress_signature(uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_stress_signature(uuid) TO "anon";

GRANT EXECUTE ON FUNCTION public.get_stress_signature(uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.get_stress_signature(uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.get_users_for_weekly_summary()
 RETURNS TABLE(user_id uuid, push_token text, timezone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    pt.token AS push_token,
    p.timezone
  FROM profiles p
  INNER JOIN push_tokens pt ON pt.user_id = p.id
  INNER JOIN user_settings us ON us.user_id = p.id
  WHERE
    -- Weekly summary enabled
    us.notify_weekly_summary = true
    -- It's Sunday 6 PM in their timezone
    AND EXTRACT(DOW FROM NOW() AT TIME ZONE p.timezone) = 0  -- Sunday
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE p.timezone) = 18;  -- 6 PM
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.get_users_for_weekly_summary() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_users_for_weekly_summary() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_users_for_weekly_summary() TO "anon";

GRANT EXECUTE ON FUNCTION public.get_users_for_weekly_summary() TO "authenticated";

GRANT EXECUTE ON FUNCTION public.get_users_for_weekly_summary() TO "service_role";

CREATE OR REPLACE FUNCTION public.increment_voice_usage(p_user_id uuid, p_minutes double precision, p_period_start date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    INSERT INTO voice_usage (user_id, period_start, minutes_used, last_session_at)
    VALUES (p_user_id, p_period_start, p_minutes, NOW())
    ON CONFLICT (user_id, period_start)
    DO UPDATE SET
        minutes_used = voice_usage.minutes_used + p_minutes,
        last_session_at = NOW(),
        updated_at = NOW();
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.increment_voice_usage(uuid,double precision,date) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.increment_voice_usage(uuid,double precision,date) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.increment_voice_usage(uuid,double precision,date) TO "anon";

GRANT EXECUTE ON FUNCTION public.increment_voice_usage(uuid,double precision,date) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.increment_voice_usage(uuid,double precision,date) TO "service_role";

CREATE OR REPLACE FUNCTION public.is_moderator()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER COST 10
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN COALESCE(
        (SELECT (auth.jwt() -> 'user_metadata' ->> 'role') = 'moderator'),
        false
    );
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.is_moderator() FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.is_moderator() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_moderator() TO "anon";

GRANT EXECUTE ON FUNCTION public.is_moderator() TO "authenticated";

GRANT EXECUTE ON FUNCTION public.is_moderator() TO "service_role";

CREATE OR REPLACE FUNCTION public.release_family_seat(p_family_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_admin_sub RECORD;
    v_member RECORD;
BEGIN
    -- Lock the admin subscription row for update
    SELECT *
    INTO v_admin_sub
    FROM subscriptions
    WHERE family_id = p_family_id
      AND is_family_admin = true
    FOR UPDATE;

    IF v_admin_sub IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Family subscription not found',
            'code', 'NO_SUBSCRIPTION'
        );
    END IF;

    -- Find the member
    SELECT *
    INTO v_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id
      AND status = 'active';

    IF v_member IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User is not an active member of this family',
            'code', 'NOT_A_MEMBER'
        );
    END IF;

    -- Mark member as removed
    UPDATE family_members
    SET status = 'removed',
        removed_at = now()
    WHERE id = v_member.id;

    -- Decrement seats_used (but don't go below 1 - admin always counts)
    UPDATE subscriptions
    SET seats_used = GREATEST(1, seats_used - 1),
        updated_at = now()
    WHERE id = v_admin_sub.id;

    -- Log the event
    INSERT INTO billing_events (event_type, user_id, family_id, payload)
    VALUES (
        'family_seat_released',
        p_user_id,
        p_family_id,
        jsonb_build_object(
            'seats_used', GREATEST(1, v_admin_sub.seats_used - 1),
            'seats_total', v_admin_sub.seats_total
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Seat released successfully',
        'seats_used', GREATEST(1, v_admin_sub.seats_used - 1),
        'seats_total', v_admin_sub.seats_total
    );
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) TO "anon";

GRANT EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) TO "service_role";

CREATE OR REPLACE FUNCTION public.submit_pathway_checkin(p_user_pathway_id uuid, p_check_in_data jsonb, p_exercises_completed text[], p_journal_entry text, p_encrypted_journal_entry text DEFAULT NULL::text, p_encrypted_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    c_max_journal_length CONSTANT INT := 10000;
    c_max_encrypted_journal_length CONSTANT INT := 20000;

    v_user_id UUID;
    v_current_day INT;
    v_current_phase INT;
    v_current_phase_day INT;
    v_pathway_id UUID;
    v_phase_duration INT;
    v_max_phase INT;
    v_should_advance BOOLEAN := false;
    v_new_phase INT;
    v_new_day INT;
    v_new_phase_day INT;
    v_existing_checkin_id UUID;
    v_existing_completed BOOLEAN;
    v_pathway_completed BOOLEAN := false;
    v_result JSONB;
BEGIN
    -- Get user pathway info
    SELECT user_id, current_day, current_phase, current_phase_day, pathway_id
    INTO v_user_id, v_current_day, v_current_phase, v_current_phase_day, v_pathway_id
    FROM user_pathways
    WHERE id = p_user_pathway_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User pathway not found';
    END IF;

    -- Check for existing progress record with row lock
    SELECT id, check_in_completed INTO v_existing_checkin_id, v_existing_completed
    FROM pathway_progress
    WHERE user_pathway_id = p_user_pathway_id
    AND day_number = v_current_day
    FOR UPDATE NOWAIT;

    -- Only reject if check-in was already completed
    IF v_existing_completed = true THEN
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    END IF;

    -- Input validation
    IF p_journal_entry IS NOT NULL AND length(p_journal_entry) > c_max_journal_length THEN
        RAISE EXCEPTION 'Journal entry exceeds maximum length (% characters)', c_max_journal_length;
    END IF;

    IF p_encrypted_journal_entry IS NOT NULL AND length(p_encrypted_journal_entry) > c_max_encrypted_journal_length THEN
        RAISE EXCEPTION 'Encrypted journal entry exceeds maximum length (% characters)', c_max_encrypted_journal_length;
    END IF;

    -- Get phase duration with read lock
    SELECT duration_days INTO v_phase_duration
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id
    AND phase_number = v_current_phase
    FOR SHARE;

    -- Get max phase number for overflow validation
    SELECT MAX(phase_number) INTO v_max_phase
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id;

    -- Calculate new values
    v_new_day := v_current_day + 1;
    v_new_phase := v_current_phase;
    v_new_phase_day := v_current_phase_day + 1;

    -- Check if we should advance phase
    IF v_new_phase_day > v_phase_duration THEN
        IF v_current_phase < v_max_phase THEN
            v_should_advance := true;
            v_new_phase := v_current_phase + 1;
            v_new_phase_day := 1;
        ELSE
            v_pathway_completed := true;
            v_should_advance := false;
        END IF;
    END IF;

    -- Insert or update progress record
    IF v_existing_checkin_id IS NOT NULL THEN
        -- Update existing record (created by enrollment)
        UPDATE pathway_progress SET
            check_in_completed = true,
            check_in_data = p_check_in_data,
            exercises_completed = p_exercises_completed,
            journal_entry = CASE WHEN p_encrypted_journal_entry IS NULL THEN p_journal_entry ELSE NULL END,
            encrypted_journal_entry = p_encrypted_journal_entry,
            journal_encryption_key_id = CASE WHEN p_encrypted_journal_entry IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
            encrypted_check_in_data = p_encrypted_notes,
            check_in_encryption_key_id = CASE WHEN p_encrypted_notes IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
            data_encrypted_at = CASE WHEN p_encrypted_journal_entry IS NOT NULL OR p_encrypted_notes IS NOT NULL THEN now() ELSE NULL END
        WHERE id = v_existing_checkin_id;
    ELSE
        -- Insert new progress record
        INSERT INTO pathway_progress (
            user_pathway_id,
            day_number,
            phase_number,
            check_in_completed,
            check_in_data,
            exercises_completed,
            journal_entry,
            encrypted_journal_entry,
            journal_encryption_key_id,
            encrypted_check_in_data,
            check_in_encryption_key_id,
            data_encrypted_at,
            milestones_achieved
        ) VALUES (
            p_user_pathway_id,
            v_current_day,
            v_current_phase,
            true,
            p_check_in_data,
            p_exercises_completed,
            CASE WHEN p_encrypted_journal_entry IS NULL THEN p_journal_entry ELSE NULL END,
            p_encrypted_journal_entry,
            CASE WHEN p_encrypted_journal_entry IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
            p_encrypted_notes,
            CASE WHEN p_encrypted_notes IS NOT NULL THEN 'ios-securestorage-v1' ELSE NULL END,
            CASE WHEN p_encrypted_journal_entry IS NOT NULL OR p_encrypted_notes IS NOT NULL THEN now() ELSE NULL END,
            '{}'::TEXT[]
        );
    END IF;

    -- Update pathway state
    IF v_pathway_completed THEN
        UPDATE user_pathways
        SET
            status = 'completed',
            completed_at = now(),
            current_day = v_new_day,
            updated_at = now()
        WHERE id = p_user_pathway_id;
    ELSE
        UPDATE user_pathways
        SET
            current_day = v_new_day,
            current_phase = v_new_phase,
            current_phase_day = v_new_phase_day,
            updated_at = now()
        WHERE id = p_user_pathway_id;
    END IF;

    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'newDay', v_new_day,
        'newPhase', v_new_phase,
        'phaseAdvanced', v_should_advance,
        'pathwayCompleted', v_pathway_completed
    );

    RETURN v_result;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) TO "anon";

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) TO "service_role";

CREATE OR REPLACE FUNCTION public.submit_pathway_checkin(p_user_pathway_id uuid, p_check_in_data jsonb, p_exercises_completed text[], p_journal_entry text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID;
    v_current_day INT;
    v_current_phase INT;
    v_current_phase_day INT;
    v_pathway_id UUID;
    v_phase_duration INT;
    v_should_advance BOOLEAN := false;
    v_new_phase INT;
    v_new_day INT;
    v_new_phase_day INT;
    v_existing_checkin_id UUID;
    v_result JSONB;
BEGIN
    -- CRITICAL SECURITY CHECK: Verify user ownership
    SELECT user_id, current_day, current_phase, current_phase_day, pathway_id
    INTO v_user_id, v_current_day, v_current_phase, v_current_phase_day, v_pathway_id
    FROM user_pathways
    WHERE id = p_user_pathway_id;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User pathway not found';
    END IF;

    IF v_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot submit check-in for another user''s pathway';
    END IF;

    -- CRITICAL: Race condition fix - check for duplicate with row lock
    SELECT id INTO v_existing_checkin_id
    FROM pathway_progress
    WHERE user_pathway_id = p_user_pathway_id
    AND day_number = v_current_day
    FOR UPDATE NOWAIT;  -- Lock prevents concurrent inserts

    IF v_existing_checkin_id IS NOT NULL THEN
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    END IF;

    -- Input validation
    IF p_journal_entry IS NOT NULL AND length(p_journal_entry) > 10000 THEN
        RAISE EXCEPTION 'Journal entry too long (max 10,000 characters)';
    END IF;

    IF p_exercises_completed IS NOT NULL AND array_length(p_exercises_completed, 1) > 20 THEN
        RAISE EXCEPTION 'Too many exercises (max 20)';
    END IF;

    -- Get current phase duration
    SELECT duration_days INTO v_phase_duration
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id
    AND phase_number = v_current_phase;

    -- Calculate new values
    v_new_day := v_current_day + 1;
    v_new_phase := v_current_phase;
    v_new_phase_day := v_current_phase_day + 1;

    -- Check if we should advance phase
    IF v_current_phase_day >= v_phase_duration THEN
        v_should_advance := true;
        v_new_phase := v_current_phase + 1;
        v_new_phase_day := 1;
    END IF;

    -- 1. Insert progress record
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed,
        check_in_data,
        exercises_completed,
        journal_entry,
        milestones_achieved
    ) VALUES (
        p_user_pathway_id,
        v_current_day,
        v_current_phase,
        true,
        p_check_in_data,
        p_exercises_completed,
        p_journal_entry,
        '{}'::TEXT[]
    );

    -- 2. Update pathway state
    UPDATE user_pathways
    SET
        current_day = v_new_day,
        current_phase = v_new_phase,
        current_phase_day = v_new_phase_day,
        updated_at = now()
    WHERE id = p_user_pathway_id;

    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'newDay', v_new_day,
        'newPhase', v_new_phase,
        'phaseAdvanced', v_should_advance
    );

    RETURN v_result;

EXCEPTION
    WHEN lock_not_available THEN
        -- Concurrent check-in attempt
        RAISE EXCEPTION 'CHECK_IN_ALREADY_COMPLETED';
    WHEN OTHERS THEN
        -- Log error without exposing sensitive data
        RAISE EXCEPTION 'Check-in failed: %', SQLERRM;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) TO "anon";

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) TO "service_role";

CREATE OR REPLACE FUNCTION public.update_premium_shields(p_user_id uuid, p_is_premium boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- This function should only be called by service role from verify-purchase
  -- No auth.uid() check since service role calls don't have auth context

  IF p_is_premium THEN
    -- Upgrade to premium shields (3 per week, 2 recovery attempts)
    UPDATE user_stats SET
      streak_shields_max = 3,
      streak_shields_remaining = GREATEST(streak_shields_remaining, 3),
      recovery_attempts_max = 2,
      recovery_attempts_remaining = CASE
        WHEN recovery_quest_available THEN GREATEST(recovery_attempts_remaining, 2)
        ELSE 2
      END,
      updated_at = NOW()
    WHERE user_id = p_user_id;
  ELSE
    -- Downgrade to free shields (1 per week, 1 recovery attempt)
    UPDATE user_stats SET
      streak_shields_max = 1,
      streak_shields_remaining = LEAST(streak_shields_remaining, 1),
      recovery_attempts_max = 1,
      recovery_attempts_remaining = LEAST(recovery_attempts_remaining, 1),
      updated_at = NOW()
    WHERE user_id = p_user_id;
  END IF;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) TO "anon";

GRANT EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) TO "service_role";

CREATE OR REPLACE FUNCTION public.update_session_rating(p_session_id uuid, p_user_id uuid, p_rating integer, p_notes text)
 RETURNS couples_exercise_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session couples_exercise_sessions;
BEGIN
  -- Lock the row for update to prevent race conditions
  SELECT * INTO v_session FROM couples_exercise_sessions
    WHERE id = p_session_id
    FOR UPDATE;

  -- Validate session exists
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- Validate rating is within valid range (1-5)
  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5';
  END IF;

  -- Update rating for the appropriate user
  IF v_session.user_id_1 = p_user_id THEN
    UPDATE couples_exercise_sessions
      SET
        user_1_rating = p_rating,
        user_1_notes = p_notes,
        -- Mark session completed if both users have now rated
        status = CASE
          WHEN user_2_rating IS NOT NULL THEN 'completed'
          ELSE status
        END,
        completed_at = CASE
          WHEN user_2_rating IS NOT NULL THEN NOW()
          ELSE completed_at
        END,
        updated_at = NOW()
      WHERE id = p_session_id
      RETURNING * INTO v_session;
  ELSIF v_session.user_id_2 = p_user_id THEN
    UPDATE couples_exercise_sessions
      SET
        user_2_rating = p_rating,
        user_2_notes = p_notes,
        -- Mark session completed if both users have now rated
        status = CASE
          WHEN user_1_rating IS NOT NULL THEN 'completed'
          ELSE status
        END,
        completed_at = CASE
          WHEN user_1_rating IS NOT NULL THEN NOW()
          ELSE completed_at
        END,
        updated_at = NOW()
      WHERE id = p_session_id
      RETURNING * INTO v_session;
  ELSE
    RAISE EXCEPTION 'User is not part of this session';
  END IF;

  RETURN v_session;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.update_session_rating(uuid,uuid,integer,text) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.update_session_rating(uuid,uuid,integer,text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_session_rating(uuid,uuid,integer,text) TO "anon";

GRANT EXECUTE ON FUNCTION public.update_session_rating(uuid,uuid,integer,text) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.update_session_rating(uuid,uuid,integer,text) TO "service_role";

CREATE OR REPLACE FUNCTION public.upsert_signature_signal(p_user_id uuid, p_signal_type text, p_value double precision, p_source text, p_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO signature_signals (user_id, signal_type, value, source, date)
    VALUES (p_user_id, p_signal_type, LEAST(GREATEST(p_value, 0.0), 1.0), p_source, p_date)
    ON CONFLICT (user_id, signal_type, date)
    DO UPDATE SET
        value = GREATEST(signature_signals.value, EXCLUDED.value), -- Keep higher value
        source = EXCLUDED.source
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$function$
;

REVOKE EXECUTE ON FUNCTION public.upsert_signature_signal(uuid,text,double precision,text,date) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.upsert_signature_signal(uuid,text,double precision,text,date) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.upsert_signature_signal(uuid,text,double precision,text,date) TO "anon";

GRANT EXECUTE ON FUNCTION public.upsert_signature_signal(uuid,text,double precision,text,date) TO "authenticated";

GRANT EXECUTE ON FUNCTION public.upsert_signature_signal(uuid,text,double precision,text,date) TO "service_role";

ALTER POLICY "Service role manages agent actions" ON public.agent_actions TO PUBLIC;

ALTER POLICY "Service role can upload audio files" ON storage.objects TO PUBLIC;

ALTER POLICY "Service role can update audio files" ON storage.objects TO PUBLIC;

DO $$ DECLARE columns text; BEGIN

 SELECT string_agg(format('%I',attname),',') INTO columns FROM pg_attribute WHERE attrelid='public.profiles'::regclass AND attnum>0 AND NOT attisdropped;

 EXECUTE format('REVOKE INSERT (%s), UPDATE (%s) ON public.profiles FROM PUBLIC, anon, authenticated',columns,columns);

END $$;

REVOKE ALL ON TABLE public.profiles FROM PUBLIC, anon, authenticated;

GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.profiles TO "anon";

GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.profiles TO "authenticated";

REVOKE ALL ON TABLE public.agent_actions FROM PUBLIC, anon, authenticated;

GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.agent_actions TO "anon";

GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE public.agent_actions TO "authenticated";

-- Realtime rollback is valid only after 20261105210000 successfully applied from
-- the verified zero-membership baseline. Do not run it after a baseline precondition failure.
DO $$ DECLARE name text; BEGIN FOREACH name IN ARRAY ARRAY['agent_actions','together_participants','support_messages','circle_room_participants','user_presence','forum_replies'] LOOP IF EXISTS(SELECT FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=name) THEN EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I',name); END IF; END LOOP; END $$;

ALTER POLICY "Service role can insert synthesis requests" ON public.synthesis_requests TO PUBLIC;
ALTER TABLE public.synthesis_requests DROP CONSTRAINT IF EXISTS synthesis_character_count_nonnegative;
REVOKE ALL ON public.creative_quota_usage FROM PUBLIC,anon,authenticated;
GRANT INSERT,SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN ON public.creative_quota_usage TO anon;
GRANT INSERT,SELECT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN ON public.creative_quota_usage TO authenticated;
CREATE OR REPLACE FUNCTION public.increment_voice_quota(p_minutes integer)
 RETURNS TABLE(new_minutes integer, limit_reached boolean, voice_limit integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_is_premium BOOLEAN;
    v_limit INTEGER;
    v_new_minutes INTEGER;
BEGIN
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    v_limit := CASE WHEN v_is_premium THEN 60 ELSE 5 END;

    -- Upsert and increment
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 0, p_minutes)
    ON CONFLICT (user_id, date)
    DO UPDATE SET voice_minutes_used = creative_quota_usage.voice_minutes_used + p_minutes
    RETURNING creative_quota_usage.voice_minutes_used INTO v_new_minutes;

    RETURN QUERY
    SELECT
        v_new_minutes,
        v_new_minutes >= v_limit,
        v_limit;
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.increment_voice_quota(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.increment_voice_quota(integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_voice_quota(integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.increment_voice_quota(integer) TO anon;
GRANT EXECUTE ON FUNCTION public.increment_voice_quota(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_voice_quota(integer) TO service_role;

COMMIT;
