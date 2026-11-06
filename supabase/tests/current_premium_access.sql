-- Synthetic rollback fixture; run after refresh_current_premium_access.
BEGIN;
SET LOCAL statement_timeout = '20s';
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT set_config('request.jwt.claim.role', 'service_role', true);
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17100000-0000-4000-8000-000000000001', 'expired@example.invalid', '{}'),
 ('17100000-0000-4000-8000-000000000002', 'family-admin@example.invalid', '{}'),
 ('17100000-0000-4000-8000-000000000003', 'family-member@example.invalid', '{}');
INSERT INTO public.profiles(id) SELECT id FROM auth.users WHERE id::text LIKE '17100000-%' ON CONFLICT(id) DO NOTHING;
UPDATE public.profiles SET subscription_tier = 'premium', daily_ai_quota = -1
  WHERE id::text LIKE '17100000-%';
INSERT INTO public.subscriptions(user_id, product_id, original_transaction_id, status, expires_at)
 VALUES ('17100000-0000-4000-8000-000000000001','synthetic_personal','synthetic_expired','active',now()-interval '1 second');
SET LOCAL ROLE service_role;
DO $$ DECLARE quota record; BEGIN
 IF public.refresh_user_entitlement('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Expired purchase granted premium'; END IF;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE id='17100000-0000-4000-8000-000000000001' AND (subscription_tier <> 'free' OR daily_ai_quota <> 5)) THEN RAISE EXCEPTION 'Expired profile cache retained'; END IF;
 IF public.get_voice_minutes_remaining('17100000-0000-4000-8000-000000000001') <> 3 THEN RAISE EXCEPTION 'Expired voice unlimited'; END IF;
 SELECT * INTO quota FROM public.check_and_increment_rehearsal_quota('17100000-0000-4000-8000-000000000001');
 IF quota.quota_limit <> 2 OR quota.used <> 1 THEN RAISE EXCEPTION 'Expired rehearsal unlimited'; END IF;
 IF NOT public.reserve_ai_image_quota('17100000-0000-4000-8000-000000000001') OR
    NOT public.reserve_ai_image_quota('17100000-0000-4000-8000-000000000001') OR
    public.reserve_ai_image_quota('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Expired image quota not enforced'; END IF;
 SELECT * INTO quota FROM public.reserve_voice_journal_quota('17100000-0000-4000-8000-000000000001',6);
 IF quota.allowed OR quota.is_premium OR quota.voice_minutes_limit <> 5 THEN RAISE EXCEPTION 'Expired voice journal quota not enforced'; END IF;
END $$;
RESET ROLE;
UPDATE public.subscriptions SET expires_at = now()+interval '1 day' WHERE user_id='17100000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF NOT public.refresh_user_entitlement('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Valid purchase denied'; END IF;
 UPDATE public.subscriptions SET status='cancelled' WHERE user_id='17100000-0000-4000-8000-000000000001';
 IF public.refresh_user_entitlement('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Revoked access retained'; END IF;
 UPDATE public.subscriptions SET status='grace_period',expires_at=NULL,access_source='organization_sponsored' WHERE user_id='17100000-0000-4000-8000-000000000001';
 IF NOT public.refresh_user_entitlement('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Lifetime/grace or stale marker denied'; END IF;
END $$;
DO $$ DECLARE quota record; BEGIN
 IF NOT public.reserve_ai_image_quota('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Grace image access denied'; END IF;
 SELECT * INTO quota FROM public.reserve_voice_journal_quota('17100000-0000-4000-8000-000000000001',6);
 IF NOT quota.allowed OR NOT quota.is_premium OR quota.voice_minutes_limit <> 60 THEN RAISE EXCEPTION 'Grace voice journal access denied'; END IF;
END $$;
-- Current paid family admission does not depend on the member's cached row.
INSERT INTO public.family_groups(id,admin_user_id,name,invite_code)
 VALUES('17100000-0000-4000-8000-000000000010','17100000-0000-4000-8000-000000000002','Synthetic family','SYNTHETIC171');
INSERT INTO public.family_members(family_id,user_id,status)
 VALUES('17100000-0000-4000-8000-000000000010','17100000-0000-4000-8000-000000000003','active');
INSERT INTO public.subscriptions(user_id,product_id,original_transaction_id,status,expires_at,plan_type,family_id,is_family_admin)
 VALUES('17100000-0000-4000-8000-000000000002','synthetic_family','synthetic_family_purchase','active',now()+interval '1 day','family','17100000-0000-4000-8000-000000000010',true);
DO $$ BEGIN
 IF NOT public.refresh_user_entitlement('17100000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Paid family denied'; END IF;
 UPDATE public.subscriptions SET expires_at=now()-interval '1 second' WHERE user_id='17100000-0000-4000-8000-000000000002';
 IF public.refresh_user_entitlement('17100000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Expired family granted'; END IF;
 UPDATE public.subscriptions SET expires_at=now()+interval '1 day' WHERE user_id='17100000-0000-4000-8000-000000000002';
 UPDATE public.family_members SET status='removed' WHERE user_id='17100000-0000-4000-8000-000000000003';
 IF public.refresh_user_entitlement('17100000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Removed member granted'; END IF;
END $$;
-- An individual purchase can retain an old family marker after an upsert.
UPDATE public.subscriptions SET family_id='17100000-0000-4000-8000-000000000010', is_family_admin=false
 WHERE user_id='17100000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF NOT public.refresh_user_entitlement('17100000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Stale family marker denied individual purchase'; END IF;
END $$;
INSERT INTO public.organizations(id,name,billing_email,seat_count,seats_used)
 VALUES('17100000-0000-4000-8000-000000000020','Synthetic sponsor','synthetic@example.invalid',10,1);
INSERT INTO public.organization_members(organization_id,user_id,is_active)
 VALUES('17100000-0000-4000-8000-000000000020','17100000-0000-4000-8000-000000000003',true);
DO $$ BEGIN
 IF NOT public.refresh_user_entitlement('17100000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Current sponsor denied'; END IF;
 UPDATE public.organizations SET subscription_status='inactive' WHERE id='17100000-0000-4000-8000-000000000020';
 IF public.refresh_user_entitlement('17100000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Inactive sponsor granted'; END IF;
 IF has_function_privilege('anon','public.has_current_premium_access(uuid)','EXECUTE') OR has_function_privilege('authenticated','public.refresh_user_entitlement(uuid)','EXECUTE') OR has_function_privilege('authenticated','public.check_and_increment_rehearsal_quota(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Entitlement ACL permits privileged client write'; END IF;
END $$;
-- Verified revocation is bound to this owner and exact current transaction.
UPDATE public.subscriptions SET status='active', expires_at=now()+interval '1 day',
  original_transaction_id='synthetic_expired', last_transaction_id='synthetic_current'
  WHERE user_id='17100000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF public.revoke_verified_apple_transaction('17100000-0000-4000-8000-000000000002','synthetic_expired','synthetic_current') THEN RAISE EXCEPTION 'Cross-owner refund changed purchase'; END IF;
 IF public.revoke_verified_apple_transaction('17100000-0000-4000-8000-000000000001','synthetic_expired','synthetic_old') THEN RAISE EXCEPTION 'Old refund cancelled renewal'; END IF;
 IF NOT public.revoke_verified_apple_transaction('17100000-0000-4000-8000-000000000001','synthetic_expired','synthetic_current') THEN RAISE EXCEPTION 'Matching refund ignored'; END IF;
 IF public.has_current_premium_access('17100000-0000-4000-8000-000000000001') OR
    EXISTS(SELECT 1 FROM public.profiles WHERE id='17100000-0000-4000-8000-000000000001' AND subscription_tier <> 'free') THEN RAISE EXCEPTION 'Refund left premium access'; END IF;
 IF public.revoke_verified_apple_transaction('17100000-0000-4000-8000-000000000001','synthetic_expired','synthetic_current') THEN RAISE EXCEPTION 'Refund replay changed purchase'; END IF;
 IF has_function_privilege('authenticated','public.revoke_verified_apple_transaction(uuid,text,text)','EXECUTE') THEN RAISE EXCEPTION 'Client refund mutation allowed'; END IF;
END $$;
-- Exercise the actual family-admin refund trigger, not just the read predicate.
INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
 ('17100000-0000-4000-8000-000000000004','shared-new@example.invalid','{}'),
 ('17100000-0000-4000-8000-000000000005','shared-legacy@example.invalid','{}');
INSERT INTO public.profiles(id) VALUES('17100000-0000-4000-8000-000000000004'),('17100000-0000-4000-8000-000000000005') ON CONFLICT(id) DO NOTHING;
UPDATE public.family_members SET status='active' WHERE user_id='17100000-0000-4000-8000-000000000003';
INSERT INTO public.family_members(family_id,user_id,status) VALUES
 ('17100000-0000-4000-8000-000000000010','17100000-0000-4000-8000-000000000001','active'),
 ('17100000-0000-4000-8000-000000000010','17100000-0000-4000-8000-000000000004','active'),
 ('17100000-0000-4000-8000-000000000010','17100000-0000-4000-8000-000000000005','active');
UPDATE public.organizations SET subscription_status='active' WHERE id='17100000-0000-4000-8000-000000000020';
UPDATE public.subscriptions SET status='active',expires_at=now()+interval '2 days',last_transaction_id='independent-current'
 WHERE user_id='17100000-0000-4000-8000-000000000001';
INSERT INTO public.subscriptions(user_id,product_id,original_transaction_id,status,expires_at,plan_type,family_id,is_family_admin,access_source,organization_id) VALUES
 ('17100000-0000-4000-8000-000000000003','org_sponsored_premium','synthetic_org_receipt','active',NULL,'organization','17100000-0000-4000-8000-000000000010',false,'organization_sponsored','17100000-0000-4000-8000-000000000020'),
 ('17100000-0000-4000-8000-000000000004','synthetic_family','family-17100000-0000-4000-8000-000000000010-17100000-0000-4000-8000-000000000004','active',now()+interval '1 day','family','17100000-0000-4000-8000-000000000010',false,'personal',NULL),
 ('17100000-0000-4000-8000-000000000005','synthetic_family','family-synthetic_family_purchase','active',now()+interval '1 day','family','17100000-0000-4000-8000-000000000010',false,'personal',NULL);
CREATE TEMP TABLE independent_purchase_snapshot AS SELECT user_id,to_jsonb(s) AS value FROM public.subscriptions s
 WHERE user_id IN ('17100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000003');
DO $$ DECLARE source_status text; BEGIN
 FOREACH source_status IN ARRAY ARRAY['active','grace_period'] LOOP
  UPDATE public.subscriptions SET status=source_status,expires_at=now()+interval '1 day',last_transaction_id='family-admin-current'
    WHERE user_id='17100000-0000-4000-8000-000000000002';
  UPDATE public.subscriptions SET status='active',expires_at=now()+interval '1 day'
    WHERE user_id IN ('17100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000005');
  UPDATE public.profiles SET subscription_tier='premium',daily_ai_quota=-1 WHERE id::text LIKE '17100000-%';
  IF NOT public.revoke_verified_apple_transaction('17100000-0000-4000-8000-000000000002','synthetic_family_purchase','family-admin-current') THEN RAISE EXCEPTION 'Family admin refund ignored'; END IF;
  IF EXISTS(SELECT 1 FROM public.subscriptions s JOIN independent_purchase_snapshot old USING(user_id) WHERE to_jsonb(s) IS DISTINCT FROM old.value) THEN RAISE EXCEPTION 'Family refund destroyed independent personal or sponsored receipt'; END IF;
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id IN ('17100000-0000-4000-8000-000000000001','17100000-0000-4000-8000-000000000003') AND (subscription_tier <> 'premium' OR daily_ai_quota <> -1)) THEN RAISE EXCEPTION 'Family refund removed independent premium profile'; END IF;
  IF EXISTS(SELECT 1 FROM public.subscriptions WHERE user_id IN ('17100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000005') AND (status <> 'expired' OR expires_at > now())) THEN RAISE EXCEPTION 'Family-derived access survived refund from %',source_status; END IF;
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id IN ('17100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000005') AND (subscription_tier <> 'free' OR daily_ai_quota <> 5)) THEN RAISE EXCEPTION 'Shared profile survived refund from %',source_status; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.billing_events WHERE user_id IN ('17100000-0000-4000-8000-000000000004','17100000-0000-4000-8000-000000000005') AND event_type='subscription_expired') <> 4 THEN RAISE EXCEPTION 'Family refund emitted duplicate or missing expiry events'; END IF;
 IF has_function_privilege('anon','public.compute_current_premium_access(uuid)','EXECUTE') OR
    has_function_privilege('authenticated','public.compute_current_premium_access(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Internal entitlement calculation exposed'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.subscriptions'::regclass AND tgfoid='public.revoke_family_premium_on_expiry()'::regprocedure) <> 1 THEN RAISE EXCEPTION 'Duplicate family expiry trigger remains'; END IF;
END $$;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"17100000-0000-4000-8000-000000000001"}',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','17100000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT public.has_current_premium_access('17100000-0000-4000-8000-000000000001');
DO $$ BEGIN
 BEGIN
  PERFORM public.has_current_premium_access('17100000-0000-4000-8000-000000000002');
  RAISE EXCEPTION 'Cross-account entitlement lookup accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT 'PASS: expired/revoked personal, lifetime/grace, family, sponsor, cache, quota and authorization cases';
ROLLBACK;
