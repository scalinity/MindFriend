-- Consume the exact recipient invitation in the same transaction as membership and seats.
CREATE FUNCTION public.join_family_atomic(
  p_user_id uuid, p_invite_code text, p_nickname text DEFAULT NULL,
  p_birth_date date DEFAULT NULL, p_require_invitation boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_invite public.family_invitations%ROWTYPE;
  v_family public.family_groups%ROWTYPE;
  v_admin_sub public.subscriptions%ROWTYPE;
  v_existing_sub public.subscriptions%ROWTYPE;
  v_member public.family_members%ROWTYPE;
  v_email text;
  v_confirmed timestamptz;
  v_role text := 'child';
  v_birth_date date := p_birth_date;
  v_has_invite boolean;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));
  SELECT * INTO v_invite FROM public.family_invitations WHERE invite_code = p_invite_code FOR UPDATE;
  v_has_invite := FOUND;
  IF v_has_invite THEN
    SELECT email, email_confirmed_at INTO v_email, v_confirmed FROM auth.users WHERE id = p_user_id FOR UPDATE;
    IF v_confirmed IS NULL OR lower(trim(v_email)) IS DISTINCT FROM lower(trim(v_invite.email)) THEN
      RAISE EXCEPTION 'Sign in with the confirmed email that received this invitation' USING ERRCODE = '42501';
    END IF;
    IF v_invite.status IS DISTINCT FROM 'pending' OR v_invite.accepted_at IS NOT NULL
       OR v_invite.expires_at IS NULL OR v_invite.expires_at <= now() THEN
      RAISE EXCEPTION 'Invitation is expired or already used' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_family FROM public.family_groups WHERE id = v_invite.family_id FOR UPDATE;
    -- Every administrator-selected role is authoritative, including child.
    v_role := coalesce(v_invite.intended_role, 'child');
    v_birth_date := coalesce(v_invite.intended_birth_date, p_birth_date);
    IF v_role NOT IN ('parent', 'teen', 'child') THEN
      RAISE EXCEPTION 'Invalid invitation role' USING ERRCODE = '22023';
    END IF;
  ELSE
    IF p_require_invitation THEN RAISE EXCEPTION 'Invalid invitation' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_family FROM public.family_groups WHERE invite_code = p_invite_code FOR UPDATE;
    -- A reusable group code does not authorize parent privileges.
  END IF;
  IF v_family.id IS NULL THEN RAISE EXCEPTION 'Invalid invitation' USING ERRCODE = '22023'; END IF;
  IF EXISTS(SELECT 1 FROM public.family_members WHERE user_id = p_user_id AND status = 'active') THEN
    RAISE EXCEPTION 'Already an active family member' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM public.family_members WHERE family_id = v_family.id AND status = 'active') >= coalesce(v_family.max_members, 6) THEN
    RAISE EXCEPTION 'Family has reached maximum members' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_admin_sub FROM public.subscriptions
    WHERE user_id = v_family.admin_user_id AND family_id = v_family.id AND is_family_admin = true
      AND plan_type IN ('family', 'couples') AND status IN ('active', 'grace_period')
      AND (expires_at IS NULL OR expires_at > now()) FOR UPDATE;
  IF v_admin_sub.id IS NULL AND (v_has_invite OR EXISTS(
    SELECT 1 FROM public.subscriptions WHERE user_id=v_family.admin_user_id AND family_id=v_family.id
      AND is_family_admin=true AND plan_type IN ('family','couples')
  )) THEN
    RAISE EXCEPTION 'Family subscription is not active' USING ERRCODE = '22023';
  END IF;
  IF v_admin_sub.id IS NOT NULL THEN
    IF v_admin_sub.seats_used >= v_admin_sub.seats_total THEN
      RAISE EXCEPTION 'No seats available in this family plan' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_existing_sub FROM public.subscriptions WHERE user_id = p_user_id FOR UPDATE;
    IF v_existing_sub.id IS NOT NULL AND v_existing_sub.status IN ('active', 'grace_period')
       AND (v_existing_sub.expires_at IS NULL OR v_existing_sub.expires_at > now())
       AND (v_existing_sub.family_id IS DISTINCT FROM v_family.id OR v_existing_sub.is_family_admin) THEN
      RAISE EXCEPTION 'An existing subscription must end before joining this paid plan' USING ERRCODE = '22023';
    END IF;
    UPDATE public.subscriptions SET seats_used = seats_used + 1, updated_at = now() WHERE id = v_admin_sub.id;
  END IF;
  INSERT INTO public.family_members(family_id,user_id,invited_email,role,nickname,birth_date,status,joined_at,removed_at)
    VALUES(v_family.id,p_user_id,CASE WHEN v_has_invite THEN v_invite.email ELSE NULL END,v_role,p_nickname,v_birth_date,'active',now(),NULL)
    ON CONFLICT(family_id,user_id) DO UPDATE SET status='active',role=excluded.role,nickname=excluded.nickname,
      birth_date=excluded.birth_date,invited_email=excluded.invited_email,joined_at=now(),removed_at=NULL,updated_at=now()
    RETURNING * INTO v_member;
  IF v_admin_sub.id IS NOT NULL THEN
    INSERT INTO public.subscriptions(user_id,product_id,original_transaction_id,status,plan_type,billing_period,family_id,is_family_admin,seats_used,seats_total,expires_at,access_source)
      VALUES(p_user_id,v_admin_sub.product_id,'family-'||v_family.id::text||'-'||p_user_id::text,v_admin_sub.status,
        v_admin_sub.plan_type,v_admin_sub.billing_period,v_family.id,false,0,0,v_admin_sub.expires_at,'personal')
      ON CONFLICT(user_id) DO UPDATE SET product_id=excluded.product_id,original_transaction_id=excluded.original_transaction_id,
        status=excluded.status,plan_type=excluded.plan_type,billing_period=excluded.billing_period,family_id=excluded.family_id,
        is_family_admin=false,seats_used=0,seats_total=0,expires_at=excluded.expires_at,access_source='personal',
        organization_id=NULL,organization_sponsor_created_at=NULL,last_transaction_id=NULL,updated_at=now()
      -- Preserve every actual purchase receipt, including expired personal ownership.
      WHERE public.subscriptions.original_transaction_id LIKE 'family-%'
        AND public.subscriptions.family_id IS NOT NULL AND public.subscriptions.is_family_admin=false;
    INSERT INTO public.billing_events(event_type,user_id,family_id,payload) VALUES('family_seat_claimed',p_user_id,v_family.id,
      jsonb_build_object('seats_used',v_admin_sub.seats_used+1,'seats_total',v_admin_sub.seats_total,'admin_subscription_id',v_admin_sub.id));
  END IF;
  IF v_family.circle_id IS NOT NULL THEN
    INSERT INTO public.circle_members(circle_id,user_id,role) VALUES(v_family.circle_id,p_user_id,'member') ON CONFLICT(circle_id,user_id) DO NOTHING;
  END IF;
  IF v_has_invite THEN
    UPDATE public.family_invitations SET status='accepted',accepted_at=now() WHERE id=v_invite.id;
  END IF;
  PERFORM public.refresh_user_entitlement(p_user_id);
  IF v_admin_sub.id IS NOT NULL THEN
    UPDATE public.profiles SET premium_badge='premium_supporter' WHERE id=p_user_id;
    INSERT INTO public.user_badges(user_id,badge_id)
      SELECT p_user_id,id FROM public.badges WHERE code='premium_supporter'
      ON CONFLICT(user_id,badge_id) DO NOTHING;
  END IF;
  RETURN jsonb_build_object('success',true,'family_id',v_family.id,'family_name',v_family.name,'circle_id',v_family.circle_id,'member_id',v_member.id,'role',v_member.role);
END;
$$;
REVOKE ALL ON FUNCTION public.join_family_atomic(uuid,text,text,date,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.join_family_atomic(uuid,text,text,date,boolean) TO service_role;
