-- A retained assessment must never acquire the account active at retry/transmission time.
-- Remove the ownerless overload so callers cannot bypass the expected-owner contract.
DROP FUNCTION public.submit_outcome_assessment(uuid, uuid, jsonb, text, text);

CREATE OR REPLACE FUNCTION public.submit_outcome_assessment(
    p_expected_user_id uuid, p_response_id uuid, p_template_id uuid, p_answers jsonb,
    p_notes text DEFAULT NULL, p_time_zone text DEFAULT 'UTC'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_template public.assessment_templates%ROWTYPE;
    v_response public.assessment_responses%ROWTYPE;
    v_schedule public.assessment_schedule%ROWTYPE;
    v_goal public.outcome_goals%ROWTYPE;
    v_scored jsonb;
    v_completed_at timestamptz := statement_timestamp();
    v_local_date date;
    v_frequency integer;
    v_target integer;
    v_max integer;
    v_baseline boolean;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
    END IF;
    IF p_expected_user_id IS DISTINCT FROM v_user_id THEN
        RAISE EXCEPTION 'Assessment owner changed' USING ERRCODE = '42501';
    END IF;
    IF p_response_id IS NULL OR p_template_id IS NULL
        OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_time_zone) THEN
        RAISE EXCEPTION 'Invalid submission identity or time zone' USING ERRCODE = '22023';
    END IF;
    -- Serialize submissions for this owner's instrument, including two simultaneous first responses.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'outcome:' || v_user_id::text || ':' || p_template_id::text, 0));
    SELECT * INTO v_response FROM public.assessment_responses
        WHERE id = p_response_id AND user_id = v_user_id;
    IF FOUND THEN
        IF v_response.assessment_template_id <> p_template_id
            OR v_response.answers IS DISTINCT FROM p_answers OR v_response.notes IS DISTINCT FROM p_notes THEN
            RAISE EXCEPTION 'Submission identifier already used for different answers' USING ERRCODE = '23505';
        END IF;
    ELSE
        SELECT * INTO STRICT v_template FROM public.assessment_templates
            WHERE id = p_template_id AND is_active;
        v_scored := public.score_outcome_assessment(p_template_id, p_answers);
        v_local_date := (v_completed_at AT TIME ZONE p_time_zone)::date;
        SELECT NOT EXISTS (SELECT 1 FROM public.assessment_responses
            WHERE user_id = v_user_id AND assessment_template_id = p_template_id) INTO v_baseline;

        INSERT INTO public.assessment_responses
            (id, user_id, assessment_template_id, answers, total_score, severity_level,
             is_baseline, notes, completed_at, scoring_version)
        VALUES (p_response_id, v_user_id, p_template_id, p_answers,
            (v_scored->>'total_score')::integer, v_scored->>'severity_level',
            v_baseline, p_notes, v_completed_at, 2)
        RETURNING * INTO v_response;

        IF v_scored->>'crisis_event_type' IS NOT NULL THEN
            INSERT INTO public.assessment_crisis_events
                (user_id, assessment_template_id, assessment_response_id, event_type, severity, context)
            VALUES (v_user_id, p_template_id, v_response.id, v_scored->>'crisis_event_type',
                'critical', jsonb_build_object('score', v_response.total_score));
        END IF;

        SELECT * INTO v_schedule FROM public.assessment_schedule
            WHERE user_id = v_user_id AND assessment_template_id = p_template_id FOR UPDATE;
        v_frequency := COALESCE(v_schedule.custom_frequency_days, v_template.recommended_frequency_days);
        IF v_frequency IS NULL OR v_frequency <= 0 THEN
            RAISE EXCEPTION 'Invalid assessment frequency' USING ERRCODE = '22023';
        END IF;
        INSERT INTO public.assessment_schedule
            (user_id, assessment_template_id, last_completed_at, next_due_at, reminder_sent)
        VALUES (v_user_id, p_template_id, v_completed_at,
            ((v_completed_at AT TIME ZONE p_time_zone) + make_interval(days => v_frequency)) AT TIME ZONE p_time_zone,
            false)
        ON CONFLICT (user_id, assessment_template_id) DO UPDATE SET
            last_completed_at = EXCLUDED.last_completed_at, next_due_at = EXCLUDED.next_due_at,
            reminder_sent = false;

        IF v_baseline THEN
            v_max := CASE v_template.code WHEN 'PHQ9' THEN 27 WHEN 'GAD7' THEN 21
                WHEN 'WHO5' THEN 25 WHEN 'PSS10' THEN 40 WHEN 'WEMWBS' THEN 70 END;
            v_target := CASE WHEN v_template.code IN ('WHO5', 'WEMWBS')
                THEN LEAST(v_max, v_response.total_score + GREATEST(5, v_response.total_score / 4))
                ELSE GREATEST(0, v_response.total_score - GREATEST(5, v_response.total_score / 4)) END;
            INSERT INTO public.outcome_goals
                (user_id, assessment_template_id, target_score, target_date, baseline_score,
                 baseline_date, baseline_response_id)
            VALUES (v_user_id, p_template_id, v_target, v_local_date + 84,
                v_response.total_score, v_local_date, v_response.id);
        END IF;
    END IF;

    SELECT * INTO v_schedule FROM public.assessment_schedule
        WHERE user_id = v_user_id AND assessment_template_id = p_template_id;
    SELECT * INTO v_goal FROM public.outcome_goals
        WHERE user_id = v_user_id AND baseline_response_id = v_response.id
        ORDER BY created_at, id LIMIT 1;
    RETURN jsonb_build_object('response', to_jsonb(v_response),
        'schedule', CASE WHEN v_schedule.id IS NULL THEN NULL ELSE to_jsonb(v_schedule) END,
        'goal', CASE WHEN v_goal.id IS NULL THEN NULL ELSE to_jsonb(v_goal) END);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_outcome_assessment(uuid, uuid, uuid, jsonb, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_outcome_assessment(uuid, uuid, uuid, jsonb, text, text) TO authenticated, service_role;
