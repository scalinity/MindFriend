BEGIN;
SET LOCAL statement_timeout = '15s';
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
INSERT INTO auth.users(id,email,raw_user_meta_data) SELECT ('18100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid, 'family'||n||'@example.invalid','{}' FROM generate_series(1,5) n;
INSERT INTO public.profiles(id) SELECT id FROM auth.users WHERE id::text LIKE '18100000-%' ON CONFLICT DO NOTHING;
INSERT INTO public.family_groups(id,admin_user_id,name) VALUES ('18100000-0000-4000-8000-000000000010','18100000-0000-4000-8000-000000000001','Synthetic family');
INSERT INTO public.family_members(id,family_id,user_id,role,status) SELECT ('18100000-0000-4000-8000-'||lpad((20+n)::text,12,'0'))::uuid,'18100000-0000-4000-8000-000000000010',('18100000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,CASE WHEN n=1 THEN 'admin' ELSE 'child' END,'active' FROM generate_series(1,4) n;
INSERT INTO public.subscriptions(user_id,product_id,original_transaction_id,status,expires_at,plan_type,family_id,is_family_admin,seats_used,seats_total) VALUES
 ('18100000-0000-4000-8000-000000000001','synthetic_family','remove_admin','active',now()+interval '1 day','family','18100000-0000-4000-8000-000000000010',true,4,4),
 ('18100000-0000-4000-8000-000000000002','synthetic_family','family-18100000-0000-4000-8000-000000000010-18100000-0000-4000-8000-000000000002','active',now()+interval '1 day','family','18100000-0000-4000-8000-000000000010',false,0,0),
 ('18100000-0000-4000-8000-000000000003','synthetic_personal','preserve_personal','active',now()+interval '1 day','individual','18100000-0000-4000-8000-000000000010',false,1,1),
 ('18100000-0000-4000-8000-000000000004','synthetic_family','family-remove_admin','active',now()+interval '1 day','family','18100000-0000-4000-8000-000000000010',false,0,0);
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN
  PERFORM public.remove_family_member_atomic('18100000-0000-4000-8000-000000000005','18100000-0000-4000-8000-000000000022');
  RAISE EXCEPTION 'Foreign actor removed member';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.remove_family_member_atomic('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000021');
  RAISE EXCEPTION 'Owner removed itself';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.remove_family_member_atomic('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000022');
 PERFORM public.remove_family_member_atomic('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000022');
 IF (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='remove_admin') <> 3 THEN RAISE EXCEPTION 'Seat release not idempotent'; END IF;
 IF (SELECT status FROM public.subscriptions WHERE original_transaction_id='family-18100000-0000-4000-8000-000000000010-18100000-0000-4000-8000-000000000002') <> 'expired' THEN RAISE EXCEPTION 'Removed subscription active'; END IF;
 IF public.has_current_premium_access('18100000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Removed member retains family access'; END IF;
 PERFORM public.remove_family_member_atomic('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000023');
 IF NOT public.has_current_premium_access('18100000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Unrelated paid access lost'; END IF;
 IF (SELECT status FROM public.subscriptions WHERE original_transaction_id='preserve_personal') <> 'active' THEN RAISE EXCEPTION 'Personal purchase rewritten'; END IF;
 IF (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='remove_admin') <> 2 THEN RAISE EXCEPTION 'Second seat not released'; END IF;
 PERFORM public.remove_family_member_atomic('18100000-0000-4000-8000-000000000001','18100000-0000-4000-8000-000000000024');
 IF (SELECT status FROM public.subscriptions WHERE original_transaction_id='family-remove_admin') <> 'expired' THEN RAISE EXCEPTION 'Legacy shared receipt not expired'; END IF;
 IF (SELECT seats_used FROM public.subscriptions WHERE original_transaction_id='remove_admin') <> 1 THEN RAISE EXCEPTION 'Legacy seat not released'; END IF;
 IF has_function_privilege('authenticated','public.remove_family_member_atomic(uuid,uuid)','EXECUTE') OR has_function_privilege('anon','public.remove_family_member_atomic(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Privileged RPC exposed'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: owner authorization, self-removal denial, atomic/idempotent seat release, expiry and unrelated paid access';
ROLLBACK;
