-- LOCAL SYNTHETIC DATABASE ONLY. Every fixture record is rolled back.

BEGIN;
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
  ('91000000-0000-4000-8000-000000000001', 'synthetic-owner@example.invalid', '{}'),
  ('91000000-0000-4000-8000-000000000002', 'synthetic-first@example.invalid', '{}'),
  ('91000000-0000-4000-8000-000000000003', 'synthetic-second@example.invalid', '{}'),
  ('91000000-0000-4000-8000-000000000004', 'synthetic-personal@example.invalid', '{}');
INSERT INTO public.organizations(id, name, billing_email, seat_count, seats_used, status, subscription_status)
  VALUES ('92000000-0000-4000-8000-000000000001', 'Synthetic fixture', 'synthetic-billing@example.invalid', 1, 0, 'active', 'inactive');
INSERT INTO public.organization_admins(id, organization_id, user_id, role)
  VALUES ('93000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'admin');
INSERT INTO public.organization_invites(organization_id, invite_code, max_uses, uses_count, created_by_admin_id)
  VALUES ('92000000-0000-4000-8000-000000000001', 'SYNTHETIC_JOIN_GUARD', 5, 0, '93000000-0000-4000-8000-000000000001');
CREATE FUNCTION pg_temp.reject_synthetic_join_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.organization_id = '92000000-0000-4000-8000-000000000001'::uuid
    AND NEW.actor_id = '91000000-0000-4000-8000-000000000003'::uuid THEN
    RAISE EXCEPTION 'Synthetic late-write failure' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER synthetic_join_failure BEFORE INSERT ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_synthetic_join_audit();
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"91000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    UPDATE public.organizations SET subscription_status = 'active'
      WHERE id = '92000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Authenticated organization admin changed sponsorship';
  EXCEPTION WHEN insufficient_privilege THEN
    IF SQLERRM <> 'Organization sponsorship fields require a service request' THEN RAISE; END IF;
  END;
  -- Normal organization editing must still work through the existing policy.
  UPDATE public.organizations SET name = 'Synthetic renamed fixture'
    WHERE id = '92000000-0000-4000-8000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization details edit was blocked'; END IF;
END;
$$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  first_id uuid := '91000000-0000-4000-8000-000000000002';
  second_id uuid := '91000000-0000-4000-8000-000000000003';
  personal_id uuid := '91000000-0000-4000-8000-000000000004';
  org_id uuid := '92000000-0000-4000-8000-000000000001';
  result jsonb;
BEGIN
  IF has_function_privilege('anon', 'public.join_organization_with_invite(uuid,text)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.join_organization_with_invite(uuid,text)', 'EXECUTE')
    OR NOT has_function_privilege('service_role', 'public.join_organization_with_invite(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'RPC execution grants are unsafe';
  END IF;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'SPONSORSHIP_INACTIVE' THEN RAISE EXCEPTION 'Inactive sponsor admitted: %', result; END IF;
  UPDATE public.organizations SET subscription_status = 'active' WHERE id = org_id;
  UPDATE public.organization_invites SET expires_at = now() - interval '1 minute' WHERE organization_id = org_id;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'INVITE_EXPIRED' THEN RAISE EXCEPTION 'Expired invite admitted: %', result; END IF;
  UPDATE public.organization_invites SET expires_at = NULL WHERE organization_id = org_id;
  UPDATE public.organization_admins SET role = 'viewer' WHERE organization_id = org_id;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'INVITE_DEACTIVATED' THEN RAISE EXCEPTION 'Viewer-issued invite admitted: %', result; END IF;
  UPDATE public.organization_admins SET role = 'admin' WHERE organization_id = org_id;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'success' IS DISTINCT FROM 'true' OR result->'member'->>'user_id' IS DISTINCT FROM first_id::text
    OR result->'member'->>'organization_id' IS DISTINCT FROM org_id::text THEN RAISE EXCEPTION 'Valid join failed: %', result; END IF;
  result := public.join_organization_with_invite(first_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'ALREADY_MEMBER' THEN RAISE EXCEPTION 'Duplicate join admitted: %', result; END IF;
  result := public.join_organization_with_invite(second_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'SEAT_LIMIT_REACHED' THEN RAISE EXCEPTION 'Last seat claimed twice: %', result; END IF;
  UPDATE public.organizations SET seat_count = 2 WHERE id = org_id;
  UPDATE public.organization_invites SET max_uses = 1 WHERE organization_id = org_id;
  result := public.join_organization_with_invite(second_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'errorCode' IS DISTINCT FROM 'MAX_USES_EXCEEDED' THEN RAISE EXCEPTION 'Exhausted invite admitted: %', result; END IF;
  UPDATE public.organization_invites SET max_uses = 5 WHERE organization_id = org_id;
  BEGIN
    PERFORM public.join_organization_with_invite(second_id, 'SYNTHETIC_JOIN_GUARD');
    RAISE EXCEPTION 'Expected the synthetic late-write failure';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT uses_count FROM public.organization_invites WHERE organization_id = org_id) IS DISTINCT FROM 1
    OR (SELECT seats_used FROM public.organizations WHERE id = org_id) IS DISTINCT FROM 1
    OR (SELECT count(*) FROM public.organization_members WHERE organization_id = org_id) <> 1
    OR EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = second_id) THEN
    RAISE EXCEPTION 'Denied or failed join changed invite, seat, membership or entitlement';
  END IF;
  INSERT INTO public.subscriptions(user_id, product_id, original_transaction_id, plan_type, status, access_source, expires_at)
    VALUES (personal_id, 'synthetic_personal', 'synthetic_personal_transaction', 'individual', 'active', 'personal', now() + interval '1 day');
  UPDATE public.subscriptions SET access_source = 'organization_sponsored', organization_id = org_id
    WHERE user_id = personal_id;
  result := public.join_organization_with_invite(personal_id, 'SYNTHETIC_JOIN_GUARD');
  IF result->>'success' IS DISTINCT FROM 'true' OR NOT EXISTS (
    SELECT 1 FROM public.subscriptions WHERE user_id = personal_id AND plan_type = 'individual'
      AND original_transaction_id = 'synthetic_personal_transaction') THEN
    RAISE EXCEPTION 'Existing personal purchase was not retained: %', result;
  END IF;
END;
$$;
RESET ROLE;
ROLLBACK;

