\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() NOT IN ('ca3_synthetic','restoration_synthetic') OR EXISTS(SELECT FROM auth.users) THEN
  RAISE EXCEPTION 'Empty dedicated synthetic database required';
 END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','device-a@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','device-b@example.invalid','{}',now(),now());
INSERT INTO public.push_tokens(user_id,device_token,platform) VALUES
 ('11111111-1111-4111-8111-111111111111',repeat('ab',32),'ios'),
 ('11111111-1111-4111-8111-111111111111',repeat('cd',32),'ios'),
 ('22222222-2222-4222-8222-222222222222',repeat('ef',32),'ios');
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF has_function_privilege('public.register_current_device(text,text)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous registration grant'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
DO $$ DECLARE owner uuid; bad text; BEGIN
 owner := public.register_current_device(repeat('AB',32));
 IF owner <> auth.uid() THEN RAISE EXCEPTION 'Caller does not own registered token'; END IF;
 PERFORM public.register_current_device(repeat('ab',32));
 FOREACH bad IN ARRAY ARRAY['', 'a', 'aZ', ' ab ', repeat('ab',513)] LOOP
  BEGIN
   PERFORM public.register_current_device(bad);
   RAISE EXCEPTION 'Invalid token accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.register_current_device(repeat('ab',32),'web');
  RAISE EXCEPTION 'Invalid platform accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.push_tokens) <> 3
    OR (SELECT count(*) FROM public.push_tokens WHERE device_token=repeat('ab',32) AND user_id='22222222-2222-4222-8222-222222222222') <> 1
    OR NOT EXISTS(SELECT FROM public.push_tokens WHERE device_token=repeat('cd',32) AND user_id='11111111-1111-4111-8111-111111111111')
    OR NOT EXISTS(SELECT FROM public.push_tokens WHERE device_token=repeat('ef',32) AND user_id='22222222-2222-4222-8222-222222222222') THEN
  RAISE EXCEPTION 'Exact-token transfer changed unrelated devices or duplicated registration';
 END IF;
END $$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
-- A delayed outgoing-account unregister must not remove the new owner's token.
DELETE FROM public.push_tokens WHERE user_id=auth.uid() AND device_token=repeat('ab',32);
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM public.push_tokens WHERE device_token=repeat('ab',32) AND user_id='22222222-2222-4222-8222-222222222222') THEN
  RAISE EXCEPTION 'Old-account unregister removed new registration';
 END IF;
END $$;
SELECT 'PASS: exact normalized token transferred, repeat idempotent, unrelated devices retained, malformed input rejected, old-owner unregister harmless';
ROLLBACK;
