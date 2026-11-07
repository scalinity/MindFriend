-- Family removal revokes only a proven shared receipt, preserving independent purchases with stale family metadata.
CREATE OR REPLACE FUNCTION public.remove_family_member_atomic(p_actor_id uuid, p_member_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_member public.family_members%ROWTYPE;
  v_family public.family_groups%ROWTYPE;
  v_result jsonb;
  v_target_user uuid;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' OR p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_member FROM public.family_members WHERE id = p_member_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found' USING ERRCODE = '22023'; END IF;
  v_target_user := v_member.user_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_target_user::text, 0));
  SELECT * INTO v_family FROM public.family_groups WHERE id = v_member.family_id FOR UPDATE;
  IF v_family.admin_user_id IS DISTINCT FROM p_actor_id OR v_member.user_id = p_actor_id THEN
    RAISE EXCEPTION 'Only the family owner can remove another member' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_member FROM public.family_members WHERE id = p_member_id FOR UPDATE;
  IF NOT FOUND OR v_member.family_id IS DISTINCT FROM v_family.id OR v_member.user_id IS DISTINCT FROM v_target_user THEN
    RAISE EXCEPTION 'Member changed during removal' USING ERRCODE = '22023';
  END IF;
  -- release_family_seat locks the subscription and decrements once for active members.
  IF v_member.status = 'active' THEN
    v_result := public.release_family_seat(v_family.id, v_member.user_id);
    IF NOT COALESCE((v_result->>'success')::boolean, false) THEN
      RAISE EXCEPTION 'Unable to release family seat' USING ERRCODE = '22023';
    END IF;
  ELSIF v_member.status IS DISTINCT FROM 'removed' THEN
    RAISE EXCEPTION 'Member is not active' USING ERRCODE = '22023';
  END IF;
  UPDATE public.subscriptions SET status = 'expired', expires_at = now(), updated_at = now()
  WHERE user_id = v_member.user_id AND family_id = v_family.id AND is_family_admin = false
    AND plan_type IN ('family', 'couples')
    AND (original_transaction_id = 'family-' || v_family.id::text || '-' || v_member.user_id::text
      OR original_transaction_id = 'family-' || (
        SELECT original_transaction_id FROM public.subscriptions
        WHERE user_id = v_family.admin_user_id AND family_id = v_family.id AND is_family_admin = true
      ));
  DELETE FROM public.circle_members WHERE user_id = v_member.user_id AND circle_id = v_family.circle_id;
  PERFORM public.refresh_user_entitlement(v_member.user_id);
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.remove_family_member_atomic(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_family_member_atomic(uuid, uuid) TO service_role;
