-- Organization admins may edit organization details, but billing state and seat
-- capacity are set by the service-authenticated billing webhook and join RPC.
CREATE FUNCTION public.guard_organization_sponsorship_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated') AND (
    NEW.status IS DISTINCT FROM OLD.status
    OR NEW.subscription_status IS DISTINCT FROM OLD.subscription_status
    OR NEW.seat_count IS DISTINCT FROM OLD.seat_count
    OR NEW.max_seats IS DISTINCT FROM OLD.max_seats
    OR NEW.seats_used IS DISTINCT FROM OLD.seats_used
    OR NEW.plan IS DISTINCT FROM OLD.plan
    OR NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id
    OR NEW.stripe_subscription_id IS DISTINCT FROM OLD.stripe_subscription_id
    OR NEW.grace_period_ends_at IS DISTINCT FROM OLD.grace_period_ends_at
  ) THEN
    RAISE EXCEPTION 'Organization sponsorship fields require a service request' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_organization_sponsorship_fields
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.guard_organization_sponsorship_fields();
REVOKE ALL ON FUNCTION public.guard_organization_sponsorship_fields() FROM PUBLIC, anon, authenticated;

-- Claim an organization invite, seat and sponsorship in one transaction.
-- Called only by join-organization after its caller's JWT is verified.
CREATE FUNCTION public.join_organization_with_invite(p_user_id uuid, p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_org_id uuid;
  v_org public.organizations%ROWTYPE;
  v_invite public.organization_invites%ROWTYPE;
  v_member public.organization_members%ROWTYPE;
  v_subscription public.subscriptions%ROWTYPE;
  v_seats integer;
BEGIN
  -- Serialize joins by the same user, including joins through different codes.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid joining user' USING ERRCODE = '28000';
  END IF;
  -- No access to auth.users is required by this service-only invoker function.
  -- The membership foreign key checks that the verified user still exists.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));

  SELECT organization_id INTO v_org_id FROM public.organization_invites
    WHERE invite_code = upper(btrim(p_invite_code));
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invite code not found', 'errorCode', 'INVITE_NOT_FOUND');
  END IF;

  -- A shared organization lock serializes the last seat across different codes.
  SELECT * INTO v_org FROM public.organizations WHERE id = v_org_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Organization not found', 'errorCode', 'ORG_NOT_FOUND');
  END IF;
  SELECT * INTO v_invite FROM public.organization_invites
    WHERE invite_code = upper(btrim(p_invite_code)) AND organization_id = v_org.id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invite code not found', 'errorCode', 'INVITE_NOT_FOUND');
  END IF;
  IF v_invite.is_active IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invite code has been deactivated', 'errorCode', 'INVITE_DEACTIVATED');
  END IF;
  IF v_invite.expires_at <= now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invite code has expired', 'errorCode', 'INVITE_EXPIRED');
  END IF;
  IF v_invite.max_uses IS NOT NULL AND coalesce(v_invite.uses_count, 0) >= v_invite.max_uses THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invite code has reached maximum uses', 'errorCode', 'MAX_USES_EXCEEDED');
  END IF;
  IF v_org.status IS DISTINCT FROM 'active' OR v_org.subscription_status IS DISTINCT FROM 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Organization sponsorship is not active', 'errorCode', 'SPONSORSHIP_INACTIVE');
  END IF;
  -- An invite cannot borrow an administrator from a different organization.
  IF NOT EXISTS (SELECT 1 FROM public.organization_admins
    WHERE id = v_invite.created_by_admin_id AND organization_id = v_org.id AND role = 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invite issuer is not authorized', 'errorCode', 'INVITE_DEACTIVATED');
  END IF;
  IF EXISTS (SELECT 1 FROM public.organization_members WHERE organization_id = v_org.id AND user_id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Already a member of this organization', 'errorCode', 'ALREADY_MEMBER');
  END IF;
  SELECT greatest(coalesce(v_org.seats_used, 0), count(*)::integer) INTO v_seats
    FROM public.organization_members WHERE organization_id = v_org.id AND is_active = true;
  IF v_seats >= v_org.seat_count THEN
    RETURN jsonb_build_object('success', false, 'error', 'Organization has reached seat capacity', 'errorCode', 'SEAT_LIMIT_REACHED');
  END IF;

  INSERT INTO public.organization_members(organization_id, user_id, joined_at, is_active)
    VALUES (v_org.id, p_user_id, now(), true) RETURNING * INTO v_member;
  INSERT INTO public.subscriptions AS existing (
    user_id, plan_type, status, access_source, organization_id, product_id,
    original_transaction_id, expires_at, organization_sponsor_created_at
  ) VALUES (
    p_user_id, 'organization', 'active', 'organization_sponsored', v_org.id,
    'org_sponsored_premium', 'org_' || v_org.id || '_' || p_user_id, NULL, now()
  ) ON CONFLICT (user_id) DO UPDATE SET
    plan_type = EXCLUDED.plan_type, status = EXCLUDED.status,
    access_source = EXCLUDED.access_source, organization_id = EXCLUDED.organization_id,
    product_id = EXCLUDED.product_id, original_transaction_id = EXCLUDED.original_transaction_id,
    expires_at = EXCLUDED.expires_at, organization_sponsor_created_at = now(), updated_at = now()
  -- Retain an existing, unexpired personal purchase rather than overwrite it.
  WHERE (existing.access_source = 'organization_sponsored'
      AND existing.plan_type = 'organization' AND existing.product_id = 'org_sponsored_premium')
    OR existing.status NOT IN ('active', 'grace_period')
    OR existing.expires_at <= now()
  RETURNING * INTO v_subscription;
  IF v_subscription.id IS NULL THEN
    SELECT * INTO STRICT v_subscription FROM public.subscriptions WHERE user_id = p_user_id;
  END IF;

  UPDATE public.organization_invites SET uses_count = coalesce(uses_count, 0) + 1 WHERE id = v_invite.id;
  UPDATE public.organizations SET seats_used = v_seats + 1 WHERE id = v_org.id;
  INSERT INTO public.audit_log(organization_id, event_type, actor_id, target_user_id, metadata)
    VALUES (v_org.id, 'member_joined', p_user_id, p_user_id,
      jsonb_build_object('invite_id', v_invite.id, 'joined_via', 'invite_code'));
  INSERT INTO public.billing_audit_log(organization_id, event_type, metadata)
    VALUES (v_org.id, 'member_joined_with_subscription',
      jsonb_build_object('user_id', p_user_id, 'subscription_id', v_subscription.id, 'invite_id', v_invite.id));

  RETURN jsonb_build_object('success', true,
    'member', jsonb_build_object('id', v_member.id, 'organization_id', v_member.organization_id,
      'user_id', v_member.user_id, 'joined_at', v_member.joined_at),
    'subscription', jsonb_build_object('tier', v_subscription.plan_type, 'access_source', v_subscription.access_source));
END;
$$;
REVOKE ALL ON FUNCTION public.join_organization_with_invite(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_organization_with_invite(uuid, text) TO service_role;
