\set ON_ERROR_STOP on
BEGIN;
-- Run before applying the provenance migration, in the empty task fixture only.
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'This test requires the empty restoration_synthetic database';
  END IF;
  IF EXISTS (SELECT FROM information_schema.columns WHERE table_schema='public'
    AND table_name='emotional_trajectories' AND column_name='measurement_status') THEN
    RAISE EXCEPTION 'Run the migration preservation test before applying the migration';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','efficacy@example.invalid','{}',now(),now());
INSERT INTO public.exercises(id,type,title,description,duration_seconds,duration_minutes) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','breathing','Synthetic breathing','Synthetic fixture',60,1);
INSERT INTO public.exercise_sessions(id,user_id,exercise_id,started_at) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now());
INSERT INTO public.emotional_trajectories(session_id,user_id,exercise_id,start_time,samples) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now(),
  '[{"composite_score":0.25,"hrv_reading":60,"nervous_system_state":"rest"}]');
INSERT INTO public.intervention_efficacy(user_id,exercise_id,session_id,completed_at,efficacy_score,net_emotional_change,trajectory_shape,starting_state,time_of_day,day_of_week) VALUES
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',now(),88.25,0.3,'flat','{"stressLevel":0.2}','morning',1);
INSERT INTO public.user_efficacy_profiles(user_id,exercise_id,overall_efficacy_score,completion_count,confidence) VALUES
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',88.25,5,0.25);
CREATE TEMP TABLE preserved_trajectories AS SELECT to_jsonb(t) AS value FROM public.emotional_trajectories t;
CREATE TEMP TABLE preserved_efficacy AS SELECT to_jsonb(t) AS value FROM public.intervention_efficacy t;
CREATE TEMP TABLE preserved_profiles AS SELECT to_jsonb(t) AS value FROM public.user_efficacy_profiles t;

\ir ../migrations/20261106224532_efficacy_measurement_provenance.sql

DO $$ BEGIN
  IF (SELECT to_jsonb(t)-'measurement_status'-'measurement_source' FROM public.emotional_trajectories t)
       IS DISTINCT FROM (SELECT value FROM preserved_trajectories) OR
     (SELECT to_jsonb(t)-'measurement_status'-'measurement_source' FROM public.intervention_efficacy t)
       IS DISTINCT FROM (SELECT value FROM preserved_efficacy) OR
     (SELECT to_jsonb(t)-'measurement_status' FROM public.user_efficacy_profiles t)
       IS DISTINCT FROM (SELECT value FROM preserved_profiles) THEN
    RAISE EXCEPTION 'Migration changed or deleted historical values';
  END IF;
  IF EXISTS (SELECT FROM public.emotional_trajectories WHERE measurement_status <> 'legacy_unverified' OR measurement_source IS NOT NULL) OR
     EXISTS (SELECT FROM public.intervention_efficacy WHERE measurement_status <> 'legacy_unverified' OR measurement_source IS NOT NULL) OR
     EXISTS (SELECT FROM public.user_efficacy_profiles WHERE measurement_status <> 'legacy_unverified') THEN
    RAISE EXCEPTION 'Migration invented provenance for historical records';
  END IF;
END $$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
SET LOCAL request.jwt.claim.role='authenticated';
SELECT public.complete_exercise_session('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',4,NULL);
SELECT public.award_exercise_session_xp('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2');
RESET ROLE;
DO $$ BEGIN
  IF (SELECT completed_at FROM public.exercise_sessions WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2') IS NULL OR
     (SELECT xp_total FROM public.user_stats WHERE user_id='11111111-1111-4111-8111-111111111111') <> 30 THEN
    RAISE EXCEPTION 'An exercise without measurements did not complete and receive XP';
  END IF;
  IF EXISTS (SELECT FROM public.emotional_trajectories WHERE session_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2') OR
     EXISTS (SELECT FROM public.intervention_efficacy WHERE session_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2') THEN
    RAISE EXCEPTION 'Ordinary completion fabricated measurements or efficacy';
  END IF;
  IF EXISTS (SELECT FROM public.intervention_efficacy WHERE measurement_status='observed') OR
     EXISTS (SELECT FROM public.user_efficacy_profiles WHERE measurement_status='observed') THEN
    RAISE EXCEPTION 'Historical records became eligible for observed efficacy';
  END IF;
END $$;
ROLLBACK;
\echo PASS: efficacy provenance preserves historical values; ordinary exercise completion needs no measurements
