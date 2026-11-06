-- Restrict the audited internal RPCs to the service role.
-- Signatures verified against the deployed structural snapshot (2026-10-22).
-- SignalMonitor retains owner-scoped signal writes. join-family uses its validated service client.
BEGIN;

-- Fail before applying any repair if the audited overloads have changed.
DO $migration$
DECLARE
  v_signature text;
  v_oid oid;
  v_expected_count integer;
  v_actual_count integer;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.get_cron_secret()',
    'public.get_moods_for_pattern_analysis(uuid,integer)',
    'public.get_pending_notifications(integer)',
    'public.get_streak_at_risk_users(integer)',
    'public.get_users_for_weekly_summary()',
    'public.claim_family_seat(uuid,uuid,text)',
    'public.release_family_seat(uuid,uuid)',
    'public.submit_pathway_checkin(uuid,jsonb,text[],text)',
    'public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text)',
    'public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer)',
    'public.check_capacity_rate_limit(uuid,bigint,integer)',
    'public.check_and_increment_synthesis_quota(uuid,boolean)',
    'public.check_and_increment_synthesis_quota(uuid,boolean,integer)',
    'public.update_premium_shields(uuid,boolean)',
    'public.get_stress_signature(uuid)',
    'public.is_moderator()',
    'public.update_session_rating(uuid,uuid,integer,text)'
  ] LOOP
    v_oid := to_regprocedure(v_signature);
    IF v_oid IS NULL OR NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc WHERE oid = v_oid
        AND prokind = 'f' AND prosecdef
    ) THEN
      RAISE EXCEPTION 'Audited SECURITY DEFINER function missing or changed: %', v_signature;
    END IF;
  END LOOP;

  FOR v_signature, v_expected_count IN
    SELECT * FROM (VALUES
      ('get_cron_secret', 1),
      ('get_moods_for_pattern_analysis', 1),
      ('get_pending_notifications', 1),
      ('get_streak_at_risk_users', 1),
      ('get_users_for_weekly_summary', 1),
      ('claim_family_seat', 1),
      ('release_family_seat', 1),
      ('submit_pathway_checkin', 2),
      ('check_rate_limit', 1),
      ('check_capacity_rate_limit', 1),
      ('check_and_increment_synthesis_quota', 2),
      ('update_premium_shields', 1),
      ('get_stress_signature', 1),
      ('is_moderator', 1),
      ('update_session_rating', 1)
    ) AS expected(name, overloads)
  LOOP
    SELECT count(*) INTO v_actual_count
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = v_signature;
    IF v_actual_count <> v_expected_count THEN
      RAISE EXCEPTION 'Unexpected overloads for public.%: expected %, found %',
        v_signature, v_expected_count, v_actual_count;
    END IF;
  END LOOP;
END;
$migration$;

REVOKE EXECUTE ON FUNCTION public.get_cron_secret() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_secret() TO service_role;
ALTER FUNCTION public.get_cron_secret() SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) TO service_role;
ALTER FUNCTION public.get_moods_for_pattern_analysis(uuid,integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_pending_notifications(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_notifications(integer) TO service_role;
ALTER FUNCTION public.get_pending_notifications(integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_streak_at_risk_users(integer) TO service_role;
ALTER FUNCTION public.get_streak_at_risk_users(integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.get_users_for_weekly_summary() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_users_for_weekly_summary() TO service_role;
ALTER FUNCTION public.get_users_for_weekly_summary() SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_family_seat(uuid,uuid,text) TO service_role;
ALTER FUNCTION public.claim_family_seat(uuid,uuid,text) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_family_seat(uuid,uuid) TO service_role;
ALTER FUNCTION public.release_family_seat(uuid,uuid) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) TO service_role;
ALTER FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) TO service_role;
ALTER FUNCTION public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer) TO service_role;
ALTER FUNCTION public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) TO service_role;
ALTER FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean) TO service_role;
ALTER FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean,integer) TO service_role;
ALTER FUNCTION public.check_and_increment_synthesis_quota(uuid,boolean,integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_premium_shields(uuid,boolean) TO service_role;
ALTER FUNCTION public.update_premium_shields(uuid,boolean) SET search_path TO pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION public.get_stress_signature(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
DECLARE
  v_result JSONB;
  v_pattern_count INT;
BEGIN
  -- Verify caller owns the data
  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access patterns for other users'
      USING ERRCODE = '42501';
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
$function$;

CREATE OR REPLACE FUNCTION public.is_moderator()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER COST 10
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
BEGIN
    RETURN COALESCE(
        (SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'moderator'),
        false
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_session_rating(p_session_id uuid, p_user_id uuid, p_rating integer, p_notes text)
 RETURNS couples_exercise_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
DECLARE
  v_session couples_exercise_sessions;
BEGIN
  -- The supplied participant must be the authenticated caller. The existing
  -- participant check below still applies to service calls.
  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Can only rate as the authenticated user'
      USING ERRCODE = '42501';
  END IF;

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
$function$;

-- The deployed moods table has no source column. Preserve the RPC shape with unknown source.
CREATE OR REPLACE FUNCTION public.get_moods_for_pattern_analysis(p_user_id uuid, p_weeks integer DEFAULT 4)
 RETURNS TABLE(mood_score integer, created_at timestamp with time zone, day_of_week integer, hour_of_day integer, source text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    m.mood_score,
    m.created_at,
    EXTRACT(DOW FROM m.created_at)::int as day_of_week,
    EXTRACT(HOUR FROM m.created_at)::int as hour_of_day,
    NULL::text AS source
  FROM moods m
  WHERE m.user_id = p_user_id
    AND m.created_at >= NOW() - (p_weeks || ' weeks')::interval
  ORDER BY m.created_at DESC;
END;
$function$
;

-- Align notification readers with the deployed push_tokens.device_token column.
CREATE OR REPLACE FUNCTION public.get_pending_notifications(p_limit integer DEFAULT 100)
 RETURNS TABLE(id uuid, user_id uuid, notification_type text, title text, body text, deep_link text, metadata jsonb, push_token text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
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
    pt.device_token AS push_token
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

CREATE OR REPLACE FUNCTION public.get_streak_at_risk_users(p_target_hour integer)
 RETURNS TABLE(user_id uuid, current_streak_days integer, timezone text, push_token text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    p.current_streak_days,
    p.timezone,
    pt.device_token AS push_token
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

CREATE OR REPLACE FUNCTION public.get_users_for_weekly_summary()
 RETURNS TABLE(user_id uuid, push_token text, timezone text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS user_id,
    pt.device_token AS push_token,
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
-- Coordinate with join-family: only the validated Edge handler can grant family membership.
CREATE OR REPLACE FUNCTION public.add_family_member(p_family_id uuid, p_user_id uuid, p_role text DEFAULT 'child'::text, p_nickname text DEFAULT NULL::text, p_birth_date text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
DECLARE
  v_family_record RECORD;
  v_existing_member RECORD;
  v_member_record RECORD;
  v_error_code TEXT;
BEGIN
  -- Step 0: CRITICAL SECURITY CHECK - Users can only add themselves to families
  -- Prevents IDOR privilege escalation where user A adds user B without consent
  IF p_user_id IS NULL OR current_setting('role', true) IS DISTINCT FROM 'service_role' THEN
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
REVOKE EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_family_member(uuid,uuid,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.upsert_signature_signal(p_user_id uuid, p_signal_type text, p_value double precision, p_source text, p_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_id UUID;
BEGIN
    IF p_user_id IS NULL OR (current_setting('role', true) IS DISTINCT FROM 'service_role' AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)) THEN
      RAISE EXCEPTION 'Unauthorized signal owner' USING ERRCODE='42501';
    END IF;
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
COMMIT;
