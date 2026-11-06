-- Run with ON_ERROR_STOP against an empty disposable database with the actual
-- schema and recipient/quota/relay/refresh migrations. No provider calls.
BEGIN;
SET LOCAL statement_timeout = '20s';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM auth.users) OR EXISTS (SELECT 1 FROM public.organizations)
     OR EXISTS (SELECT 1 FROM public.profiles) OR EXISTS (SELECT 1 FROM public.subscriptions)
     OR EXISTS (SELECT 1 FROM public.organization_members) OR EXISTS (SELECT 1 FROM public.organization_invites)
     OR EXISTS (SELECT 1 FROM public.creative_quota_usage) THEN
    RAISE EXCEPTION 'Synthetic entitlement fixture requires empty entitlement tables';
  END IF;
END $$;

SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
  ('10000000-0000-4000-8000-000000000001', 'sponsor-personal@example.invalid', '{}'),
  ('20000000-0000-4000-8000-000000000002', 'sponsor-other@example.invalid', '{"subscription_tier":"premium"}');
INSERT INTO public.profiles(id) VALUES
  ('10000000-0000-4000-8000-000000000001'), ('20000000-0000-4000-8000-000000000002')
  ON CONFLICT (id) DO NOTHING;
UPDATE public.profiles SET subscription_tier = 'free';
INSERT INTO public.organizations(id, name, billing_email, seat_count, seats_used)
  VALUES ('90000000-0000-4000-8000-000000000009', 'Synthetic sponsor', 'sponsor@example.invalid', 10, 0);
INSERT INTO public.organization_admins(id, organization_id, user_id, role)
  VALUES ('80000000-0000-4000-8000-000000000008', '90000000-0000-4000-8000-000000000009',
          '20000000-0000-4000-8000-000000000002', 'admin');
INSERT INTO public.organization_invites(organization_id, invite_code, created_by_admin_id, max_uses)
  VALUES ('90000000-0000-4000-8000-000000000009', 'SYNTHETICSPONSOR', '80000000-0000-4000-8000-000000000008', 10);
INSERT INTO public.subscriptions(user_id, product_id, original_transaction_id, status, expires_at)
  VALUES ('10000000-0000-4000-8000-000000000001', 'synthetic_personal', 'synthetic_personal_transaction', 'active', now() + interval '1 day');
CREATE TEMP TABLE entitlement_snapshot(name text PRIMARY KEY, value jsonb);
INSERT INTO entitlement_snapshot SELECT 'personal', to_jsonb(s) FROM public.subscriptions s;

SET LOCAL ROLE service_role;
DO $$ DECLARE result jsonb; BEGIN
  result := public.join_organization_with_invite('10000000-0000-4000-8000-000000000001', 'SYNTHETICSPONSOR');
  IF result->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Synthetic join failed: %', result; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF (SELECT to_jsonb(s) FROM public.subscriptions s) IS DISTINCT FROM
     (SELECT value FROM entitlement_snapshot WHERE name = 'personal') THEN
    RAISE EXCEPTION 'Join replaced valid personal purchase';
  END IF;
  IF (SELECT seats_used FROM public.organizations) <> 1 OR (SELECT uses_count FROM public.organization_invites) <> 1
     OR (SELECT count(*) FROM public.organization_members) <> 1 THEN
    RAISE EXCEPTION 'Join did not claim exactly one seat/use/member';
  END IF;
END $$;
INSERT INTO entitlement_snapshot SELECT 'organization', to_jsonb(o) FROM public.organizations o;
INSERT INTO entitlement_snapshot SELECT 'invite', to_jsonb(i) FROM public.organization_invites i;
INSERT INTO entitlement_snapshot SELECT 'membership', to_jsonb(m) FROM public.organization_members m;

-- Exercise owner authorization under the actual authenticated database role.
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-4000-8000-000000000001"}', true);
SET LOCAL ROLE authenticated;
SELECT public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
DO $$ BEGIN
  BEGIN
    PERFORM public.refresh_sponsored_entitlement('20000000-0000-4000-8000-000000000002');
    RAISE EXCEPTION 'Cross-user refresh accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.refresh_sponsored_entitlement(NULL);
    RAISE EXCEPTION 'NULL owner accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF (SELECT to_jsonb(s) FROM public.subscriptions s) IS DISTINCT FROM
     (SELECT value FROM entitlement_snapshot WHERE name = 'personal') THEN RAISE EXCEPTION 'Refresh replaced valid personal purchase'; END IF;
END $$;

-- StoreKit replaces product/plan without always clearing older sponsorship fields.
UPDATE public.subscriptions SET access_source = 'organization_sponsored',
  organization_id = '90000000-0000-4000-8000-000000000009';
SELECT public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE product_id = 'synthetic_personal'
      AND plan_type = 'individual' AND status = 'active' AND expires_at > now()) THEN
    RAISE EXCEPTION 'Stale sponsorship marker overwrote a purchased plan';
  END IF;
END $$;
UPDATE public.subscriptions SET access_source = 'personal', organization_id = NULL;

-- A NULL expiry is a lifetime purchase, including the join-preserved grace period.
UPDATE public.subscriptions SET expires_at = NULL, status = 'grace_period';
SELECT public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE access_source = 'personal' AND status = 'grace_period' AND expires_at IS NULL) THEN
    RAISE EXCEPTION 'Lifetime/grace purchase replaced';
  END IF;
END $$;

-- Expiry alone enables sponsorship; no second join is needed or permitted.
UPDATE public.subscriptions SET status = 'active', expires_at = now() - interval '1 second';
SET LOCAL ROLE authenticated;
SELECT public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
RESET ROLE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE access_source = 'organization_sponsored'
      AND status = 'active' AND expires_at IS NULL AND organization_id = '90000000-0000-4000-8000-000000000009') THEN
    RAISE EXCEPTION 'Expired purchase did not become sponsored';
  END IF;
END $$;
INSERT INTO entitlement_snapshot SELECT 'sponsored', to_jsonb(s) FROM public.subscriptions s;
SELECT public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
DO $$ BEGIN
  IF (SELECT to_jsonb(s) FROM public.subscriptions s) IS DISTINCT FROM
     (SELECT value FROM entitlement_snapshot WHERE name = 'sponsored') THEN RAISE EXCEPTION 'Refresh is not idempotent'; END IF;
END $$;

SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
DO $$ DECLARE result jsonb; BEGIN
  result := public.join_organization_with_invite('10000000-0000-4000-8000-000000000001', 'SYNTHETICSPONSOR');
  IF result->>'errorCode' IS DISTINCT FROM 'ALREADY_MEMBER' THEN RAISE EXCEPTION 'Repeat join changed behavior'; END IF;
  IF (SELECT to_jsonb(o) FROM public.organizations o) IS DISTINCT FROM (SELECT value FROM entitlement_snapshot WHERE name = 'organization')
     OR (SELECT to_jsonb(i) FROM public.organization_invites i) IS DISTINCT FROM (SELECT value FROM entitlement_snapshot WHERE name = 'invite')
     OR (SELECT to_jsonb(m) FROM public.organization_members m) IS DISTINCT FROM (SELECT value FROM entitlement_snapshot WHERE name = 'membership') THEN
    RAISE EXCEPTION 'Refresh/repeat join changed seat, invite or membership';
  END IF;
END $$;

-- Independently prove that each critical quota entry point performs the refresh.
INSERT INTO public.creative_quota_usage(user_id, date, ai_art_count, voice_minutes_used)
  VALUES ('10000000-0000-4000-8000-000000000001', current_date, 2, 5);
UPDATE public.subscriptions SET access_source = 'personal', status = 'expired', expires_at = now() - interval '1 second';
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF public.reserve_ai_image_quota('10000000-0000-4000-8000-000000000001') IS DISTINCT FROM true THEN RAISE EXCEPTION 'Image quota missed sponsorship'; END IF;
END $$;
RESET ROLE;
UPDATE public.subscriptions SET access_source = 'personal', status = 'cancelled', expires_at = NULL;
SET LOCAL ROLE service_role;
DO $$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.reserve_voice_journal_quota('10000000-0000-4000-8000-000000000001', 10);
  IF result.allowed IS DISTINCT FROM true OR result.is_premium IS DISTINCT FROM true OR result.voice_minutes_limit <> 60 OR result.voice_minutes_used <> 15 THEN
    RAISE EXCEPTION 'Journal quota missed sponsorship or changed bounds';
  END IF;
END $$;
RESET ROLE;
UPDATE public.subscriptions SET access_source = 'personal', status = 'expired', expires_at = now() - interval '1 second';
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF public.get_voice_minutes_remaining('10000000-0000-4000-8000-000000000001') <> 999999 THEN RAISE EXCEPTION 'Voice quota missed sponsorship'; END IF;
END $$;
RESET ROLE;

-- Both organization flags and the active membership are required on every refresh.
DO $$ DECLARE state text; BEGIN
  FOREACH state IN ARRAY ARRAY['organization', 'billing', 'membership'] LOOP
    IF state = 'organization' THEN UPDATE public.organizations SET status = 'inactive';
    ELSIF state = 'billing' THEN UPDATE public.organizations SET subscription_status = 'inactive';
    ELSE UPDATE public.organization_members SET is_active = false; END IF;
    PERFORM public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
    IF EXISTS (SELECT 1 FROM public.subscriptions WHERE status = 'active') THEN RAISE EXCEPTION 'Inactive % retained sponsorship', state; END IF;
    UPDATE public.organizations SET status = 'active', subscription_status = 'active';
    UPDATE public.organization_members SET is_active = true;
    PERFORM public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
    IF NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE status = 'active' AND access_source = 'organization_sponsored') THEN RAISE EXCEPTION 'Sponsorship did not resume'; END IF;
  END LOOP;
  -- Client-supplied metadata grants nothing without an existing active membership.
  PERFORM public.refresh_sponsored_entitlement('20000000-0000-4000-8000-000000000002');
  IF EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = '20000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Metadata/admin status minted sponsorship'; END IF;
  IF has_function_privilege('anon', 'public.refresh_sponsored_entitlement(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.refresh_sponsored_entitlement(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.refresh_sponsored_entitlement(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.reserve_ai_image_quota(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.reserve_voice_journal_quota(uuid,integer)', 'EXECUTE') THEN RAISE EXCEPTION 'Entitlement/quota ACL changed'; END IF;
END $$;
-- A service refresh can materialize a missing row for an existing paid seat.
INSERT INTO public.organization_members(organization_id, user_id, is_active)
  VALUES ('90000000-0000-4000-8000-000000000009', '20000000-0000-4000-8000-000000000002', true);
UPDATE public.organizations SET seats_used = 2;
SET LOCAL ROLE service_role;
SELECT public.refresh_sponsored_entitlement('20000000-0000-4000-8000-000000000002');
RESET ROLE;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = '20000000-0000-4000-8000-000000000002'
     AND access_source = 'organization_sponsored' AND status = 'active') THEN RAISE EXCEPTION 'Service failed to materialize missing subscription'; END IF;
  IF (SELECT seats_used FROM public.organizations) <> 2 OR (SELECT uses_count FROM public.organization_invites) <> 1
     OR (SELECT count(*) FROM public.organization_members) <> 2 THEN RAISE EXCEPTION 'Service refresh consumed another seat/use'; END IF;
END $$;
SELECT set_config('request.jwt.claim.role', 'anon', true);
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Anonymous refresh accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"10000000-0000-4000-8000-000000000001","is_anonymous":true}', true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.refresh_sponsored_entitlement('10000000-0000-4000-8000-000000000001');
    RAISE EXCEPTION 'Anonymous authenticated identity accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT 'PASS: purchase preservation, expiry, sponsorship, owner/service authorization, ACLs, unchanged seats/uses, idempotence and critical quotas';
ROLLBACK;
