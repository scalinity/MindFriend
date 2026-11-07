\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT IN ('assessment_submission_synthetic', 'restoration_synthetic')
      OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires an empty, isolated synthetic database';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('a1000000-0000-4000-8000-000000000001','authenticated','authenticated','assessment-a@example.invalid','{}',now(),now()),
 ('a1000000-0000-4000-8000-000000000002','authenticated','authenticated','assessment-b@example.invalid','{}',now(),now());
CREATE FUNCTION pg_temp.assessment_answers(code text, desired_score integer) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE q jsonb; result jsonb := '{}'; remaining integer := desired_score; value integer; cap integer;
BEGIN
  FOR q IN SELECT e.value FROM jsonb_array_elements((SELECT questions FROM public.assessment_templates t WHERE t.code=assessment_answers.code)) e
  LOOP
    cap := jsonb_array_length(q->'response_options') - 1;
    value := least(remaining,cap);
    remaining := remaining-value;
    IF code='PSS10' AND (q->>'number')::integer IN (4,5,7,8) THEN value:=4-value; END IF;
    result := result || jsonb_build_object(q->>'id',value);
  END LOOP;
  RETURN result;
END $$;
CREATE FUNCTION pg_temp.fail_assessment_schedule() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('mindfriend.fail_schedule',true)='true' THEN
    RAISE EXCEPTION 'Synthetic schedule failure' USING ERRCODE='ZX001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER synthetic_fail_schedule BEFORE INSERT OR UPDATE ON public.assessment_schedule
FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_assessment_schedule();
-- Preserve the exact initiating owner while the request authentication changes before execution.
CREATE TEMP TABLE assessment_before_owner_switch AS
SELECT 'responses' AS name, COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') AS rows FROM public.assessment_responses t
UNION ALL SELECT 'crisis',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM public.assessment_crisis_events t
UNION ALL SELECT 'goals',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM public.outcome_goals t
UNION ALL SELECT 'schedules',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM public.assessment_schedule t;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='a1000000-0000-4000-8000-000000000002';
SET LOCAL request.jwt.claim.role='authenticated';
DO $$
DECLARE phq uuid := (SELECT id FROM public.assessment_templates WHERE code='PHQ9'); attempt integer;
BEGIN
 IF to_regprocedure('public.submit_outcome_assessment(uuid,uuid,jsonb,text,text)') IS NOT NULL THEN
   RAISE EXCEPTION 'The ownerless overload remains callable';
 END IF;
 FOR attempt IN 1..2 LOOP
   BEGIN
     PERFORM public.submit_outcome_assessment('a1000000-0000-4000-8000-000000000001',
       'a2000000-0000-4000-8000-000000000080',phq,pg_temp.assessment_answers('PHQ9',0)||'{"9":1}',
       'Synthetic retained owner A note','America/New_York');
     RAISE EXCEPTION 'Owner A payload was accepted under owner B authentication';
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN
   PERFORM public.submit_outcome_assessment(NULL,gen_random_uuid(),phq,pg_temp.assessment_answers('PHQ9',0));
   RAISE EXCEPTION 'Missing expected owner was accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
BEGIN
 IF EXISTS (
   (SELECT 'responses' AS name,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') AS rows FROM public.assessment_responses t
    UNION ALL SELECT 'crisis',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM public.assessment_crisis_events t
    UNION ALL SELECT 'goals',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM public.outcome_goals t
    UNION ALL SELECT 'schedules',COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),'[]') FROM public.assessment_schedule t)
   EXCEPT SELECT name,rows FROM assessment_before_owner_switch
 ) THEN RAISE EXCEPTION 'An owner-mismatch request changed assessment data'; END IF;
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF has_function_privilege('public.submit_outcome_assessment(uuid,uuid,uuid,jsonb,text,text)','EXECUTE') THEN
   RAISE EXCEPTION 'Anonymous submission permitted';
 END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='a1000000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claim.role='authenticated';
DO $$
DECLARE
 phq uuid := (SELECT id FROM public.assessment_templates WHERE code='PHQ9');
 gad uuid := (SELECT id FROM public.assessment_templates WHERE code='GAD7');
 pss uuid := (SELECT id FROM public.assessment_templates WHERE code='PSS10');
 who uuid := (SELECT id FROM public.assessment_templates WHERE code='WHO5');
 answers jsonb; zeroes jsonb; fours jsonb; result jsonb; retry jsonb; r uuid; t integer;
BEGIN
 SELECT jsonb_object_agg(q->>'id',0),jsonb_object_agg(q->>'id',4) INTO zeroes,fours
 FROM jsonb_array_elements((SELECT questions FROM public.assessment_templates WHERE id=pss)) q;
 IF (public.score_outcome_assessment(pss,zeroes)->>'total_score')::integer<>16
    OR (public.score_outcome_assessment(pss,fours)->>'total_score')::integer<>24 THEN
   RAISE EXCEPTION 'PSS reverse scoring failed';
 END IF;
 FOREACH t IN ARRAY ARRAY[0,13,14,26,27,40] LOOP
   result:=public.score_outcome_assessment(pss,pg_temp.assessment_answers('PSS10',t));
   IF (result->>'total_score')::integer<>t OR result->>'severity_level'<>
       (CASE WHEN t<=13 THEN 'low' WHEN t<=26 THEN 'moderate' ELSE 'high' END) THEN
     RAISE EXCEPTION 'PSS boundary failed: %',result;
   END IF;
 END LOOP;
 BEGIN
   PERFORM public.score_outcome_assessment(pss,zeroes-'1');
   RAISE EXCEPTION 'Incomplete answers accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
   PERFORM public.score_outcome_assessment(pss,zeroes||'{"1":5}');
   RAISE EXCEPTION 'Out-of-range answer accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
   PERFORM public.score_outcome_assessment(pss,zeroes||'{"extra":0}');
   RAISE EXCEPTION 'Unknown question accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 answers:=pg_temp.assessment_answers('PHQ9',0)||'{"9":1}';
 result:=public.submit_outcome_assessment(auth.uid(),'a2000000-0000-4000-8000-000000000001',phq,answers,NULL,'America/New_York');
 retry:=public.submit_outcome_assessment(auth.uid(),'a2000000-0000-4000-8000-000000000001',phq,answers,NULL,'America/New_York');
 IF result<>retry OR (SELECT count(*) FROM public.assessment_responses)<>1
     OR (SELECT count(*) FROM public.assessment_crisis_events)<>1
     OR (SELECT count(*) FROM public.outcome_goals)<>1
     OR NOT (result->'response'->>'is_baseline')::boolean
     OR NOT EXISTS(SELECT FROM public.assessment_crisis_events WHERE assessment_response_id='a2000000-0000-4000-8000-000000000001' AND event_type='phq9_q9_scored') THEN
   RAISE EXCEPTION 'Crisis submission or exact retry is inconsistent';
 END IF;
 BEGIN
   PERFORM public.submit_outcome_assessment(auth.uid(),'a2000000-0000-4000-8000-000000000001',phq,pg_temp.assessment_answers('PHQ9',0));
   RAISE EXCEPTION 'Submission ID reused for different answers';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 result:=public.submit_outcome_assessment(auth.uid(),gen_random_uuid(),gad,pg_temp.assessment_answers('GAD7',15));
 IF NOT EXISTS(SELECT FROM public.assessment_crisis_events WHERE assessment_response_id=(result->'response'->>'id')::uuid AND event_type='anxiety_spike') THEN
   RAISE EXCEPTION 'GAD crisis event misclassified';
 END IF;
 result:=public.submit_outcome_assessment(auth.uid(),gen_random_uuid(),pss,pg_temp.assessment_answers('PSS10',27),NULL,'America/New_York');
 IF NOT EXISTS(SELECT FROM public.assessment_crisis_events WHERE assessment_response_id=(result->'response'->>'id')::uuid AND event_type='stress_exceeding_threshold')
    OR ((result->'schedule'->>'next_due_at')::timestamptz AT TIME ZONE 'America/New_York')<>
       ((result->'response'->>'completed_at')::timestamptz AT TIME ZONE 'America/New_York')+interval '7 days' THEN
   RAISE EXCEPTION 'PSS crisis or weekly schedule failed';
 END IF;
 UPDATE public.assessment_schedule SET custom_frequency_days=3 WHERE assessment_template_id=pss AND user_id=auth.uid();
 result:=public.submit_outcome_assessment(auth.uid(),gen_random_uuid(),pss,zeroes);
 IF (result->'schedule'->>'next_due_at')::timestamptz<>(result->'response'->>'completed_at')::timestamptz+interval '3 days' THEN
   RAISE EXCEPTION 'Custom frequency ignored';
 END IF;
 UPDATE public.assessment_responses SET completed_at=now()-interval '90 days' WHERE assessment_template_id=phq AND user_id=auth.uid();
 FOR t IN 1..11 LOOP
   result:=public.submit_outcome_assessment(auth.uid(),gen_random_uuid(),who,pg_temp.assessment_answers('WHO5',10));
 END LOOP;
 IF (result->'schedule'->>'next_due_at')::timestamptz<>(result->'response'->>'completed_at')::timestamptz+interval '7 days'
    OR NOT EXISTS(SELECT FROM public.outcome_goals WHERE assessment_template_id=who AND baseline_score=10 AND target_score=15) THEN
   RAISE EXCEPTION 'WHO weekly schedule or goal direction failed';
 END IF;
 result:=public.submit_outcome_assessment(auth.uid(),gen_random_uuid(),phq,pg_temp.assessment_answers('PHQ9',0));
 IF (result->'response'->>'is_baseline')::boolean
    OR (SELECT count(*) FROM public.outcome_goals WHERE assessment_template_id=phq)<>1 THEN
   RAISE EXCEPTION 'Display cache window created a duplicate baseline';
 END IF;
END $$;
SET LOCAL request.jwt.claim.sub='a1000000-0000-4000-8000-000000000002';
DO $$
DECLARE phq uuid := (SELECT id FROM public.assessment_templates WHERE code='PHQ9');
BEGIN
 BEGIN
   PERFORM public.submit_outcome_assessment(auth.uid(),'a2000000-0000-4000-8000-000000000001',phq,pg_temp.assessment_answers('PHQ9',0));
   RAISE EXCEPTION 'Cross-user submission ID was accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM set_config('mindfriend.fail_schedule','true',true);
 BEGIN
   PERFORM public.submit_outcome_assessment(auth.uid(),'a2000000-0000-4000-8000-000000000002',phq,pg_temp.assessment_answers('PHQ9',0)||'{"9":1}');
   RAISE EXCEPTION 'Failure injection did not run';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
 IF EXISTS(SELECT FROM public.assessment_responses) OR EXISTS(SELECT FROM public.assessment_crisis_events)
    OR EXISTS(SELECT FROM public.outcome_goals) THEN
   RAISE EXCEPTION 'Partial assessment state survived transaction failure';
 END IF;
 PERFORM set_config('mindfriend.fail_schedule','false',true);
 PERFORM public.submit_outcome_assessment(auth.uid(),'a2000000-0000-4000-8000-000000000002',phq,pg_temp.assessment_answers('PHQ9',0)||'{"9":1}');
 IF (SELECT count(*) FROM public.assessment_responses)<>1 OR (SELECT count(*) FROM public.assessment_crisis_events)<>1 THEN
   RAISE EXCEPTION 'Retry after rollback failed';
 END IF;
END $$;
ROLLBACK;
\echo 'PASS assessment scoring, crisis linkage, atomicity, retry, baseline, schedule and RLS'
