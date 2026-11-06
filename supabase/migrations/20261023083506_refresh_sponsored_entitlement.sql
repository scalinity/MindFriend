BEGIN;

-- Refresh an already occupied organization seat; never claim another invite/use.
CREATE FUNCTION public.refresh_sponsored_entitlement(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_subscription public.subscriptions%ROWTYPE;
  v_org_id uuid;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Missing entitlement owner' USING ERRCODE = '22023';
  END IF;
  IF coalesce(auth.role(), '') <> 'service_role' AND (
    coalesce(auth.role(), '') <> 'authenticated'
    OR auth.uid() IS NULL OR auth.uid() <> p_user_id
    OR coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
  ) THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Share the join RPC's per-user lock, including when no subscription exists.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  SELECT * INTO v_subscription FROM public.subscriptions
    WHERE user_id = p_user_id FOR UPDATE;

  -- A lifetime purchase has no expiry. Keep personal grace periods as join does.
  IF (v_subscription.access_source IS DISTINCT FROM 'organization_sponsored'
      OR v_subscription.plan_type IS DISTINCT FROM 'organization'
      OR v_subscription.product_id IS DISTINCT FROM 'org_sponsored_premium')
     AND v_subscription.status IN ('active', 'grace_period')
     AND (v_subscription.expires_at IS NULL OR v_subscription.expires_at > now()) THEN
    RETURN false;
  END IF;

  SELECT o.id INTO v_org_id
  FROM public.organization_members m
  JOIN public.organizations o ON o.id = m.organization_id
  WHERE m.user_id = p_user_id AND m.is_active = true
    AND o.status = 'active' AND o.subscription_status = 'active'
  ORDER BY (o.id = v_subscription.organization_id) DESC NULLS LAST, m.joined_at, m.id
  LIMIT 1;

  IF v_org_id IS NULL THEN
    -- A materialized sponsorship must not outlive its membership/billing state.
    UPDATE public.subscriptions SET status = 'expired', expires_at = now(), updated_at = now()
      WHERE id = v_subscription.id AND access_source = 'organization_sponsored'
        AND plan_type = 'organization' AND product_id = 'org_sponsored_premium'
        AND status IN ('active', 'grace_period');
    RETURN false;
  END IF;

  INSERT INTO public.subscriptions AS existing (
    user_id, plan_type, status, access_source, organization_id, product_id,
    original_transaction_id, expires_at, organization_sponsor_created_at
  ) VALUES (
    p_user_id, 'organization', 'active', 'organization_sponsored', v_org_id,
    'org_sponsored_premium', 'org_' || v_org_id || '_' || p_user_id, NULL, now()
  ) ON CONFLICT (user_id) DO UPDATE SET
    plan_type = EXCLUDED.plan_type, status = EXCLUDED.status,
    access_source = EXCLUDED.access_source, organization_id = EXCLUDED.organization_id,
    product_id = EXCLUDED.product_id, original_transaction_id = EXCLUDED.original_transaction_id,
    expires_at = NULL, organization_sponsor_created_at = now(), updated_at = now()
  -- Also preserve a concurrent purchase inserted after the empty-row lookup.
  WHERE ((existing.access_source = 'organization_sponsored'
          AND existing.plan_type = 'organization' AND existing.product_id = 'org_sponsored_premium')
      OR existing.status NOT IN ('active', 'grace_period') OR existing.expires_at <= now())
    AND (existing.plan_type, existing.status, existing.access_source, existing.organization_id,
         existing.product_id, existing.original_transaction_id, existing.expires_at)
      IS DISTINCT FROM
        (EXCLUDED.plan_type, EXCLUDED.status, EXCLUDED.access_source, EXCLUDED.organization_id,
         EXCLUDED.product_id, EXCLUDED.original_transaction_id, EXCLUDED.expires_at);
  RETURN EXISTS (SELECT 1 FROM public.subscriptions
    WHERE user_id = p_user_id AND access_source = 'organization_sponsored'
      AND organization_id = v_org_id AND status = 'active' AND plan_type = 'organization'
      AND product_id = 'org_sponsored_premium');
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_sponsored_entitlement(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_sponsored_entitlement(uuid) TO authenticated, service_role;


-- Retain each quota function's bounds, authorization and relay accounting.
CREATE OR REPLACE FUNCTION public.reserve_ai_image_quota(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE limit_count integer; reserved integer;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Missing image owner' USING ERRCODE='22023'; END IF;
  PERFORM public.refresh_sponsored_entitlement(p_user_id);
  SELECT CASE WHEN EXISTS(SELECT FROM public.subscriptions WHERE user_id=p_user_id
    AND status='active' AND (expires_at IS NULL OR expires_at>now())) THEN 20 ELSE 2 END INTO limit_count;
  INSERT INTO public.creative_quota_usage(user_id,date,ai_art_count,voice_minutes_used)
    VALUES(p_user_id,current_date,1,0)
    ON CONFLICT(user_id,date) DO UPDATE SET ai_art_count=greatest(creative_quota_usage.ai_art_count,0)+1
      WHERE greatest(creative_quota_usage.ai_art_count,0)<limit_count
    RETURNING ai_art_count INTO reserved;
  RETURN reserved IS NOT NULL;
END $$;

CREATE OR REPLACE FUNCTION public.reserve_voice_journal_quota(p_user_id uuid, p_minutes integer)
RETURNS TABLE(allowed boolean, voice_minutes_used integer, voice_minutes_limit integer, is_premium boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_premium boolean;
    v_limit integer;
    v_used integer;
    v_reserved integer;
    v_today date := CURRENT_DATE;
BEGIN
    IF p_user_id IS NULL OR p_minutes IS NULL OR p_minutes <= 0 OR p_minutes > 10 THEN
        RAISE EXCEPTION 'Invalid voice journal reservation' USING ERRCODE = '22023';
    END IF;

    PERFORM public.refresh_sponsored_entitlement(p_user_id);
    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions s
        WHERE s.user_id = p_user_id AND s.status = 'active'
          AND (s.expires_at IS NULL OR s.expires_at > now())
    ) INTO v_premium;
    v_limit := CASE WHEN v_premium THEN 60 ELSE 5 END;

    IF p_minutes <= v_limit THEN
        INSERT INTO public.creative_quota_usage AS usage (user_id, date, ai_art_count, voice_minutes_used)
        VALUES (p_user_id, v_today, 0, p_minutes)
        ON CONFLICT (user_id, date) DO UPDATE
        SET voice_minutes_used = greatest(usage.voice_minutes_used, 0) + p_minutes
        WHERE greatest(usage.voice_minutes_used, 0) + p_minutes <= v_limit
        RETURNING usage.voice_minutes_used INTO v_reserved;
    END IF;

    IF v_reserved IS NOT NULL THEN
        RETURN QUERY SELECT true, v_reserved, v_limit, v_premium;
    ELSE
        SELECT greatest(usage.voice_minutes_used, 0) INTO v_used
        FROM public.creative_quota_usage usage
        WHERE usage.user_id = p_user_id AND usage.date = v_today;
        RETURN QUERY SELECT false, coalesce(v_used, 0), v_limit, v_premium;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_voice_minutes_remaining(p_user_id uuid)
RETURNS double precision LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_used double precision; v_reserved integer;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' AND (auth.uid() IS NULL OR auth.uid() <> p_user_id) THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  PERFORM public.refresh_sponsored_entitlement(p_user_id);
  IF EXISTS(SELECT 1 FROM public.profiles WHERE id = p_user_id AND subscription_tier = 'premium')
     OR EXISTS(SELECT 1 FROM public.subscriptions WHERE user_id = p_user_id AND status = 'active' AND (expires_at IS NULL OR expires_at > now())) THEN
    RETURN 999999.0;
  END IF;
  SELECT minutes_used INTO v_used FROM public.voice_usage
    WHERE user_id = p_user_id AND period_start = date_trunc('month', now())::date;
  SELECT coalesce(sum(reserved_seconds), 0) INTO v_reserved FROM public.voice_relay_reservations
    WHERE user_id = p_user_id AND period_start = date_trunc('month', now())::date
      AND claimed_at IS NOT NULL AND finalized_at IS NULL;
  RETURN greatest(0, 3.0 - coalesce(v_used, 0) - v_reserved / 60.0);
END;
$$;

COMMIT;
