\set ON_ERROR_STOP on
BEGIN;
-- Refuse any database not explicitly owned by this synthetic-only task.
DO $$ BEGIN
  IF current_database() <> 'support_session_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires empty support_session_synthetic database';
  END IF;
END $$;
INSERT INTO public.supported_languages(code,name,native_name,is_active)
VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','consent-a@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','consent-b@example.invalid','{}',now(),now());
DO $$ BEGIN
  IF (SELECT count(*) FROM public.profiles WHERE id IN (
    '11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222')) <> 2 THEN
    RAISE EXCEPTION 'Synthetic profile bootstrap incomplete';
  END IF;
END $$;
-- Existing clients can continue using their old completion contract. This does
-- not fabricate an age/consent receipt for that completion.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
SET LOCAL request.jwt.claim.role='authenticated';
DO $$ DECLARE n integer; BEGIN
  UPDATE public.profiles SET onboarding_completed_at='2020-01-01' WHERE id=auth.uid();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Legacy completion did not update exactly one row'; END IF;
END $$;
DO $$ BEGIN
  IF EXISTS(SELECT FROM public.support_onboarding_consent) THEN RAISE EXCEPTION 'Legacy completion fabricated consent'; END IF;
END $$;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$ DECLARE
  boundary integer := extract(year from (now() at time zone 'UTC'))::integer - 13;
  receipt jsonb;
  replay jsonb;
BEGIN
  BEGIN
    PERFORM public.complete_support_onboarding('22222222-2222-4222-8222-222222222222',boundary,true,true,'2026-11-06');
    RAISE EXCEPTION 'Wrong expected owner accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.complete_support_onboarding(auth.uid(),boundary+1,true,true,'2026-11-06');
    RAISE EXCEPTION 'Under13 accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.complete_support_onboarding(auth.uid(),boundary,false,true,'2026-11-06');
    RAISE EXCEPTION 'Missing birthday confirmation accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.complete_support_onboarding(auth.uid(),boundary,true,false,'2026-11-06');
    RAISE EXCEPTION 'Unaccepted terms accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.complete_support_onboarding(auth.uid(),boundary,true,true,'wrong');
    RAISE EXCEPTION 'Wrong terms version accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  FOREACH boundary IN ARRAY ARRAY[NULL::integer,1899,2101] LOOP
    BEGIN
      PERFORM public.complete_support_onboarding(auth.uid(),boundary,true,true,'2026-11-06');
      RAISE EXCEPTION 'Invalid birth year accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
  boundary := extract(year from (now() at time zone 'UTC'))::integer - 13;
  receipt := public.complete_support_onboarding(auth.uid(),boundary,true,true,'2026-11-06');
  FOR i IN 1..100 LOOP
    replay := public.complete_support_onboarding(auth.uid(),boundary,true,true,'2026-11-06');
    IF replay IS DISTINCT FROM receipt THEN RAISE EXCEPTION 'Repeated consent changed receipt'; END IF;
  END LOOP;
  IF receipt->>'user_id' <> auth.uid()::text OR receipt->>'consent_version' <> '2026-11-06' OR
    (SELECT onboarding_completed_at FROM public.profiles WHERE id=auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Consent not atomically acknowledged';
  END IF;
  BEGIN
    PERFORM public.complete_support_onboarding(auth.uid(),boundary-1,true,true,'2026-11-06');
    RAISE EXCEPTION 'Consent was rewritten';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    UPDATE public.support_onboarding_consent SET birth_year=1900 WHERE user_id=auth.uid();
    RAISE EXCEPTION 'Direct consent rewrite accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF (SELECT count(*) FROM public.support_onboarding_consent WHERE user_id=auth.uid()) <> 1 THEN
    RAISE EXCEPTION 'Owner cannot inspect own consent';
  END IF;
  BEGIN
    DELETE FROM public.support_onboarding_consent WHERE user_id=auth.uid();
    RAISE EXCEPTION 'Direct consent delete accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    TRUNCATE public.support_onboarding_consent;
    RAISE EXCEPTION 'Direct consent truncate accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.support_onboarding_consent VALUES(auth.uid(),1900,true,'fake',now());
    RAISE EXCEPTION 'Direct consent insert accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$ BEGIN
  IF EXISTS(SELECT FROM public.support_onboarding_consent) THEN RAISE EXCEPTION 'Cross-owner consent read'; END IF;
  IF (SELECT onboarding_completed_at FROM public.profiles WHERE id=auth.uid()) IS DISTINCT FROM '2020-01-01'::timestamptz THEN
    RAISE EXCEPTION 'Legacy completion changed';
  END IF;
END $$;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$ BEGIN
  BEGIN
    PERFORM public.complete_support_onboarding(auth.uid(),2000,true,true,'2026-11-06');
    RAISE EXCEPTION 'Missing profile accepted';
  EXCEPTION WHEN no_data_found THEN NULL; END;
END $$;
SET LOCAL request.jwt.claim.sub='';
DO $$ BEGIN
  BEGIN
    PERFORM public.complete_support_onboarding(NULL,2000,true,true,'2026-11-06');
    RAISE EXCEPTION 'Unauthenticated consent accepted';
  EXCEPTION WHEN invalid_authorization_specification THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF has_function_privilege('public.complete_support_onboarding(uuid,integer,boolean,boolean,text)','execute') OR
     has_table_privilege('public.support_onboarding_consent','select') THEN
    RAISE EXCEPTION 'Anonymous consent exposed';
  END IF;
END $$;
RESET ROLE;
ROLLBACK;
