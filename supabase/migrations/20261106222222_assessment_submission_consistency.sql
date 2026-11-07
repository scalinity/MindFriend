-- New submissions keep scoring, baseline selection, crisis linkage, goals and scheduling atomic.
-- Existing answers and derived scores are deliberately not rewritten by this migration.
ALTER TABLE public.assessment_responses ADD COLUMN IF NOT EXISTS scoring_version integer;
ALTER TABLE public.outcome_goals ADD COLUMN IF NOT EXISTS baseline_response_id uuid
    REFERENCES public.assessment_responses(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.score_outcome_assessment(p_template_id uuid, p_answers jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
    v_template public.assessment_templates%ROWTYPE;
    v_question jsonb;
    v_range jsonb;
    v_count integer;
    v_option_count integer;
    v_answer integer;
    v_total integer := 0;
    v_q9 integer := 0;
    v_severity text;
    v_event text;
BEGIN
    SELECT * INTO STRICT v_template FROM public.assessment_templates WHERE id = p_template_id;
    v_count := CASE v_template.code WHEN 'PHQ9' THEN 9 WHEN 'GAD7' THEN 7
        WHEN 'WHO5' THEN 5 WHEN 'PSS10' THEN 10 WHEN 'WEMWBS' THEN 14 END;
    v_option_count := CASE v_template.code WHEN 'PHQ9' THEN 4 WHEN 'GAD7' THEN 4
        WHEN 'WHO5' THEN 6 WHEN 'PSS10' THEN 5 WHEN 'WEMWBS' THEN 5 END;
    IF v_count IS NULL OR jsonb_typeof(v_template.questions) <> 'array'
        OR jsonb_array_length(v_template.questions) <> v_count THEN
        RAISE EXCEPTION 'Invalid assessment template' USING ERRCODE = '22023';
    END IF;
    IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'object' THEN
        RAISE EXCEPTION 'Answers must be an object' USING ERRCODE = '22023';
    END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(p_answers)) <> v_count
        OR (SELECT count(DISTINCT q->>'id') FROM jsonb_array_elements(v_template.questions) q) <> v_count
        OR (SELECT count(DISTINCT (q->>'number')::integer)
            FROM jsonb_array_elements(v_template.questions) q
            WHERE (q->>'number')::integer BETWEEN 1 AND v_count) <> v_count THEN
        RAISE EXCEPTION 'Answer every question exactly once' USING ERRCODE = '22023';
    END IF;
    FOR v_question IN SELECT value FROM jsonb_array_elements(v_template.questions)
    LOOP
        IF jsonb_typeof(v_question->'response_options') IS DISTINCT FROM 'array'
            OR jsonb_array_length(v_question->'response_options') <> v_option_count THEN
            RAISE EXCEPTION 'Invalid response options' USING ERRCODE = '22023';
        END IF;
        IF NOT (p_answers ? (v_question->>'id'))
            OR jsonb_typeof(p_answers->(v_question->>'id')) <> 'number'
            OR (p_answers->>(v_question->>'id')) !~ '^(0|[1-9][0-9]*)$' THEN
            RAISE EXCEPTION 'Invalid answer' USING ERRCODE = '22023';
        END IF;
        v_answer := (p_answers->>(v_question->>'id'))::integer;
        IF v_answer >= jsonb_array_length(v_question->'response_options') THEN
            RAISE EXCEPTION 'Answer outside allowed options' USING ERRCODE = '22023';
        END IF;
        IF v_template.code = 'PHQ9' AND (v_question->>'number')::integer = 9 THEN
            v_q9 := v_answer;
        END IF;
        v_total := v_total + CASE
            WHEN v_template.code = 'PSS10' AND (v_question->>'number')::integer IN (4, 5, 7, 8)
                THEN 4 - v_answer
            WHEN v_template.code = 'WEMWBS' THEN v_answer + 1
            ELSE v_answer END;
    END LOOP;
    FOR v_range IN SELECT value FROM jsonb_array_elements(v_template.scoring_ranges)
    LOOP
        IF v_total BETWEEN (v_range->>'min')::integer AND (v_range->>'max')::integer THEN
            v_severity := v_range->>'level';
            EXIT;
        END IF;
    END LOOP;
    IF v_severity IS NULL THEN
        RAISE EXCEPTION 'Score has no interpretation in this template' USING ERRCODE = '22023';
    END IF;
    v_event := CASE
        WHEN v_template.code = 'PHQ9' AND v_q9 > 0 THEN 'phq9_q9_scored'
        WHEN v_template.code = 'PHQ9' AND v_total >= 20 THEN 'depression_worsening'
        WHEN v_template.code = 'GAD7' AND v_total >= 15 THEN 'anxiety_spike'
        WHEN v_template.code = 'PSS10' AND v_total >= 27 THEN 'stress_exceeding_threshold'
        ELSE NULL END;
    RETURN jsonb_build_object('total_score', v_total, 'severity_level', v_severity,
        'crisis_event_type', v_event);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_outcome_assessment(
    p_response_id uuid, p_template_id uuid, p_answers jsonb,
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

REVOKE ALL ON FUNCTION public.score_outcome_assessment(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.submit_outcome_assessment(uuid, uuid, jsonb, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.score_outcome_assessment(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.submit_outcome_assessment(uuid, uuid, jsonb, text, text) TO authenticated, service_role;

COMMENT ON COLUMN public.assessment_responses.scoring_version IS
    '2: validated response-option indexes, including reversed PSS-10 items. NULL: existing score; preserve raw answers and recalculate on read.';
COMMENT ON COLUMN public.outcome_goals.baseline_response_id IS
    'Exact response supporting a newly created goal. Existing unlinked goals are retained and require review after score corrections.';
