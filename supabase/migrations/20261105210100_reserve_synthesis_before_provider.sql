-- Preserve the existing 10/day and 1,250,000-character monthly limits.
-- A reservation is retained after an uncertain provider failure to prevent free replay.
CREATE OR REPLACE FUNCTION public.check_and_increment_synthesis_quota(p_user_id uuid, p_is_premium boolean DEFAULT false, p_character_count integer DEFAULT 0)
 RETURNS TABLE(allowed boolean, quota_used integer, quota_limit integer, was_reset boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
DECLARE
    v_quota_used INT;
    v_quota_limit INT;
BEGIN
    IF p_user_id IS NULL OR p_character_count IS NULL OR p_character_count < 0 THEN
      RAISE EXCEPTION 'Invalid synthesis reservation' USING ERRCODE='22023';
    END IF;
    -- Serialize quota and monthly-character reservations for this account.
    PERFORM pg_advisory_xact_lock(hashtextextended(p_user_id::text, 81824));
    -- Set quota limit based on tier
    IF p_is_premium THEN
        v_quota_limit := 10;  -- Premium: 10/day (reduced from 20, monthly budget is primary control)
    ELSE
        v_quota_limit := 0;   -- Free: blocked at Edge Function level
    END IF;

    -- Count today's synthesis requests
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM synthesis_requests
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE;

    -- Check if user has exceeded daily quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    IF (SELECT COALESCE(SUM(GREATEST(character_count,0)),0) FROM public.synthesis_requests
        WHERE user_id=p_user_id AND created_at>=date_trunc('month',CURRENT_TIMESTAMP))
        + p_character_count > 1250000 THEN
      RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
      RETURN;
    END IF;
    -- Record this request with character count
    INSERT INTO synthesis_requests (user_id, character_count)
    VALUES (p_user_id, p_character_count);

    RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, FALSE;
END;
$function$
;
