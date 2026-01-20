-- Recovery Mode UX Feature
-- Adds server-side recovery mode state to user_settings
-- See: kimispecs/03-recovery-mode-ux-spec.md

-- Add recovery mode columns to user_settings
ALTER TABLE user_settings
ADD COLUMN IF NOT EXISTS recovery_mode_active BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS recovery_mode_entered_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS recovery_mode_reason TEXT CHECK (recovery_mode_reason IN ('manual', 'auto_consecutive_low_mood'));

-- Index for cron job performance (only query active recovery modes)
CREATE INDEX IF NOT EXISTS idx_user_settings_recovery_active
ON user_settings(recovery_mode_active)
WHERE recovery_mode_active = TRUE;

-- Function to evaluate and update recovery mode for a single user
-- Called by the evaluate-recovery-mode Edge Function cron job
CREATE OR REPLACE FUNCTION evaluate_recovery_mode_for_user(p_user_id UUID)
RETURNS TABLE(
    action TEXT,
    reason TEXT,
    previous_state BOOLEAN,
    new_state BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_active BOOLEAN;
    v_entered_at TIMESTAMPTZ;
    v_mode_reason TEXT;
    v_consecutive_low_days INT;
    v_recent_high_moods INT;
    v_action TEXT := 'none';
    v_reason TEXT := '';
BEGIN
    -- Get current recovery mode state
    SELECT
        COALESCE(recovery_mode_active, FALSE),
        recovery_mode_entered_at,
        recovery_mode_reason
    INTO v_current_active, v_entered_at, v_mode_reason
    FROM user_settings
    WHERE user_id = p_user_id;

    -- If no user_settings row exists, create one
    IF NOT FOUND THEN
        INSERT INTO user_settings (user_id, recovery_mode_active)
        VALUES (p_user_id, FALSE)
        ON CONFLICT (user_id) DO NOTHING;
        v_current_active := FALSE;
    END IF;

    -- Calculate consecutive low mood days (mood_score <= 2)
    SELECT COUNT(*)
    INTO v_consecutive_low_days
    FROM (
        SELECT local_date
        FROM moods
        WHERE user_id = p_user_id
          AND mood_score <= 2
          AND created_at >= NOW() - INTERVAL '7 days'
        ORDER BY local_date DESC
        LIMIT 3
    ) sub
    WHERE (
        -- Check these are the 3 most recent days
        SELECT COUNT(DISTINCT local_date) = 3
        FROM moods
        WHERE user_id = p_user_id
          AND mood_score <= 2
          AND created_at >= NOW() - INTERVAL '7 days'
    );

    -- More robust consecutive check using the mood trend helper
    SELECT consecutive_low_mood_days
    INTO v_consecutive_low_days
    FROM calculate_mood_trend(p_user_id);

    -- Check for entry condition: not active AND 3+ consecutive low mood days
    IF NOT v_current_active AND v_consecutive_low_days >= 3 THEN
        UPDATE user_settings
        SET recovery_mode_active = TRUE,
            recovery_mode_entered_at = NOW(),
            recovery_mode_reason = 'auto_consecutive_low_mood',
            updated_at = NOW()
        WHERE user_id = p_user_id;

        v_action := 'enter';
        v_reason := 'consecutive_low_mood_days >= 3';

        RETURN QUERY SELECT v_action, v_reason, v_current_active, TRUE;
        RETURN;
    END IF;

    -- Check for exit condition: active AND auto-triggered AND >24h elapsed
    IF v_current_active AND v_mode_reason = 'auto_consecutive_low_mood' THEN
        -- Calculate elapsed time
        IF v_entered_at IS NOT NULL AND NOW() - v_entered_at >= INTERVAL '24 hours' THEN
            -- Count recent moods >= 4 in the last 3 entries
            SELECT COUNT(*)
            INTO v_recent_high_moods
            FROM (
                SELECT mood_score
                FROM moods
                WHERE user_id = p_user_id
                ORDER BY created_at DESC
                LIMIT 3
            ) recent
            WHERE mood_score >= 4;

            -- Auto-exit if 3 consecutive high moods
            IF v_recent_high_moods >= 3 THEN
                UPDATE user_settings
                SET recovery_mode_active = FALSE,
                    recovery_mode_entered_at = NULL,
                    recovery_mode_reason = NULL,
                    updated_at = NOW()
                WHERE user_id = p_user_id;

                v_action := 'exit';
                v_reason := '3_consecutive_high_moods';

                RETURN QUERY SELECT v_action, v_reason, v_current_active, FALSE;
                RETURN;
            END IF;
        END IF;

        -- Force exit after 7 days regardless
        IF v_entered_at IS NOT NULL AND NOW() - v_entered_at >= INTERVAL '7 days' THEN
            UPDATE user_settings
            SET recovery_mode_active = FALSE,
                recovery_mode_entered_at = NULL,
                recovery_mode_reason = NULL,
                updated_at = NOW()
            WHERE user_id = p_user_id;

            v_action := 'exit';
            v_reason := '7_day_timeout';

            RETURN QUERY SELECT v_action, v_reason, v_current_active, FALSE;
            RETURN;
        END IF;
    END IF;

    -- No action taken
    RETURN QUERY SELECT v_action, v_reason, v_current_active, v_current_active;
END;
$$;

-- Function to toggle recovery mode manually
-- Enforces 24h minimum duration rule for exits
CREATE OR REPLACE FUNCTION toggle_recovery_mode(p_enable BOOLEAN)
RETURNS TABLE(
    success BOOLEAN,
    error_message TEXT,
    new_state BOOLEAN,
    entered_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_active BOOLEAN;
    v_entered_at TIMESTAMPTZ;
    v_user_id UUID := auth.uid();
BEGIN
    -- Get current state
    SELECT recovery_mode_active, recovery_mode_entered_at
    INTO v_current_active, v_entered_at
    FROM user_settings
    WHERE user_id = v_user_id;

    -- Handle enable request
    IF p_enable THEN
        -- If already active, just return current state
        IF v_current_active THEN
            RETURN QUERY SELECT TRUE, NULL::TEXT, v_current_active, v_entered_at;
            RETURN;
        END IF;

        -- Enable recovery mode
        UPDATE user_settings
        SET recovery_mode_active = TRUE,
            recovery_mode_entered_at = NOW(),
            recovery_mode_reason = 'manual',
            updated_at = NOW()
        WHERE user_id = v_user_id;

        RETURN QUERY SELECT TRUE, NULL::TEXT, TRUE, NOW();
        RETURN;
    END IF;

    -- Handle disable request
    IF NOT p_enable THEN
        -- If already inactive, just return current state
        IF NOT v_current_active THEN
            RETURN QUERY SELECT TRUE, NULL::TEXT, FALSE, NULL::TIMESTAMPTZ;
            RETURN;
        END IF;

        -- Check 24h minimum duration
        IF v_entered_at IS NOT NULL AND NOW() - v_entered_at < INTERVAL '24 hours' THEN
            RETURN QUERY SELECT FALSE, 'Must wait 24 hours before exiting recovery mode', v_current_active, v_entered_at;
            RETURN;
        END IF;

        -- Disable recovery mode
        UPDATE user_settings
        SET recovery_mode_active = FALSE,
            recovery_mode_entered_at = NULL,
            recovery_mode_reason = NULL,
            updated_at = NOW()
        WHERE user_id = v_user_id;

        RETURN QUERY SELECT TRUE, NULL::TEXT, FALSE, NULL::TIMESTAMPTZ;
        RETURN;
    END IF;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION toggle_recovery_mode(BOOLEAN) TO authenticated;

-- Comment documenting the feature
COMMENT ON COLUMN user_settings.recovery_mode_active IS 'Whether recovery mode UX is currently enabled for this user';
COMMENT ON COLUMN user_settings.recovery_mode_entered_at IS 'Timestamp when recovery mode was entered (for 24h minimum duration)';
COMMENT ON COLUMN user_settings.recovery_mode_reason IS 'Reason for entering recovery mode: manual or auto_consecutive_low_mood';
