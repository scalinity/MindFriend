-- Recovery Mode UX feature migration
-- Adds support for a gentle, simplified app mode during difficult times
-- See: kimispecs/03-recovery-mode-ux-spec.md

-- Add recovery mode columns to user_settings
ALTER TABLE user_settings
ADD COLUMN IF NOT EXISTS recovery_mode_active BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS recovery_mode_entered_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS recovery_mode_reason TEXT CHECK (recovery_mode_reason IN ('manual', 'auto_consecutive_low_mood'));

-- Index for querying users in recovery mode
CREATE INDEX IF NOT EXISTS idx_user_settings_recovery_mode
ON user_settings(recovery_mode_active) WHERE recovery_mode_active = TRUE;

-- Function to evaluate recovery mode state for a user
-- Called by cron job to auto-enter/exit based on mood trends
CREATE OR REPLACE FUNCTION evaluate_recovery_mode_for_user(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_state BOOLEAN;
    v_entered_at TIMESTAMPTZ;
    v_reason TEXT;
    v_consecutive_low_days INT := 0;
    v_consecutive_good_days INT := 0;
    v_mood_record RECORD;
    v_result JSONB;
BEGIN
    -- Get current recovery mode state
    SELECT
        recovery_mode_active,
        recovery_mode_entered_at,
        recovery_mode_reason
    INTO v_current_state, v_entered_at, v_reason
    FROM user_settings
    WHERE user_id = p_user_id;

    -- Count consecutive low mood days (score <= 2) from most recent
    FOR v_mood_record IN
        SELECT score, DATE(logged_at) as mood_date
        FROM moods
        WHERE user_id = p_user_id
        ORDER BY logged_at DESC
        LIMIT 7
    LOOP
        IF v_mood_record.score <= 2 THEN
            v_consecutive_low_days := v_consecutive_low_days + 1;
        ELSE
            EXIT; -- Break on first non-low day
        END IF;
    END LOOP;

    -- Count consecutive good mood days (score >= 4) from most recent
    FOR v_mood_record IN
        SELECT score, DATE(logged_at) as mood_date
        FROM moods
        WHERE user_id = p_user_id
        ORDER BY logged_at DESC
        LIMIT 7
    LOOP
        IF v_mood_record.score >= 4 THEN
            v_consecutive_good_days := v_consecutive_good_days + 1;
        ELSE
            EXIT; -- Break on first non-good day
        END IF;
    END LOOP;

    -- Decision logic
    IF NOT v_current_state THEN
        -- Not in recovery mode - check if we should auto-enter
        IF v_consecutive_low_days >= 3 THEN
            -- Auto-enter recovery mode
            UPDATE user_settings
            SET
                recovery_mode_active = TRUE,
                recovery_mode_entered_at = NOW(),
                recovery_mode_reason = 'auto_consecutive_low_mood'
            WHERE user_id = p_user_id;

            v_result := jsonb_build_object(
                'action', 'entered',
                'reason', 'auto_consecutive_low_mood',
                'consecutive_low_days', v_consecutive_low_days
            );
        ELSE
            v_result := jsonb_build_object(
                'action', 'none',
                'reason', 'no_trigger',
                'consecutive_low_days', v_consecutive_low_days
            );
        END IF;
    ELSE
        -- In recovery mode - check if we should auto-exit
        -- Auto-exit after 7 days OR 3+ consecutive good mood days
        IF v_entered_at IS NOT NULL AND (NOW() - v_entered_at) > INTERVAL '7 days' THEN
            -- Auto-exit: exceeded max duration
            UPDATE user_settings
            SET
                recovery_mode_active = FALSE,
                recovery_mode_entered_at = NULL,
                recovery_mode_reason = NULL
            WHERE user_id = p_user_id;

            v_result := jsonb_build_object(
                'action', 'exited',
                'reason', 'max_duration_7_days'
            );
        ELSIF v_consecutive_good_days >= 3 THEN
            -- Auto-exit: mood improved
            UPDATE user_settings
            SET
                recovery_mode_active = FALSE,
                recovery_mode_entered_at = NULL,
                recovery_mode_reason = NULL
            WHERE user_id = p_user_id;

            v_result := jsonb_build_object(
                'action', 'exited',
                'reason', 'mood_improved',
                'consecutive_good_days', v_consecutive_good_days
            );
        ELSE
            v_result := jsonb_build_object(
                'action', 'none',
                'reason', 'still_recovering',
                'days_in_recovery', EXTRACT(DAY FROM NOW() - v_entered_at)::INT,
                'consecutive_good_days', v_consecutive_good_days
            );
        END IF;
    END IF;

    RETURN v_result;
END;
$$;

-- Function to manually toggle recovery mode
-- Enforces 24h minimum duration when exiting
CREATE OR REPLACE FUNCTION toggle_recovery_mode(p_enable BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_current_state BOOLEAN;
    v_entered_at TIMESTAMPTZ;
    v_hours_elapsed INT;
    v_result JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_message', 'Not authenticated'
        );
    END IF;

    -- Get current state
    SELECT recovery_mode_active, recovery_mode_entered_at
    INTO v_current_state, v_entered_at
    FROM user_settings
    WHERE user_id = v_user_id;

    IF p_enable THEN
        -- Enabling recovery mode
        IF v_current_state THEN
            -- Already active
            RETURN jsonb_build_object(
                'success', true,
                'new_state', true,
                'entered_at', v_entered_at
            );
        END IF;

        UPDATE user_settings
        SET
            recovery_mode_active = TRUE,
            recovery_mode_entered_at = NOW(),
            recovery_mode_reason = 'manual'
        WHERE user_id = v_user_id
        RETURNING recovery_mode_entered_at INTO v_entered_at;

        RETURN jsonb_build_object(
            'success', true,
            'new_state', true,
            'entered_at', v_entered_at
        );
    ELSE
        -- Disabling recovery mode
        IF NOT v_current_state THEN
            -- Already inactive
            RETURN jsonb_build_object(
                'success', true,
                'new_state', false
            );
        END IF;

        -- Check 24h minimum duration
        v_hours_elapsed := EXTRACT(EPOCH FROM (NOW() - v_entered_at)) / 3600;

        IF v_hours_elapsed < 24 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error_message', 'Must wait 24 hours before exiting recovery mode',
                'new_state', true,
                'entered_at', v_entered_at,
                'hours_remaining', 24 - v_hours_elapsed
            );
        END IF;

        UPDATE user_settings
        SET
            recovery_mode_active = FALSE,
            recovery_mode_entered_at = NULL,
            recovery_mode_reason = NULL
        WHERE user_id = v_user_id;

        RETURN jsonb_build_object(
            'success', true,
            'new_state', false
        );
    END IF;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION evaluate_recovery_mode_for_user(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION toggle_recovery_mode(BOOLEAN) TO authenticated;
