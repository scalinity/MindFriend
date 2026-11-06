-- Repair the existing exercise/program completion transactions without changing rewards.
BEGIN;
SET LOCAL lock_timeout = '3s';
DO $$ BEGIN
  IF to_regprocedure('public.complete_exercise_session(uuid,integer,text)') IS NOT NULL
     OR to_regprocedure('public.award_exercise_session_xp(uuid)') IS NOT NULL
     OR EXISTS (SELECT FROM pg_attribute WHERE attrelid='public.exercise_sessions'::regclass
                AND attname='xp_awarded_at' AND NOT attisdropped)
     OR md5(pg_get_functiondef('public.complete_program_day(uuid,integer,jsonb,text,text,uuid,integer,integer)'::regprocedure))
        IS DISTINCT FROM '9874f5129a2fdcdbcdd9837456161d64' THEN
    RAISE EXCEPTION 'Completion schema differs from the reviewed baseline';
  END IF;
END $$;

-- Session and counter update share a transaction and row lock. RLS remains active.
CREATE OR REPLACE FUNCTION public.complete_exercise_session(p_session_id uuid, p_rating integer DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_session public.exercise_sessions%ROWTYPE;
BEGIN
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_rating IS NOT NULL AND p_rating NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_session FROM public.exercise_sessions
  WHERE id = p_session_id AND user_id = v_owner FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session not found or access denied' USING ERRCODE = '42501';
  END IF;
  -- Serialize different sessions for this owner before recounting. This also repairs
  -- a session saved by an older client whose separate counter write failed.
  PERFORM 1 FROM public.user_stats WHERE user_id = v_owner FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercise stats not found'; END IF;
  IF v_session.completed_at IS NULL THEN
    UPDATE public.exercise_sessions SET completed_at = now(), ended_at = COALESCE(ended_at, now()),
      completed = true, rating = p_rating, note = p_note WHERE id = p_session_id AND user_id = v_owner;
  END IF;
  UPDATE public.user_stats SET total_exercises_completed = (
      SELECT count(*) FROM public.exercise_sessions WHERE user_id = v_owner AND completed_at IS NOT NULL
    ), updated_at = now() WHERE user_id = v_owner;
  RETURN v_session.completed_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_exercise_session(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_exercise_session(uuid, integer, text) TO authenticated;

-- Keep the existing 30 XP exercise reward, keyed to its actual completed session.
ALTER TABLE public.exercise_sessions ADD COLUMN IF NOT EXISTS xp_awarded_at timestamptz;
CREATE OR REPLACE FUNCTION public.award_exercise_session_xp(p_session_id uuid)
RETURNS TABLE(amount integer, new_xp integer, new_level integer, new_title text, level_up boolean)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_session public.exercise_sessions%ROWTYPE;
  v_skill text;
BEGIN
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_session FROM public.exercise_sessions
  WHERE id = p_session_id AND user_id = v_owner FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Session not found or access denied' USING ERRCODE = '42501'; END IF;
  IF v_session.completed_at IS NULL THEN
    RAISE EXCEPTION 'Finish the exercise before claiming its reward' USING ERRCODE = '22023';
  END IF;
  IF v_session.xp_awarded_at IS NOT NULL THEN
    RETURN QUERY SELECT 0, us.xp_total, us.level, us.level_title, false
      FROM public.user_stats us WHERE us.user_id = v_owner;
    RETURN;
  END IF;
  SELECT e.type::text INTO v_skill FROM public.exercises e WHERE e.id = v_session.exercise_id;
  RETURN QUERY SELECT 30, a.new_xp, a.new_level, a.new_title, a.level_up
    FROM public.award_xp(v_owner, 30, 'exercise', v_skill) a;
  UPDATE public.exercise_sessions SET xp_awarded_at = now() WHERE id = p_session_id AND user_id = v_owner;
END;
$$;
REVOKE ALL ON FUNCTION public.award_exercise_session_xp(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_exercise_session_xp(uuid) TO authenticated;

-- Retain the existing owner-checked definer for certificate issuance: certificates
-- have a client SELECT policy only. No new definer endpoint is introduced.
CREATE OR REPLACE FUNCTION "public"."complete_program_day"("p_enrollment_id" "uuid", "p_day_number" integer, "p_content_completed" "jsonb", "p_reflection_response" "text" DEFAULT NULL::"text", "p_apply_report" "text" DEFAULT NULL::"text", "p_exercise_session_id" "uuid" DEFAULT NULL::"uuid", "p_mood_before" integer DEFAULT NULL::integer, "p_mood_after" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_enrollment program_enrollments%ROWTYPE;
  v_program programs%ROWTYPE;
  v_day program_days%ROWTYPE;
  v_required_completed BOOLEAN;
  v_is_program_complete BOOLEAN;
  v_certificate_number TEXT;
  v_result JSONB;
  v_exercise_session_id UUID;
BEGIN
  -- Ensure user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  -- Get enrollment and verify ownership
  SELECT * INTO v_enrollment FROM program_enrollments
  WHERE id = p_enrollment_id AND user_id = v_user_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found or access denied' USING ERRCODE = '42501';
  END IF;

  -- Get program and day
  SELECT * INTO v_program FROM programs WHERE id = v_enrollment.program_id;
  SELECT * INTO v_day FROM program_days
  WHERE program_id = v_program.id AND day_number = p_day_number;

  IF v_day IS NULL THEN
    RAISE EXCEPTION 'Day % not found in program', p_day_number;
  END IF;

  -- The enrollment lock serializes retries, including the final certificate/XP transaction.
  IF EXISTS (SELECT 1 FROM public.program_day_progress
             WHERE enrollment_id = p_enrollment_id AND day_number = p_day_number
               AND status = 'completed') THEN
    v_is_program_complete := p_day_number = v_program.duration_days AND v_enrollment.status = 'completed';
    IF v_is_program_complete THEN
      SELECT certificate_number INTO v_certificate_number FROM public.program_certificates
      WHERE enrollment_id = p_enrollment_id AND user_id = v_user_id;
      IF v_certificate_number IS NULL THEN
        RAISE EXCEPTION 'Completed program certificate is missing';
      END IF;
    END IF;
    RETURN jsonb_build_object(
      'day_completed', p_day_number, 'program_complete', v_is_program_complete,
      'next_day', CASE WHEN v_is_program_complete THEN NULL ELSE p_day_number + 1 END,
      'streak', v_enrollment.streak_days, 'certificate_number', v_certificate_number
    );
  END IF;

  IF v_enrollment.status <> 'active' OR p_day_number <> v_enrollment.current_day THEN
    RAISE EXCEPTION 'Only the current active program day can be completed' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM public.program_day_progress
      WHERE enrollment_id = p_enrollment_id AND day_number BETWEEN 1 AND p_day_number - 1
        AND status IN ('completed', 'skipped')) <> p_day_number - 1 THEN
    RAISE EXCEPTION 'Earlier program days are unfinished' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_content_completed) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Content completion must be an object' USING ERRCODE = '22023';
  END IF;

  -- Required keys must contain JSON true, rather than merely exist.
  SELECT COALESCE(
    (SELECT bool_and(COALESCE(p_content_completed->req = 'true'::jsonb, false))
     FROM jsonb_array_elements_text(v_day.completion_criteria->'required') req),
    TRUE
  ) INTO v_required_completed;

  IF NOT v_required_completed THEN
    RAISE EXCEPTION 'Required content not completed' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(p_exercise_session_id, exercise_session_id) INTO v_exercise_session_id
  FROM public.program_day_progress WHERE enrollment_id = p_enrollment_id AND day_number = p_day_number;
  v_exercise_session_id := COALESCE(v_exercise_session_id, p_exercise_session_id);
  IF v_exercise_session_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.exercise_sessions WHERE id = v_exercise_session_id AND user_id = v_user_id
      AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Completed exercise not found or access denied' USING ERRCODE = '42501';
  END IF;
  IF p_content_completed->'practice' = 'true'::jsonb AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_day.content) block
    WHERE block->>'type' = 'practice' AND block->>'exercise_id' IS NOT NULL
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.exercise_sessions es, jsonb_array_elements(v_day.content) block
      WHERE es.id = v_exercise_session_id AND es.user_id = v_user_id AND es.completed_at IS NOT NULL
        AND es.started_at >= v_enrollment.started_at
        AND block->>'type' = 'practice' AND es.exercise_id::text = lower(block->>'exercise_id')
    ) OR EXISTS (
      SELECT 1 FROM public.program_day_progress
      WHERE exercise_session_id = v_exercise_session_id
        AND (enrollment_id <> p_enrollment_id OR day_number <> p_day_number)
    ) THEN
      RAISE EXCEPTION 'Finish this day exercise before completing practice' USING ERRCODE = '22023';
    END IF;
  END IF;

  -- Update or insert day progress
  INSERT INTO program_day_progress (
    enrollment_id, day_number, status, started_at, completed_at,
    content_completed, reflection_response, apply_report,
    exercise_session_id, mood_before, mood_after
  ) VALUES (
    p_enrollment_id, p_day_number, 'completed', NOW(), NOW(),
    p_content_completed, p_reflection_response, p_apply_report,
    v_exercise_session_id, p_mood_before, p_mood_after
  )
  ON CONFLICT (enrollment_id, day_number)
  DO UPDATE SET
    status = 'completed',
    completed_at = NOW(),
    content_completed = p_content_completed,
    reflection_response = COALESCE(p_reflection_response, program_day_progress.reflection_response),
    apply_report = COALESCE(p_apply_report, program_day_progress.apply_report),
    exercise_session_id = COALESCE(v_exercise_session_id, program_day_progress.exercise_session_id),
    mood_before = COALESCE(p_mood_before, program_day_progress.mood_before),
    mood_after = COALESCE(p_mood_after, program_day_progress.mood_after),
    updated_at = NOW();

  -- Update enrollment streak and current day
  UPDATE program_enrollments SET
    streak_days = streak_days + 1,
    longest_streak = GREATEST(longest_streak, streak_days + 1),
    current_day = LEAST(current_day + 1, v_program.duration_days),
    updated_at = NOW()
  WHERE id = p_enrollment_id
  RETURNING * INTO v_enrollment;

  -- Check if program is complete
  v_is_program_complete := (p_day_number >= v_program.duration_days);

  IF v_is_program_complete THEN
    -- Mark enrollment complete
    UPDATE program_enrollments SET
      status = 'completed',
      completed_at = NOW()
    WHERE id = p_enrollment_id;

    -- Generate certificate number
    v_certificate_number := 'MF-' || TO_CHAR(NOW(), 'YYYY') || '-' || LPAD(NEXTVAL('certificate_seq')::TEXT, 6, '0');

    -- Create certificate
    INSERT INTO program_certificates (
      user_id, program_id, enrollment_id, certificate_number, completion_stats
    ) VALUES (
      v_user_id, v_program.id, p_enrollment_id, v_certificate_number,
      jsonb_build_object(
        'days_completed', (SELECT count(*) FROM public.program_day_progress WHERE enrollment_id = p_enrollment_id AND status = 'completed'),
        'streak_best', v_enrollment.longest_streak,
        'skips_used', v_enrollment.skips_used,
        'program_title', v_program.title
      )
    );

    -- Create celebration event for program completion
    INSERT INTO celebration_events (
      user_id, celebration_type, value, shown_at
    ) VALUES (
      v_user_id, 'program_complete', v_program.duration_days, NULL
    );

    -- Award XP (200 for program completion)
    -- Note: award_xp function may not exist yet, wrap in exception handler
    BEGIN
      PERFORM award_xp(v_user_id, 200, 'program_completion', v_program.category);
    EXCEPTION WHEN undefined_function THEN
      -- award_xp not defined yet, skip silently
      NULL;
    END;
  ELSE
    -- Create next day progress entry
    INSERT INTO program_day_progress (enrollment_id, day_number, status)
    VALUES (p_enrollment_id, p_day_number + 1, 'pending')
    ON CONFLICT DO NOTHING;
  END IF;

  v_result := jsonb_build_object(
    'day_completed', p_day_number,
    'program_complete', v_is_program_complete,
    'next_day', CASE WHEN v_is_program_complete THEN NULL ELSE p_day_number + 1 END,
    'streak', v_enrollment.streak_days,
    'certificate_number', CASE WHEN v_is_program_complete THEN v_certificate_number ELSE NULL END
  );

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_program_day(uuid, integer, jsonb, text, text, uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_program_day(uuid, integer, jsonb, text, text, uuid, integer, integer) TO authenticated, service_role;
COMMIT;
