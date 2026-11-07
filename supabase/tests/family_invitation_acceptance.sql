BEGIN;
SET LOCAL statement_timeout = '15s';
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
INSERT INTO auth.users(id,email,email_confirmed_at,raw_user_meta_data) SELECT ('18200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid, 'recipient'||n||'@example.invalid', CASE WHEN n=4 THEN NULL ELSE now() END,'{}' FROM generate_series(1,7) n;
INSERT INTO public.profiles(id) SELECT id FROM auth.users WHERE id::text LIKE '18200000-%' ON CONFLICT DO NOTHING;
INSERT INTO public.family_groups(id,admin_user_id,name,invite_code,max_members) VALUES ('18200000-0000-4000-8000-000000000010','18200000-0000-4000-8000-000000000001','Synthetic family','GROUPABC',6);
INSERT INTO public.family_members(family_id,user_id,role,status) VALUES('18200000-0000-4000-8000-000000000010','18200000-0000-4000-8000-000000000001','admin','active');
INSERT INTO public.subscriptions(user_id,product_id,original_transaction_id,status,expires_at,plan_type,family_id,is_family_admin,seats_used,seats_total) VALUES
 ('18200000-0000-4000-8000-000000000001','synthetic_family','accept_admin','active',now()+interval '1 day','family','18200000-0000-4000-8000-000000000010',true,1,2),
 ('18200000-0000-4000-8000-000000000006','synthetic_personal','keep_personal','active',now()+interval '1 day','individual',NULL,false,1,1),
 ('18200000-0000-4000-8000-000000000007','synthetic_personal','keep_expired_receipt','expired',now()-interval '1 day','individual',NULL,false,1,1);
INSERT INTO public.family_invitations(family_id,email,invite_code,intended_role,intended_birth_date) VALUES
 ('18200000-0000-4000-8000-000000000010','Recipient2@EXAMPLE.invalid','CHILDABC','child','2015-03-04'),
 ('18200000-0000-4000-8000-000000000010','recipient4@example.invalid','UNCONFAB','parent',NULL),
 ('18200000-0000-4000-8000-000000000010','recipient5@example.invalid','SECONDAB','teen',NULL),
 ('18200000-0000-4000-8000-000000000010','recipient6@example.invalid','PAIDABCD','parent',NULL);
SET LOCAL ROLE service_role;
DO $$ DECLARE v_result jsonb; BEGIN
 BEGIN
  PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000003','CHILDABC',NULL,'1990-01-01',true);
  RAISE EXCEPTION 'Wrong recipient accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000004','UNCONFAB',NULL,NULL,true);
  RAISE EXCEPTION 'Unconfirmed recipient accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='accept_admin') <> 1 THEN RAISE EXCEPTION 'Unauthorized claim changed seats'; END IF;
 IF EXISTS(SELECT 1 FROM public.family_invitations WHERE accepted_at IS NOT NULL AND family_id='18200000-0000-4000-8000-000000000010') THEN RAISE EXCEPTION 'Unauthorized claim consumed invitation'; END IF;
 v_result := public.join_family_atomic('18200000-0000-4000-8000-000000000002','CHILDABC','Recipient','1990-01-01',true);
 IF v_result->>'role' <> 'child' OR (SELECT birth_date FROM public.family_members WHERE user_id='18200000-0000-4000-8000-000000000002') IS DISTINCT FROM '2015-03-04'::date THEN RAISE EXCEPTION 'Child role or intended birth date overridden'; END IF;
 IF (SELECT status FROM public.family_invitations WHERE invite_code='CHILDABC') <> 'accepted' THEN RAISE EXCEPTION 'Invitation not consumed'; END IF;
 IF NOT public.has_current_premium_access('18200000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Paid access missing'; END IF;
 BEGIN
  PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000002','CHILDABC',NULL,NULL,true);
  RAISE EXCEPTION 'Replay accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000005','SECONDAB',NULL,NULL,true);
  RAISE EXCEPTION 'Full family accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF (SELECT status FROM public.family_invitations WHERE invite_code='SECONDAB') <> 'pending' OR (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='accept_admin') <> 2 THEN RAISE EXCEPTION 'Full-seat failure partially applied'; END IF;
END $$;
RESET ROLE;
UPDATE public.subscriptions SET seats_total=5 WHERE original_transaction_id='accept_admin';
-- Fail after seat and membership writes; the exception must roll the whole join back.
CREATE FUNCTION pg_temp.reject_synthetic_family_subscription() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.user_id='18200000-0000-4000-8000-000000000005'::uuid THEN RAISE EXCEPTION 'Synthetic subscription failure' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER synthetic_family_failure BEFORE INSERT ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_synthetic_family_subscription();
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN
  PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000005','SECONDAB',NULL,NULL,true);
  RAISE EXCEPTION 'Injected subscription failure ignored';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='accept_admin') <> 2 OR EXISTS(SELECT 1 FROM public.family_members WHERE user_id='18200000-0000-4000-8000-000000000005') OR (SELECT status FROM public.family_invitations WHERE invite_code='SECONDAB') <> 'pending' THEN RAISE EXCEPTION 'Failed transaction leaked partial writes'; END IF;
 BEGIN
  PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000006','PAIDABCD',NULL,NULL,true);
  RAISE EXCEPTION 'Existing paid subscription replaced';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF (SELECT original_transaction_id FROM public.subscriptions WHERE user_id='18200000-0000-4000-8000-000000000006') <> 'keep_personal' THEN RAISE EXCEPTION 'Personal purchase changed'; END IF;
END $$;
RESET ROLE;
DROP TRIGGER synthetic_family_failure ON public.subscriptions;
SET LOCAL ROLE service_role;
DO $$ DECLARE v_result jsonb; BEGIN
 PERFORM public.join_family_atomic('18200000-0000-4000-8000-000000000005','SECONDAB',NULL,NULL,true);
 IF (SELECT count(DISTINCT original_transaction_id) FROM public.subscriptions WHERE user_id IN ('18200000-0000-4000-8000-000000000002','18200000-0000-4000-8000-000000000005')) <> 2 THEN RAISE EXCEPTION 'Member transaction IDs collide'; END IF;
 v_result := public.join_family_atomic('18200000-0000-4000-8000-000000000007','GROUPABC',NULL,'1980-01-01',false);
 IF (SELECT original_transaction_id FROM public.subscriptions WHERE user_id='18200000-0000-4000-8000-000000000007') <> 'keep_expired_receipt' THEN RAISE EXCEPTION 'Expired receipt ownership erased'; END IF;
 IF NOT public.has_current_premium_access('18200000-0000-4000-8000-000000000007') THEN RAISE EXCEPTION 'Preserved receipt blocked family entitlement'; END IF;
 IF v_result->>'role' <> 'child' THEN RAISE EXCEPTION 'Self-reported adult became parent'; END IF;
 IF (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='accept_admin') <> 4 THEN RAISE EXCEPTION 'Group-code paid join bypassed seat accounting'; END IF;
 IF has_function_privilege('authenticated','public.join_family_atomic(uuid,text,text,date,boolean)','EXECUTE') OR has_function_privilege('anon','public.join_family_atomic(uuid,text,text,date,boolean)','EXECUTE') THEN RAISE EXCEPTION 'RPC exposed to clients'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: confirmed recipient, authoritative child role/date, replay, capacity, full rollback, personal purchase preservation, unique receipts and group-code seats';
ROLLBACK;
