\set ON_ERROR_STOP on
BEGIN;
-- Synthetic-only fixture: never run against a database containing account data.
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'This test requires the empty restoration_synthetic database';
  END IF;
END $$;
INSERT INTO public.supported_languages(code,name,native_name,is_active)
VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','completion-a@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','completion-b@example.invalid','{}',now(),now());
INSERT INTO public.exercises (id,type,title,description,duration_seconds,duration_minutes) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','breathing','Synthetic breathing','Synthetic exercise',60,1),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab','grounding','Synthetic grounding','Synthetic exercise',60,1);
INSERT INTO public.exercise_sessions(id,user_id,exercise_id,started_at) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','22222222-2222-4222-8222-222222222222','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',now());
INSERT INTO public.programs(id,slug,title,description,duration_days,category) VALUES
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','completion-synthetic','Synthetic program','Synthetic fixture',2,'mindfulness');
INSERT INTO public.program_days(program_id,day_number,title,content,completion_criteria) VALUES
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',1,'Synthetic first day','[{"type":"practice","exercise_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}]','{"required":["practice"],"optional":[]}'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',2,'Synthetic final day','[{"type":"learn"}]','{"required":["learn"],"optional":[]}');
INSERT INTO public.program_enrollments(id,user_id,program_id,started_at) VALUES
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd1','11111111-1111-4111-8111-111111111111','cccccccc-cccc-4ccc-8ccc-cccccccccccc',now()-interval '1 minute'),
 ('dddddddd-dddd-4ddd-8ddd-ddddddddddd2','22222222-2222-4222-8222-222222222222','cccccccc-cccc-4ccc-8ccc-cccccccccccc',now()-interval '1 minute');
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF has_function_privilege('public.complete_exercise_session(uuid,integer,text)','execute') OR
     has_function_privilege('public.award_exercise_session_xp(uuid)','execute') OR
     has_function_privilege('public.complete_program_day(uuid,integer,jsonb,text,text,uuid,integer,integer)','execute') THEN
    RAISE EXCEPTION 'Anonymous completion endpoint exposed';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
SET LOCAL request.jwt.claim.role='authenticated';
DO $$ BEGIN
  BEGIN
    PERFORM public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',4,NULL);
    RAISE EXCEPTION 'Cross-owner exercise completion accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',6,NULL);
    RAISE EXCEPTION 'Invalid exercise rating accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd2',1,'{"practice":true}');
    RAISE EXCEPTION 'Cross-owner enrollment completion accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',2,'{"learn":true}');
    RAISE EXCEPTION 'Future final-day completion accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":false}');
    RAISE EXCEPTION 'False required completion accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}');
    RAISE EXCEPTION 'Practice without a completed session accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF (SELECT total_exercises_completed FROM public.user_stats WHERE user_id=auth.uid()) <> 0 THEN
    RAISE EXCEPTION 'Rejected completion changed count';
  END IF;
  BEGIN
    PERFORM public.award_exercise_session_xp('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2');
    RAISE EXCEPTION 'Cross-owner XP award accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.award_exercise_session_xp('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
    RAISE EXCEPTION 'Unfinished exercise XP award accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF NOT public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',4,'Synthetic note') THEN
    RAISE EXCEPTION 'First session completion not recorded';
  END IF;
  IF public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',2,'Replacement must not overwrite') THEN
    RAISE EXCEPTION 'Exercise retry recorded a second completion';
  END IF;
  IF (SELECT total_exercises_completed FROM public.user_stats WHERE user_id=auth.uid()) <> 1 OR
     (SELECT note FROM public.exercise_sessions WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1') <> 'Synthetic note' THEN
    RAISE EXCEPTION 'Exercise retry changed count or original content';
  END IF;
  BEGIN
    PERFORM public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}',NULL,NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2');
    RAISE EXCEPTION 'Cross-owner practice session accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',NULL,NULL);
  BEGIN
    PERFORM public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}',NULL,NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3');
    RAISE EXCEPTION 'Wrong exercise session accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
-- Reproduce the old partial failure: a persisted completion with an unrepaired count.
INSERT INTO public.exercise_sessions(id,user_id,exercise_id,started_at,completed_at,note) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now(),now(),'Original synthetic content');
SET LOCAL ROLE authenticated;
DO $$ DECLARE new_completion boolean;
BEGIN
  -- Read assertions in a separate statement after the volatile RPC has written.
  new_completion := public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',NULL,NULL);
  IF new_completion OR
     (SELECT total_exercises_completed FROM public.user_stats WHERE user_id=auth.uid()) <> 3 OR
     (SELECT note FROM public.exercise_sessions WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4') <> 'Original synthetic content' THEN
    RAISE EXCEPTION 'Legacy partial completion was not repaired without overwriting content';
  END IF;
END $$;
DO $$ DECLARE xp_before integer; first_amount integer; retry_amount integer;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id=auth.uid();
  SELECT amount INTO first_amount FROM public.award_exercise_session_xp('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
  SELECT amount INTO retry_amount FROM public.award_exercise_session_xp('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
  IF first_amount <> 30 OR retry_amount <> 0 OR
     (SELECT xp_total FROM public.user_stats WHERE user_id=auth.uid()) <> xp_before + 30 OR
     (SELECT exercises_completed FROM public.skill_progress WHERE user_id=auth.uid() AND skill_type='breathing') <> 1 THEN
    RAISE EXCEPTION 'Exercise XP retry changed the 30 XP reward or skill count';
  END IF;
END $$;
SELECT public.save_program_day_progress('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}',NULL,NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
SELECT public.save_program_day_progress('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}',NULL,NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
SELECT public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}',NULL,NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
SELECT public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',1,'{"practice":true}',NULL,NULL,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
DO $$ BEGIN
  IF (SELECT current_day FROM public.program_enrollments WHERE id='dddddddd-dddd-4ddd-8ddd-ddddddddddd1') <> 2 OR
     (SELECT streak_days FROM public.program_enrollments WHERE id='dddddddd-dddd-4ddd-8ddd-ddddddddddd1') <> 1 THEN
    RAISE EXCEPTION 'Intermediate day retry advanced the program twice';
  END IF;
END $$;
DO $$ DECLARE first_result jsonb; replay_result jsonb; xp_before integer;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id=auth.uid();
  first_result := public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',2,'{"learn":true}');
  replay_result := public.complete_program_day('dddddddd-dddd-4ddd-8ddd-ddddddddddd1',2,'{"learn":true}');
  IF first_result->>'certificate_number' IS NULL OR first_result <> replay_result THEN
    RAISE EXCEPTION 'Final completion retry did not return its persisted certificate';
  END IF;
  IF (SELECT count(*) FROM public.program_certificates WHERE enrollment_id='dddddddd-dddd-4ddd-8ddd-ddddddddddd1') <> 1 OR
     (SELECT certificate_number FROM public.program_certificates WHERE enrollment_id='dddddddd-dddd-4ddd-8ddd-ddddddddddd1') <> first_result->>'certificate_number' OR
     (SELECT streak_days FROM public.program_enrollments WHERE id='dddddddd-dddd-4ddd-8ddd-ddddddddddd1') <> 2 OR
     (SELECT xp_total FROM public.user_stats WHERE user_id=auth.uid()) <> xp_before + 200 THEN
    RAISE EXCEPTION 'Final completion retry changed certificate, streak, or 200 XP reward';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$ BEGIN
  IF EXISTS (SELECT FROM public.program_certificates) THEN
    RAISE EXCEPTION 'Certificate list leaked across owners';
  END IF;
END $$;
RESET ROLE;
ROLLBACK;
\echo PASS: completion ownership, invalid inputs, real practice, retry counts, persisted certificate, and program XP
