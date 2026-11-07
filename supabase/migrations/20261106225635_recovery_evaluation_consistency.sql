-- Evaluate actual recorded mood days and return one explicit state-transition object.
-- Caller-scoped execution preserves RLS; only the service role may evaluate another account.
CREATE OR REPLACE FUNCTION public.evaluate_recovery_mode_for_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
    v_current_state boolean;
    v_new_state boolean;
    v_entered_at timestamptz;
    v_time_zone text;
    v_today date;
    v_expected_date date;
    v_consecutive_low_days integer := 0;
    v_consecutive_good_days integer := 0;
    v_low_chain boolean := true;
    v_good_chain boolean := true;
    v_mood record;
    v_action text := 'none';
    v_reason text;
BEGIN
    IF p_user_id IS NULL OR
        (current_user <> 'service_role' AND auth.uid() IS DISTINCT FROM p_user_id) THEN
        RAISE EXCEPTION 'Can only evaluate own recovery state' USING ERRCODE = '42501';
    END IF;

    SELECT s.recovery_mode_active, s.recovery_mode_entered_at,
        COALESCE(NULLIF(p.timezone, ''), NULLIF(s.timezone, ''), 'UTC')
    INTO v_current_state, v_entered_at, v_time_zone
    FROM public.user_settings s
    LEFT JOIN public.profiles p ON p.id = s.user_id
    WHERE s.user_id = p_user_id
    FOR UPDATE OF s;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recovery settings not found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_time_zone) THEN
        v_time_zone := 'UTC';
    END IF;
    v_today := (statement_timestamp() AT TIME ZONE v_time_zone)::date;
    v_new_state := v_current_state;

    -- A day contributes its mean of all recorded observations, never one count per row.
    -- Start at today or yesterday (before today's first check-in). A missing day breaks both chains.
    FOR v_mood IN
        SELECT local_date, avg(mood_score) AS daily_score
        FROM public.moods
        WHERE user_id = p_user_id AND local_date BETWEEN v_today - 7 AND v_today
        GROUP BY local_date
        ORDER BY local_date DESC
    LOOP
        IF v_expected_date IS NULL THEN
            EXIT WHEN v_mood.local_date < v_today - 1;
            v_expected_date := v_mood.local_date;
        END IF;
        EXIT WHEN v_mood.local_date <> v_expected_date;
        IF v_low_chain AND v_mood.daily_score <= 2 THEN
            v_consecutive_low_days := v_consecutive_low_days + 1;
        ELSE
            v_low_chain := false;
        END IF;
        IF v_good_chain AND v_mood.daily_score >= 4 THEN
            v_consecutive_good_days := v_consecutive_good_days + 1;
        ELSE
            v_good_chain := false;
        END IF;
        EXIT WHEN NOT v_low_chain AND NOT v_good_chain;
        v_expected_date := v_expected_date - 1;
    END LOOP;

    IF NOT v_current_state THEN
        v_reason := 'no_trigger';
        IF v_consecutive_low_days >= 3 THEN
            v_action := 'enter';
            v_reason := 'auto_consecutive_low_mood';
            v_new_state := true;
            UPDATE public.user_settings SET recovery_mode_active = true,
                recovery_mode_entered_at = statement_timestamp(), recovery_mode_reason = v_reason
            WHERE user_id = p_user_id;
        END IF;
    ELSE
        v_reason := 'still_recovering';
        IF v_entered_at IS NOT NULL AND statement_timestamp() - v_entered_at >= interval '7 days' THEN
            v_action := 'exit';
            v_reason := 'max_duration_7_days';
        ELSIF v_consecutive_good_days >= 3 THEN
            v_action := 'exit';
            v_reason := 'mood_improved';
        END IF;
        IF v_action = 'exit' THEN
            v_new_state := false;
            UPDATE public.user_settings SET recovery_mode_active = false,
                recovery_mode_entered_at = NULL, recovery_mode_reason = NULL
            WHERE user_id = p_user_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('action', v_action, 'reason', v_reason,
        'previous_state', v_current_state, 'new_state', v_new_state,
        'consecutive_low_days', v_consecutive_low_days,
        'consecutive_good_days', v_consecutive_good_days);
END;
$$;
REVOKE ALL ON FUNCTION public.evaluate_recovery_mode_for_user(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.evaluate_recovery_mode_for_user(uuid) TO authenticated, service_role;
