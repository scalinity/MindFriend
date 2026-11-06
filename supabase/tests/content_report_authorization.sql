\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'restoration_synthetic' OR EXISTS(SELECT FROM auth.users) THEN
  RAISE EXCEPTION 'Empty restoration_synthetic database required';
 END IF;
END $$;
INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic') ON CONFLICT DO NOTHING;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','flag-a@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','flag-b@example.invalid','{}',now(),now());
INSERT INTO public.generated_content(id,user_id,content_type,title,text_content,status) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','meditation','Synthetic','Synthetic private fixture','completed');
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF has_table_privilege('public.gen_content_flags','INSERT') THEN RAISE EXCEPTION 'Anonymous insert grant retained'; END IF;
 BEGIN
  INSERT INTO public.gen_content_flags(generated_content_id,reason,status)
  VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','safety_concern','pending');
  RAISE EXCEPTION 'Anonymous insert accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$ BEGIN
 IF has_table_privilege('public.gen_content_flags','INSERT') THEN RAISE EXCEPTION 'Client insert grant retained'; END IF;
 BEGIN
  INSERT INTO public.gen_content_flags(generated_content_id,user_id,reason,status)
  VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',auth.uid(),'safety_concern','pending');
  RAISE EXCEPTION 'Cross-owner direct insert accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$ BEGIN
 BEGIN
  INSERT INTO public.gen_content_flags(generated_content_id,user_id,reason,status)
  VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',auth.uid(),'safety_concern','pending');
  RAISE EXCEPTION 'Owner direct insert bypassed handler';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
INSERT INTO public.gen_content_flags(generated_content_id,user_id,reason,status)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','safety_concern','pending');
DO $$ BEGIN
 IF (SELECT count(*) FROM public.gen_content_flags) <> 1 THEN RAISE EXCEPTION 'Service insert failed or unauthorized insert persisted'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: anonymous, cross-owner and owner direct inserts denied; service report persisted';
ROLLBACK;
