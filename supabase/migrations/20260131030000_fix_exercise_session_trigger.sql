-- Fix trigger that references non-existent duration_minutes column on exercise_sessions
-- The duration_minutes is on the exercises table, not exercise_sessions

-- Drop and recreate the function with correct column reference
CREATE OR REPLACE FUNCTION "public"."update_challenge_progress_on_exercise"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_duration_minutes INTEGER;
BEGIN
    -- Get duration from the exercises table, not from exercise_sessions
    SELECT duration_minutes INTO v_duration_minutes
    FROM exercises
    WHERE id = NEW.exercise_id;

    -- Use COALESCE to handle NULL case
    UPDATE challenge_participants
    SET current_progress = current_progress + COALESCE(v_duration_minutes, 0)
    WHERE challenge_id IN (
        SELECT c.id FROM challenges c
        WHERE c.challenge_type = 'minutes'
        AND c.exercise_type = (
            SELECT exercise_type FROM exercises WHERE id = NEW.exercise_id
        )
        AND c.ends_at > NOW()
    )
    AND user_id = NEW.user_id
    AND EXISTS (
        SELECT 1 FROM challenges c
        WHERE c.id = challenge_participants.challenge_id
        AND c.starts_at <= NOW()
    );

    RETURN NEW;
END;
$$;

-- Also fix update_listener_stats if it references duration_minutes from sessions
CREATE OR REPLACE FUNCTION "public"."update_listener_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_duration_minutes INTEGER;
BEGIN
    IF NEW.status = 'completed' AND NEW.listener_id IS NOT NULL THEN
        -- Get duration from exercises table
        SELECT duration_minutes INTO v_duration_minutes
        FROM exercises
        WHERE id = NEW.exercise_id;

        UPDATE listeners
        SET
            total_sessions = total_sessions + 1,
            total_hours = total_hours + COALESCE(v_duration_minutes, 0) / 60.0,
            updated_at = NOW()
        WHERE id = NEW.listener_id;
    END IF;
    RETURN NEW;
END;
$$;
