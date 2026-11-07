BEGIN;
-- A pending invitation has no second participant. Active pairs remain ordered.
ALTER TABLE public.partner_links DROP CONSTRAINT no_self_partnering;
ALTER TABLE public.partner_links DROP CONSTRAINT user_order;
ALTER TABLE public.partner_links ADD CONSTRAINT no_self_partnering
 CHECK (user_id_2 IS NULL OR user_id_1 <> user_id_2);
ALTER TABLE public.partner_links ADD CONSTRAINT user_order
 CHECK (user_id_2 IS NULL OR user_id_1 < user_id_2);

-- Creating a pending link is now possible, so prevent clients from assigning an
-- arbitrary inviter. The create handler derives it from the verified account.
DROP POLICY "Users insert pending invites" ON public.partner_links;
REVOKE INSERT ON public.partner_links FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.partner_links TO service_role;

CREATE FUNCTION public.accept_partner_invite(p_user_id uuid, p_invite_code_hash text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO pg_catalog, public, pg_temp
AS $$
DECLARE
  v_link public.partner_links%ROWTYPE;
  v_inviter uuid;
  v_locked integer;
BEGIN
  IF current_setting('role', true) IS DISTINCT FROM 'service_role' OR p_user_id IS NULL THEN
    RAISE EXCEPTION 'Service role and verified account required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_link FROM public.partner_links WHERE invite_code_hash=p_invite_code_hash;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'code','NOT_FOUND'); END IF;
  IF v_link.status <> 'pending' OR v_link.user_id_2 IS NOT NULL THEN
    RETURN jsonb_build_object('success',false,'code','ALREADY_ACCEPTED');
  END IF;
  v_inviter := v_link.user_id_1;
  IF v_inviter = p_user_id THEN RETURN jsonb_build_object('success',false,'code','SELF_INVITE'); END IF;

  -- Every acceptance locks both accounts in the same order, including when two
  -- different invitations involve one account in different participant columns.
  PERFORM p.id FROM public.profiles p WHERE p.id IN (v_inviter,p_user_id)
    ORDER BY p.id FOR UPDATE;
  GET DIAGNOSTICS v_locked = ROW_COUNT;
  IF v_locked <> 2 THEN RAISE EXCEPTION 'Participant profile not found' USING ERRCODE='23503'; END IF;

  SELECT * INTO v_link FROM public.partner_links WHERE id=v_link.id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'code','NOT_FOUND'); END IF;
  IF v_link.status <> 'pending' OR v_link.user_id_2 IS NOT NULL THEN
    RETURN jsonb_build_object('success',false,'code','ALREADY_ACCEPTED');
  END IF;
  IF v_link.user_id_1 <> v_inviter OR v_link.created_by <> v_inviter THEN
    RETURN jsonb_build_object('success',false,'code','NOT_FOUND');
  END IF;
  IF v_link.expires_at <= clock_timestamp() THEN
    RETURN jsonb_build_object('success',false,'code','EXPIRED');
  END IF;
  IF EXISTS (SELECT 1 FROM public.partner_links
    WHERE status='active' AND (user_id_1 IN (v_inviter,p_user_id) OR user_id_2 IN (v_inviter,p_user_id))) THEN
    RETURN jsonb_build_object('success',false,'code','ACTIVE_PARTNERSHIP');
  END IF;

  UPDATE public.partner_links SET
    user_id_1=LEAST(v_inviter,p_user_id), user_id_2=GREATEST(v_inviter,p_user_id),
    user_1_share_mood=CASE WHEN v_inviter<p_user_id THEN v_link.user_1_share_mood ELSE false END,
    user_1_share_exercises=CASE WHEN v_inviter<p_user_id THEN v_link.user_1_share_exercises ELSE false END,
    user_2_share_mood=CASE WHEN v_inviter>p_user_id THEN v_link.user_1_share_mood ELSE false END,
    user_2_share_exercises=CASE WHEN v_inviter>p_user_id THEN v_link.user_1_share_exercises ELSE false END,
    status='active',activated_at=clock_timestamp(),updated_at=clock_timestamp()
  WHERE id=v_link.id RETURNING * INTO v_link;
  RETURN jsonb_build_object('success',true,'partner_link',to_jsonb(v_link),'partner_id',v_inviter);
END;
$$;
REVOKE ALL ON FUNCTION public.accept_partner_invite(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_partner_invite(uuid,text) TO service_role;
COMMIT;
