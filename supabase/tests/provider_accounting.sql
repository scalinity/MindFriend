\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database()<>'restoration_synthetic' OR EXISTS(SELECT FROM auth.users) THEN
  RAISE EXCEPTION 'Requires the empty schema-only restoration_synthetic database';
 END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at)
 VALUES('11111111-1111-4111-8111-111111111111','authenticated','authenticated','accounting-fixture@example.invalid','{}',now(),now());
SET LOCAL ROLE service_role;
DO $$ BEGIN
 IF NOT public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111')
 OR NOT public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111')
 OR public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111') THEN
  RAISE EXCEPTION 'Image quota failed to enforce the existing free allowance';
 END IF;
 BEGIN
  INSERT INTO public.synthesis_requests(user_id,character_count)
   VALUES('11111111-1111-4111-8111-111111111111',-1);
  RAISE EXCEPTION 'Negative synthesis credit accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  PERFORM public.increment_voice_quota(-1);
  RAISE EXCEPTION 'Negative voice credit accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
DO $$ DECLARE q record; i integer; BEGIN
 SELECT * INTO q FROM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',3);
 IF NOT q.allowed OR q.voice_minutes_used<>3 OR q.voice_minutes_limit<>5 THEN RAISE EXCEPTION 'Free voice reservation failed'; END IF;
 SELECT * INTO q FROM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',2);
 IF NOT q.allowed OR q.voice_minutes_used<>5 THEN RAISE EXCEPTION 'Free voice boundary failed'; END IF;
 SELECT * INTO q FROM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',1);
 IF q.allowed THEN RAISE EXCEPTION 'Free voice exceeded allowance'; END IF;
 BEGIN
  PERFORM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',-1);
  RAISE EXCEPTION 'Negative voice reservation allowed';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 INSERT INTO public.subscriptions(user_id,product_id,original_transaction_id,status,expires_at)
 VALUES('11111111-1111-4111-8111-111111111111','synthetic-premium','synthetic-transaction','active',now()+interval '1 day');
 FOR i IN 1..5 LOOP
  SELECT * INTO q FROM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',10);
  IF NOT q.allowed OR q.voice_minutes_limit<>60 THEN RAISE EXCEPTION 'Premium voice reservation failed'; END IF;
 END LOOP;
 SELECT * INTO q FROM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',5);
 IF NOT q.allowed OR q.voice_minutes_used<>60 THEN RAISE EXCEPTION 'Premium voice boundary failed'; END IF;
 SELECT * INTO q FROM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',1);
 IF q.allowed THEN RAISE EXCEPTION 'Premium voice exceeded allowance'; END IF;
 FOR i IN 3..20 LOOP
  IF NOT public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111') THEN RAISE EXCEPTION 'Premium image allowance failed'; END IF;
 END LOOP;
 IF public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111') THEN RAISE EXCEPTION 'Premium images exceeded allowance'; END IF;
 UPDATE public.subscriptions SET expires_at=now()-interval '1 day';
 IF public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111') THEN RAISE EXCEPTION 'Expired subscription granted premium images'; END IF;
 UPDATE public.creative_quota_usage SET ai_art_count=2 WHERE user_id='11111111-1111-4111-8111-111111111111';
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN
  PERFORM public.reserve_ai_image_quota('11111111-1111-4111-8111-111111111111');
  RAISE EXCEPTION 'Anonymous image reservation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.synthesis_requests(user_id,character_count)
   VALUES('11111111-1111-4111-8111-111111111111',0);
  RAISE EXCEPTION 'Anonymous synthesis insert allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE q record; BEGIN
 SELECT * INTO q FROM public.get_creative_quota();
 IF q.ai_art_count<>2 OR q.ai_art_limit<>2 THEN RAISE EXCEPTION 'Owner quota read broke'; END IF;
 BEGIN
  UPDATE public.creative_quota_usage SET ai_art_count=0 WHERE user_id=auth.uid();
  RAISE EXCEPTION 'Owner counter reset allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM public.creative_quota_usage WHERE user_id=auth.uid();
  RAISE EXCEPTION 'Owner counter deletion allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.reserve_voice_journal_quota('11111111-1111-4111-8111-111111111111',1);
  RAISE EXCEPTION 'Client voice reservation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.reserve_ai_image_quota('22222222-2222-4222-8222-222222222222');
  RAISE EXCEPTION 'Cross-user image accounting allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.synthesis_requests(user_id,character_count) VALUES(auth.uid(),0);
  RAISE EXCEPTION 'Client synthesis accounting allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.increment_voice_quota(1);
  RAISE EXCEPTION 'Client voice accounting allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
