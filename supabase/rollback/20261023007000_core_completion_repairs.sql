-- Revert code only. Existing completions, counts and certificates remain intact.
BEGIN;
DROP FUNCTION IF EXISTS public.complete_exercise_session(uuid, integer, text);
DROP FUNCTION IF EXISTS public.award_exercise_session_xp(uuid);
-- Retain xp_awarded_at because it records unique rewards and allows safe reapplication.
CREATE OR REPLACE FUNCTION "public"."complete_program_day"("p_enrollment_id" "uuid", "p_day_number" integer, "p_content_completed" "jsonb", "p_reflection_response" "text" DEFAULT NULL::"text", "p_apply_report" "text" DEFAULT NULL::"text", "p_exercise_session_id" "uuid" DEFAULT NULL::"uuid", "p_mood_before" integer DEFAULT NULL::integer, "p_mood_after" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
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
BEGIN
  -- Ensure user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get enrollment and verify ownership
  SELECT * INTO v_enrollment FROM program_enrollments
  WHERE id = p_enrollment_id AND user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found or access denied';
  END IF;

  IF v_enrollment.status != 'active' THEN
    RAISE EXCEPTION 'Enrollment is not active';
  END IF;

  -- Get program and day
  SELECT * INTO v_program FROM programs WHERE id = v_enrollment.program_id;
  SELECT * INTO v_day FROM program_days
  WHERE program_id = v_program.id AND day_number = p_day_number;

  IF v_day IS NULL THEN
    RAISE EXCEPTION 'Day % not found in program', p_day_number;
  END IF;

  -- Check required content is completed
  SELECT COALESCE(
    (SELECT bool_and(p_content_completed ? req)
     FROM jsonb_array_elements_text(v_day.completion_criteria->'required') req),
    TRUE
  ) INTO v_required_completed;

  IF NOT v_required_completed THEN
    RAISE EXCEPTION 'Required content not completed';
  END IF;

  -- Update or insert day progress
  INSERT INTO program_day_progress (
    enrollment_id, day_number, status, started_at, completed_at,
    content_completed, reflection_response, apply_report,
    exercise_session_id, mood_before, mood_after
  ) VALUES (
    p_enrollment_id, p_day_number, 'completed', NOW(), NOW(),
    p_content_completed, p_reflection_response, p_apply_report,
    p_exercise_session_id, p_mood_before, p_mood_after
  )
  ON CONFLICT (enrollment_id, day_number)
  DO UPDATE SET
    status = 'completed',
    completed_at = NOW(),
    content_completed = p_content_completed,
    reflection_response = COALESCE(p_reflection_response, program_day_progress.reflection_response),
    apply_report = COALESCE(p_apply_report, program_day_progress.apply_report),
    exercise_session_id = COALESCE(p_exercise_session_id, program_day_progress.exercise_session_id),
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
        'days_completed', v_program.duration_days,
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

GRANT EXECUTE ON FUNCTION public.complete_program_day(uuid, integer, jsonb, text, text, uuid, integer, integer) TO PUBLIC, anon, authenticated, service_role;
COMMIT;
