-- Migration: 20260322000000_save_program_progress.sql
-- Description: Add function to save partial program day progress without completing it

-- Function: Save program day progress (partial)
-- SECURITY: Validates enrollment ownership via auth.uid()
CREATE OR REPLACE FUNCTION save_program_day_progress(
  p_enrollment_id UUID,
  p_day_number INT,
  p_content_completed JSONB,
  p_reflection_response TEXT DEFAULT NULL,
  p_apply_report TEXT DEFAULT NULL,
  p_exercise_session_id UUID DEFAULT NULL,
  p_mood_before INT DEFAULT NULL,
  p_mood_after INT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_enrollment_id UUID;
BEGIN
  -- Ensure user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify enrollment ownership and get id
  SELECT id INTO v_enrollment_id FROM program_enrollments
  WHERE id = p_enrollment_id AND user_id = v_user_id;

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'Enrollment not found or access denied';
  END IF;

  -- Upsert progress
  -- Note: We only set status to 'in_progress' if it's currently 'pending'.
  -- If it's already 'completed' or 'skipped', we don't change the status back to 'in_progress'
  -- but we might still want to update the content (e.g. reflection).

  INSERT INTO program_day_progress (
    enrollment_id, day_number, status, started_at,
    content_completed, reflection_response, apply_report,
    exercise_session_id, mood_before, mood_after, updated_at
  ) VALUES (
    p_enrollment_id, p_day_number, 'in_progress', NOW(),
    p_content_completed, p_reflection_response, p_apply_report,
    p_exercise_session_id, p_mood_before, p_mood_after, NOW()
  )
  ON CONFLICT (enrollment_id, day_number)
  DO UPDATE SET
    status = CASE 
      WHEN program_day_progress.status = 'pending' THEN 'in_progress'
      ELSE program_day_progress.status
    END,
    content_completed = p_content_completed,
    reflection_response = COALESCE(p_reflection_response, program_day_progress.reflection_response),
    apply_report = COALESCE(p_apply_report, program_day_progress.apply_report),
    exercise_session_id = COALESCE(p_exercise_session_id, program_day_progress.exercise_session_id),
    mood_before = COALESCE(p_mood_before, program_day_progress.mood_before),
    mood_after = COALESCE(p_mood_after, program_day_progress.mood_after),
    updated_at = NOW();

  RETURN jsonb_build_object(
    'success', true,
    'day_number', p_day_number
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
