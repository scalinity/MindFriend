\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'This test requires the empty restoration_synthetic database';
  END IF;
END $$;
INSERT INTO auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
VALUES
  ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','restoration-a@example.invalid','{"full_name":"Synthetic A"}',now(),now()),
  ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','restoration-b@example.invalid','{"full_name":"Synthetic B"}',now(),now());
DO $$ BEGIN
  IF (SELECT count(*) FROM public.profiles) <> 2 OR
     (SELECT count(*) FROM public.user_settings) <> 2 OR
     (SELECT count(*) FROM public.user_stats) <> 2 THEN
    RAISE EXCEPTION 'Profile bootstrap did not create all required records';
  END IF;
END $$;
INSERT INTO public.conversations (id,user_id,title) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Synthetic A'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','Synthetic B');
INSERT INTO public.messages (conversation_id,role,content) VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','user','Fixture A'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','user','Fixture B');
INSERT INTO storage.buckets (id,name,public) VALUES ('mood-photos','mood-photos',false);
INSERT INTO storage.objects (bucket_id,name,owner,owner_id) VALUES
  ('mood-photos','11111111-1111-4111-8111-111111111111/fixture.png','11111111-1111-4111-8111-111111111111','11111111-1111-4111-8111-111111111111'),
  ('mood-photos','22222222-2222-4222-8222-222222222222/fixture.png','22222222-2222-4222-8222-222222222222','22222222-2222-4222-8222-222222222222');
INSERT INTO public.voice_sessions (id,user_id,voice_used,started_at) VALUES
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','11111111-1111-4111-8111-111111111111','ara',now()-interval '1 minute'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','22222222-2222-4222-8222-222222222222','ara',now()-interval '1 minute');
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF EXISTS (SELECT FROM public.conversations) OR EXISTS (SELECT FROM public.messages) THEN
    RAISE EXCEPTION 'Anonymous conversation content leaked';
  END IF;
  IF EXISTS (SELECT FROM storage.objects WHERE bucket_id='mood-photos') THEN
    RAISE EXCEPTION 'Anonymous private Storage metadata leaked';
  END IF;
  IF has_function_privilege('public.create_voice_session(uuid,text)','execute') OR
     has_function_privilege('public.check_and_increment_ai_quota(uuid,boolean)','execute') OR
     has_function_privilege('public.increment_voice_usage(uuid,double precision,date)','execute') THEN
    RAISE EXCEPTION 'Privileged service helper remains anonymous-callable';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
SET LOCAL request.jwt.claim.role = 'authenticated';
DO $$ BEGIN
  IF (SELECT count(*) FROM public.conversations) <> 1 OR (SELECT count(*) FROM public.messages) <> 1 THEN
    RAISE EXCEPTION 'Conversation/message owner isolation failed';
  END IF;
  IF EXISTS (SELECT FROM public.profiles WHERE id='22222222-2222-4222-8222-222222222222') THEN
    RAISE EXCEPTION 'Unconnected user profile leaked';
  END IF;
  IF (SELECT count(*) FROM storage.objects WHERE bucket_id='mood-photos') <> 1 THEN
    RAISE EXCEPTION 'Private Storage owner isolation failed';
  END IF;
  UPDATE public.profiles SET display_name='Edited synthetic name' WHERE id=auth.uid();
  BEGIN
    UPDATE public.profiles SET subscription_tier='premium' WHERE id=auth.uid();
    RAISE EXCEPTION 'Client self-upgrade allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE public.profiles SET daily_ai_used=0,daily_ai_quota=10000 WHERE id=auth.uid();
    RAISE EXCEPTION 'Client quota override allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO storage.objects (bucket_id,name,owner_id) VALUES ('mood-photos','22222222-2222-4222-8222-222222222222/forged.png','11111111-1111-4111-8111-111111111111');
    RAISE EXCEPTION 'Cross-user upload path allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.end_voice_session('dddddddd-dddd-4ddd-8ddd-dddddddddddd',60,1,false);
    RAISE EXCEPTION 'Cross-user voice accounting allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.end_voice_session('cccccccc-cccc-4ccc-8ccc-cccccccccccc',-60,1,false);
    RAISE EXCEPTION 'Negative voice usage allowed';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
SELECT public.end_voice_session('cccccccc-cccc-4ccc-8ccc-cccccccccccc',60,1,false);
SELECT public.end_voice_session('cccccccc-cccc-4ccc-8ccc-cccccccccccc',60,1,false);
RESET ROLE;
DO $$ BEGIN
  IF (SELECT minutes_used FROM public.voice_usage WHERE user_id='11111111-1111-4111-8111-111111111111') <> 1 THEN
    RAISE EXCEPTION 'Voice end replay double-counted usage';
  END IF;
END $$;
SET LOCAL ROLE service_role;
DO $$
DECLARE allowed boolean; i integer;
BEGIN
  BEGIN
    PERFORM public.check_and_increment_synthesis_quota('11111111-1111-4111-8111-111111111111',true,-1);
    RAISE EXCEPTION 'Negative synthesis reservation allowed';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  SELECT q.allowed INTO allowed FROM public.check_and_increment_synthesis_quota('11111111-1111-4111-8111-111111111111',true,1250000) q;
  IF NOT allowed THEN RAISE EXCEPTION 'Monthly reservation at the existing limit failed'; END IF;
  SELECT q.allowed INTO allowed FROM public.check_and_increment_synthesis_quota('11111111-1111-4111-8111-111111111111',true,1) q;
  IF allowed THEN RAISE EXCEPTION 'Monthly character allowance exceeded'; END IF;
  FOR i IN 1..10 LOOP
    SELECT q.allowed INTO allowed FROM public.check_and_increment_synthesis_quota('22222222-2222-4222-8222-222222222222',true,1) q;
    IF NOT allowed THEN RAISE EXCEPTION 'Existing daily allowance changed'; END IF;
  END LOOP;
  SELECT q.allowed INTO allowed FROM public.check_and_increment_synthesis_quota('22222222-2222-4222-8222-222222222222',true,1) q;
  IF allowed THEN RAISE EXCEPTION 'Daily synthesis allowance exceeded'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
\echo PASS: synthetic profile bootstrap, chat isolation, private Storage policies, voice accounting and synthesis reservations
