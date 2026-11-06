-- Preserve the existing RPC signature and fixed-window results, including the first row.
-- Only trusted Edge Functions may supply another user's ID or window parameters.
BEGIN;

CREATE OR REPLACE FUNCTION "public"."check_rate_limit"("p_user_id" "uuid", "p_endpoint" "text", "p_window_start" timestamp with time zone, "p_max_requests" integer, "p_window_ms" integer) RETURNS TABLE("allowed" boolean, "remaining" integer, "reset_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_count INT;
  v_window_start TIMESTAMPTZ;
  v_reset_at TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL OR p_endpoint IS NULL OR pg_catalog.btrim(p_endpoint) = ''
     OR p_window_start IS NULL OR NOT pg_catalog.isfinite(p_window_start)
     OR p_window_start > pg_catalog.now()
     OR p_max_requests IS NULL OR p_max_requests <= 0
     OR p_window_ms IS NULL OR p_window_ms <= 0 THEN
    RAISE EXCEPTION 'Invalid rate limit parameters' USING ERRCODE = '22023';
  END IF;

  -- Row locks cannot protect a missing first row. Serialize this key before lookup.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text || ':' || p_endpoint, 0)
  );

  SELECT request_count, window_start
  INTO v_count, v_window_start
  FROM public.rate_limits
  WHERE user_id = p_user_id AND endpoint = p_endpoint
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.rate_limits (user_id, endpoint, request_count, window_start)
    VALUES (p_user_id, p_endpoint, 1, NOW())
    ON CONFLICT (user_id, endpoint) DO UPDATE
    SET request_count = 1, window_start = NOW();

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  IF v_window_start < p_window_start THEN
    UPDATE public.rate_limits
    SET request_count = 1, window_start = NOW()
    WHERE user_id = p_user_id AND endpoint = p_endpoint;

    v_reset_at := NOW() + (p_window_ms || ' milliseconds')::interval;
    RETURN QUERY SELECT TRUE, p_max_requests - 1, v_reset_at;
    RETURN;
  END IF;

  v_reset_at := v_window_start + (p_window_ms || ' milliseconds')::interval;

  IF v_count >= p_max_requests THEN
    RETURN QUERY SELECT FALSE, 0, v_reset_at;
    RETURN;
  END IF;

  UPDATE public.rate_limits
  SET request_count = v_count + 1
  WHERE user_id = p_user_id AND endpoint = p_endpoint;

  RETURN QUERY SELECT TRUE, p_max_requests - v_count - 1, v_reset_at;
END;
$$;

REVOKE ALL ON FUNCTION public.check_rate_limit(uuid,text,timestamptz,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(uuid,text,timestamptz,integer,integer)
  TO service_role;

COMMIT;
