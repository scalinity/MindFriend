-- Reserve the existing creative allowance (2 free / 20 active premium per day)
-- before a paid image request. Retain reservations after uncertain provider errors.
CREATE FUNCTION public.reserve_ai_image_quota(p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE limit_count integer; reserved integer;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Missing image owner' USING ERRCODE='22023'; END IF;
  SELECT CASE WHEN EXISTS(SELECT FROM public.subscriptions WHERE user_id=p_user_id
    AND status='active' AND (expires_at IS NULL OR expires_at>now())) THEN 20 ELSE 2 END INTO limit_count;
  INSERT INTO public.creative_quota_usage(user_id,date,ai_art_count,voice_minutes_used)
    VALUES(p_user_id,current_date,1,0)
    ON CONFLICT(user_id,date) DO UPDATE SET ai_art_count=greatest(creative_quota_usage.ai_art_count,0)+1
      WHERE greatest(creative_quota_usage.ai_art_count,0)<limit_count
    RETURNING ai_art_count INTO reserved;
  RETURN reserved IS NOT NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.reserve_ai_image_quota(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_ai_image_quota(uuid) TO service_role;
