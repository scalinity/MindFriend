-- Fix references to non-existent logged_at column on moods table
-- The moods table uses created_at, not logged_at

-- Fix the update_challenge_progress_on_mood function
CREATE OR REPLACE FUNCTION update_challenge_progress_on_mood()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE challenge_participants
    SET current_progress = (
        SELECT COUNT(DISTINCT DATE(created_at))
        FROM moods
        WHERE user_id = NEW.user_id
        AND created_at > NOW() - INTERVAL '7 days'
    )
    WHERE challenge_id IN (
        SELECT id FROM challenges
        WHERE challenge_type = 'mood'
        AND ends_at > NOW()
    )
    AND user_id = NEW.user_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Also fix the recovery mode function that references logged_at
CREATE OR REPLACE FUNCTION public.check_recovery_mode_eligibility(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_current_in_recovery BOOLEAN;
    v_consecutive_low_days INT := 0;
    v_consecutive_good_days INT := 0;
    v_should_enter BOOLEAN := FALSE;
    v_should_exit BOOLEAN := FALSE;
    v_mood_record RECORD;
    v_threshold_days INT := 3;
BEGIN
    -- Get current recovery mode status
    SELECT recovery_mode_enabled INTO v_current_in_recovery
    FROM user_settings
    WHERE user_id = p_user_id;

    -- Count consecutive low mood days (score <= 2) from most recent
    FOR v_mood_record IN
        SELECT mood_score as score, DATE(created_at) as mood_date
        FROM moods
        WHERE user_id = p_user_id
        ORDER BY created_at DESC
        LIMIT 7
    LOOP
        IF v_mood_record.score <= 2 THEN
            v_consecutive_low_days := v_consecutive_low_days + 1;
        ELSE
            EXIT; -- Stop counting once we hit a non-low day
        END IF;
    END LOOP;

    -- Count consecutive good mood days (score >= 4) from most recent
    FOR v_mood_record IN
        SELECT mood_score as score, DATE(created_at) as mood_date
        FROM moods
        WHERE user_id = p_user_id
        ORDER BY created_at DESC
        LIMIT 7
    LOOP
        IF v_mood_record.score >= 4 THEN
            v_consecutive_good_days := v_consecutive_good_days + 1;
        ELSE
            EXIT; -- Stop counting once we hit a non-good day
        END IF;
    END LOOP;

    -- Determine if should enter or exit recovery mode
    IF NOT COALESCE(v_current_in_recovery, FALSE) AND v_consecutive_low_days >= v_threshold_days THEN
        v_should_enter := TRUE;
    ELSIF COALESCE(v_current_in_recovery, FALSE) AND v_consecutive_good_days >= v_threshold_days THEN
        v_should_exit := TRUE;
    END IF;

    -- Build result
    v_result := jsonb_build_object(
        'currentlyInRecovery', COALESCE(v_current_in_recovery, FALSE),
        'shouldEnter', v_should_enter,
        'shouldExit', v_should_exit,
        'consecutiveLowDays', v_consecutive_low_days,
        'consecutiveGoodDays', v_consecutive_good_days,
        'thresholdDays', v_threshold_days
    );

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION update_challenge_progress_on_mood IS 'Updates challenge progress when a mood is logged - uses created_at column';
COMMENT ON FUNCTION public.check_recovery_mode_eligibility IS 'Check if user should enter/exit recovery mode based on mood patterns - uses created_at column';
