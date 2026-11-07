BEGIN;

-- Profiles are a display cache, never proof that a purchase is still current.
-- Internal calculation shared by guarded RPCs and subscription triggers. A
-- scheduled expiry trigger may have no request JWT; clients cannot call this.
CREATE OR REPLACE FUNCTION public.compute_current_premium_access(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.subscriptions s WHERE s.user_id = p_user_id
      AND s.status IN ('active', 'grace_period') AND (s.expires_at IS NULL OR s.expires_at > now())
      -- A sponsored or shared row requires its current source of access below.
      AND NOT (s.access_source = 'organization_sponsored' AND s.plan_type = 'organization'
               AND s.product_id = 'org_sponsored_premium')
      AND (s.plan_type = 'individual' OR s.family_id IS NULL OR s.is_family_admin = true)
  ) OR EXISTS (
    SELECT 1 FROM public.family_members m
    JOIN public.family_groups f ON f.id = m.family_id
    JOIN public.subscriptions admin_sub ON admin_sub.user_id = f.admin_user_id
      AND admin_sub.family_id = f.id AND admin_sub.is_family_admin = true
    WHERE m.user_id = p_user_id AND m.status = 'active'
      AND admin_sub.plan_type IN ('family', 'couples')
      AND admin_sub.status IN ('active', 'grace_period')
      AND (admin_sub.expires_at IS NULL OR admin_sub.expires_at > now())
  ) OR EXISTS (
    SELECT 1 FROM public.organization_members m
    JOIN public.organizations o ON o.id = m.organization_id
    WHERE m.user_id = p_user_id AND m.is_active = true
      AND o.status = 'active' AND o.subscription_status = 'active'
  );
$$;
REVOKE ALL ON FUNCTION public.compute_current_premium_access(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compute_current_premium_access(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.has_current_premium_access(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Missing entitlement owner' USING ERRCODE = '22023';
  END IF;
  IF coalesce(auth.role(), '') <> 'service_role' AND (
    coalesce(auth.role(), '') <> 'authenticated' OR auth.uid() IS NULL OR auth.uid() <> p_user_id
    OR coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
  ) THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  RETURN public.compute_current_premium_access(p_user_id);
END $$;
REVOKE ALL ON FUNCTION public.has_current_premium_access(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_current_premium_access(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.refresh_user_entitlement(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_premium boolean;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Missing entitlement owner' USING ERRCODE = '22023';
  END IF;
  -- Same per-user ordering as organization admission; do not rewrite purchases.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  v_premium := public.has_current_premium_access(p_user_id);
  UPDATE public.profiles SET
    subscription_tier = (CASE WHEN v_premium THEN 'premium' ELSE 'free' END)::public.subscription_tier,
    daily_ai_quota = CASE WHEN v_premium THEN -1 ELSE 5 END,
    premium_badge = CASE WHEN v_premium THEN premium_badge ELSE NULL END
  WHERE id = p_user_id AND (subscription_tier, daily_ai_quota,
    CASE WHEN v_premium THEN NULL ELSE premium_badge END)
    IS DISTINCT FROM ((CASE WHEN v_premium THEN 'premium' ELSE 'free' END)::public.subscription_tier,
      CASE WHEN v_premium THEN -1 ELSE 5 END, NULL::text);
  RETURN v_premium;
END $$;
REVOKE ALL ON FUNCTION public.refresh_user_entitlement(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_user_entitlement(uuid) TO service_role;

-- Called only after Apple's signed payload and appAccountToken are verified.
-- A refund of an older transaction must not cancel a newer verified renewal.
CREATE OR REPLACE FUNCTION public.revoke_verified_apple_transaction(
  p_user_id uuid, p_original_transaction_id text, p_transaction_id text
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL OR nullif(btrim(p_original_transaction_id), '') IS NULL
    OR nullif(btrim(p_transaction_id), '') IS NULL THEN
    RAISE EXCEPTION 'Missing verified transaction owner' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  UPDATE public.subscriptions SET status = 'cancelled', updated_at = now()
    WHERE user_id = p_user_id AND original_transaction_id = p_original_transaction_id
      AND last_transaction_id = p_transaction_id AND status <> 'cancelled';
  IF NOT FOUND THEN RETURN false; END IF;
  PERFORM public.refresh_user_entitlement(p_user_id);
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.revoke_verified_apple_transaction(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_verified_apple_transaction(uuid,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_voice_minutes_remaining(p_user_id uuid)
RETURNS double precision LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_used double precision; v_reserved integer;
BEGIN
  IF public.has_current_premium_access(p_user_id) THEN RETURN 999999.0; END IF;
  SELECT minutes_used INTO v_used FROM public.voice_usage
    WHERE user_id = p_user_id AND period_start = date_trunc('month', now())::date;
  SELECT coalesce(sum(reserved_seconds), 0) INTO v_reserved FROM public.voice_relay_reservations
    WHERE user_id = p_user_id AND period_start = date_trunc('month', now())::date
      AND claimed_at IS NOT NULL AND finalized_at IS NULL;
  RETURN greatest(0, 3.0 - coalesce(v_used, 0) - v_reserved / 60.0);
END $$;

CREATE OR REPLACE FUNCTION public.check_and_increment_rehearsal_quota(p_user_id uuid)
RETURNS TABLE(can_create boolean, used integer, quota_limit integer, reset_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_used integer; v_reset_at timestamptz;
BEGIN
  IF public.has_current_premium_access(p_user_id) THEN
    RETURN QUERY SELECT true, 0, 999999, now(); RETURN;
  END IF;
  -- Also serialize the first reservation, before a settings row exists.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 0));
  INSERT INTO public.user_settings (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
  SELECT coalesce(rehearsals_used_this_week, 0), coalesce(rehearsals_quota_reset_at, now())
    INTO v_used, v_reset_at FROM public.user_settings WHERE user_id = p_user_id FOR UPDATE;
  IF v_reset_at < now() - interval '7 days' THEN v_used := 0; v_reset_at := now(); END IF;
  IF v_used < 2 THEN
    UPDATE public.user_settings SET rehearsals_used_this_week = v_used + 1,
      rehearsals_quota_reset_at = v_reset_at WHERE user_id = p_user_id;
    RETURN QUERY SELECT true, v_used + 1, 2, v_reset_at + interval '7 days';
  ELSE
    RETURN QUERY SELECT false, v_used, 2, v_reset_at + interval '7 days';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_and_increment_rehearsal_quota(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_rehearsal_quota(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_ai_image_quota(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE limit_count integer; reserved integer;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Missing image owner' USING ERRCODE='22023'; END IF;
  PERFORM public.refresh_sponsored_entitlement(p_user_id);
  SELECT CASE WHEN public.has_current_premium_access(p_user_id) THEN 20 ELSE 2 END INTO limit_count;
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
    v_premium := public.has_current_premium_access(p_user_id);
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

REVOKE ALL ON FUNCTION public.reserve_ai_image_quota(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_voice_journal_quota(uuid,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_ai_image_quota(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.reserve_voice_journal_quota(uuid,integer) TO service_role;

-- Cancel only access derived from the expiring family's purchase. A personal
-- purchase may retain a stale family marker and must keep its receipt/expiry.
CREATE OR REPLACE FUNCTION public.revoke_family_premium_on_expiry()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_member record; v_premium boolean; v_changed integer;
BEGIN
  IF NEW.is_family_admin = true AND NEW.family_id IS NOT NULL
     AND OLD.status IN ('active', 'grace_period')
     AND (NEW.status IN ('expired', 'cancelled') OR NEW.expires_at <= now())
     AND (OLD.status, OLD.expires_at) IS DISTINCT FROM (NEW.status, NEW.expires_at) THEN
    -- Do not take member advisory/family-row locks after the admin row is locked:
    -- family admission takes those locks before its admin subscription lock.
    FOR v_member IN SELECT user_id FROM public.family_members
      WHERE family_id = NEW.family_id AND user_id <> NEW.user_id AND status = 'active'
    LOOP
      UPDATE public.subscriptions SET status = 'expired', expires_at = now(), updated_at = now()
        WHERE user_id = v_member.user_id AND family_id = NEW.family_id AND is_family_admin = false
          AND plan_type IN ('family', 'couples') AND status IN ('active', 'grace_period')
          AND original_transaction_id IN (
            'family-' || NEW.family_id::text || '-' || v_member.user_id::text,
            'family-' || OLD.original_transaction_id
          );
      GET DIAGNOSTICS v_changed = ROW_COUNT;
      v_premium := public.compute_current_premium_access(v_member.user_id);
      UPDATE public.profiles SET
        subscription_tier = (CASE WHEN v_premium THEN 'premium' ELSE 'free' END)::public.subscription_tier,
        daily_ai_quota = CASE WHEN v_premium THEN -1 ELSE 5 END,
        premium_badge = CASE WHEN v_premium THEN premium_badge ELSE NULL END
        WHERE id = v_member.user_id;
      IF v_changed > 0 THEN
        INSERT INTO public.billing_events(event_type,user_id,family_id,subscription_id,payload)
        VALUES ('subscription_expired',v_member.user_id,NEW.family_id,NEW.id,
          jsonb_build_object('reason','admin_subscription_expired','admin_user_id',NEW.user_id));
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.revoke_family_premium_on_expiry() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_family_premium_on_expiry() TO service_role;
-- The baseline registers the same trigger function twice.
DROP TRIGGER IF EXISTS trigger_revoke_family_premium ON public.subscriptions;

COMMIT;
