\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT IN ('assessment_submission_synthetic','restoration_synthetic') OR EXISTS(SELECT FROM auth.users) THEN
  RAISE EXCEPTION 'Requires an empty isolated synthetic database';
 END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at)
SELECT ('b1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
 'recovery-'||n||'@example.invalid','{}',now(),now() FROM generate_series(1,6) n;
UPDATE public.profiles SET timezone='UTC' WHERE email LIKE 'recovery-%@example.invalid';
INSERT INTO public.moods(user_id,local_date,mood_score)
SELECT 'b1000000-0000-4000-8000-000000000001', (now() AT TIME ZONE 'UTC')::date-n,2 FROM generate_series(0,2) n;
INSERT INTO public.moods(user_id,local_date,mood_score)
SELECT 'b1000000-0000-4000-8000-000000000002', (now() AT TIME ZONE 'UTC')::date-n,1 FROM unnest(ARRAY[0,2,4]) n;
INSERT INTO public.moods(user_id,local_date,mood_score)
SELECT 'b1000000-0000-4000-8000-000000000003', (now() AT TIME ZONE 'UTC')::date-n,1 FROM generate_series(5,7) n;
UPDATE public.user_settings SET recovery_mode_active=true,recovery_mode_entered_at=now()-interval '8 days',recovery_mode_reason='auto_consecutive_low_mood'
WHERE user_id='b1000000-0000-4000-8000-000000000004';
INSERT INTO public.moods(user_id,local_date,mood_score,created_at)
VALUES ('b1000000-0000-4000-8000-000000000004',(now() AT TIME ZONE 'UTC')::date-10,1,now()-interval '10 days');
UPDATE public.user_settings SET recovery_mode_active=true,recovery_mode_entered_at=now()-interval '2 days',recovery_mode_reason='auto_consecutive_low_mood'
WHERE user_id='b1000000-0000-4000-8000-000000000005';
INSERT INTO public.moods(user_id,local_date,mood_score)
SELECT 'b1000000-0000-4000-8000-000000000005', (now() AT TIME ZONE 'UTC')::date-n,4 FROM unnest(ARRAY[0,2,4]) n;
UPDATE public.profiles SET timezone='Pacific/Kiritimati' WHERE id='b1000000-0000-4000-8000-000000000006';
INSERT INTO public.moods(user_id,local_date,mood_score)
SELECT 'b1000000-0000-4000-8000-000000000006', (now() AT TIME ZONE 'Pacific/Kiritimati')::date-n,2 FROM generate_series(0,2) n;
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF has_function_privilege('public.evaluate_recovery_mode_for_user(uuid)','execute') THEN RAISE EXCEPTION 'Anonymous RPC is exposed'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='b1000000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claim.role='authenticated';
DO $$
DECLARE r jsonb;
BEGIN
 r:=public.evaluate_recovery_mode_for_user(auth.uid());
 IF r->>'action'<>'enter' OR (r->>'previous_state')::boolean OR NOT (r->>'new_state')::boolean
    OR (r->>'consecutive_low_days')::integer<>3 THEN RAISE EXCEPTION 'Entry contract failed: %',r; END IF;
 r:=public.evaluate_recovery_mode_for_user(auth.uid());
 IF r->>'action'<>'none' OR NOT (r->>'previous_state')::boolean OR NOT (r->>'new_state')::boolean THEN
  RAISE EXCEPTION 'Unchanged active state contract failed: %',r;
 END IF;
 BEGIN
  PERFORM public.evaluate_recovery_mode_for_user('b1000000-0000-4000-8000-000000000002');
  RAISE EXCEPTION 'Cross-user evaluation accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SET LOCAL request.jwt.claim.sub='b1000000-0000-4000-8000-000000000002';
DO $$
DECLARE r jsonb;
BEGIN
 r:=public.evaluate_recovery_mode_for_user(auth.uid());
 IF r->>'action'<>'none' OR (r->>'consecutive_low_days')::integer<>1 THEN RAISE EXCEPTION 'Missing dates did not break chain'; END IF;
 -- The actual schema permits only one mood row per user/date; a same-day update still counts once.
 BEGIN
  INSERT INTO public.moods(user_id,local_date,mood_score) VALUES(auth.uid(),(now() AT TIME ZONE 'UTC')::date,1);
  RAISE EXCEPTION 'Expected unique user/date constraint';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 INSERT INTO public.moods(user_id,local_date,mood_score) VALUES(auth.uid(),(now() AT TIME ZONE 'UTC')::date-1,4);
 r:=public.evaluate_recovery_mode_for_user(auth.uid());
 IF r->>'action'<>'none' OR (r->>'consecutive_low_days')::integer<>1 THEN RAISE EXCEPTION 'Non-low day did not break chain'; END IF;
 UPDATE public.moods SET mood_score=1 WHERE user_id=auth.uid() AND local_date=(now() AT TIME ZONE 'UTC')::date-1;
 r:=public.evaluate_recovery_mode_for_user(auth.uid());
 IF r->>'action'<>'enter' OR (r->>'consecutive_low_days')::integer<>3 THEN RAISE EXCEPTION 'Recorded local-date update not respected'; END IF;
END $$;
SET LOCAL request.jwt.claim.sub='b1000000-0000-4000-8000-000000000003';
DO $$ DECLARE r jsonb; BEGIN
 r:=public.evaluate_recovery_mode_for_user(auth.uid());
 IF r->>'action'<>'none' OR (r->>'consecutive_low_days')::integer<>0 THEN RAISE EXCEPTION 'Stale low days triggered recovery'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claim.role='service_role';
SET LOCAL request.jwt.claim.sub='';
DO $$ DECLARE r jsonb; BEGIN
 r:=public.evaluate_recovery_mode_for_user('b1000000-0000-4000-8000-000000000004');
 IF r->>'action'<>'exit' OR r->>'reason'<>'max_duration_7_days' OR NOT (r->>'previous_state')::boolean
    OR (r->>'new_state')::boolean THEN RAISE EXCEPTION 'Expiry without recent mood failed: %',r; END IF;
 r:=public.evaluate_recovery_mode_for_user('b1000000-0000-4000-8000-000000000005');
 IF r->>'action'<>'none' OR (r->>'consecutive_good_days')::integer<>1 THEN RAISE EXCEPTION 'Gaps did not break good-day chain'; END IF;
 INSERT INTO public.moods(user_id,local_date,mood_score) VALUES('b1000000-0000-4000-8000-000000000005',(now() AT TIME ZONE 'UTC')::date-1,4);
 r:=public.evaluate_recovery_mode_for_user('b1000000-0000-4000-8000-000000000005');
 IF r->>'action'<>'exit' OR r->>'reason'<>'mood_improved' OR (r->>'consecutive_good_days')::integer<>3 THEN
  RAISE EXCEPTION 'Consecutive good dates did not exit: %',r;
 END IF;
 r:=public.evaluate_recovery_mode_for_user('b1000000-0000-4000-8000-000000000006');
 IF r->>'action'<>'enter' THEN RAISE EXCEPTION 'Profile local dates not evaluated: %',r; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.role='authenticated';
DO $$ BEGIN
 BEGIN
  PERFORM public.evaluate_recovery_mode_for_user('b1000000-0000-4000-8000-000000000001');
  RAISE EXCEPTION 'Missing authenticated identity accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo 'PASS recovery schema, contract, consecutive dates, expiry and owner/service authorization'
