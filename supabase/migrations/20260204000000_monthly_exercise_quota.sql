-- Change content generation quota from 3/day to 1/month for free users
CREATE OR REPLACE FUNCTION "public"."check_and_increment_content_quota"("p_user_id" "uuid", "p_is_premium" boolean DEFAULT false) RETURNS TABLE("allowed" boolean, "quota_used" integer, "quota_limit" integer, "was_reset" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_quota_used INT;
    v_quota_limit INT := 1;  -- Free tier: 1 generation per month
BEGIN
    -- Premium users: always allowed, no limit
    IF p_is_premium THEN
        SELECT COUNT(*)::INT INTO v_quota_used
        FROM generated_content
        WHERE user_id = p_user_id
        AND created_at >= date_trunc('month', CURRENT_DATE)
        AND status != 'failed';

        RETURN QUERY SELECT TRUE, v_quota_used, -1, FALSE;
        RETURN;
    END IF;

    -- Free users: count this month's generations
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM generated_content
    WHERE user_id = p_user_id
    AND created_at >= date_trunc('month', CURRENT_DATE)
    AND status != 'failed';

    -- Check if user has already exceeded quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Quota not exceeded, allow generation
    RETURN QUERY SELECT TRUE, v_quota_used, v_quota_limit, FALSE;
END;
$$;

COMMENT ON FUNCTION "public"."check_and_increment_content_quota"("p_user_id" "uuid", "p_is_premium" boolean) IS 'Checks content generation quota. Free: 1/month, Premium: unlimited.';
