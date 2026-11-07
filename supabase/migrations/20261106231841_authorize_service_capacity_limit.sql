-- Preserve the service-only ACL while accepting actual service credentials.
BEGIN;
CREATE OR REPLACE FUNCTION public.check_capacity_rate_limit(
    p_user_id UUID,
    p_window_ms BIGINT,
    p_max_requests INT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_rate_limit RECORD;
    v_now TIMESTAMPTZ := now();
    v_window_age_ms BIGINT;
    v_reset_at TIMESTAMPTZ;
    v_remaining INT;
BEGIN
    -- The handler authenticates the target account; this RPC is service-only.
    -- A missing user subject is normal for service credentials, not authority.
    IF current_setting('role', true) IS DISTINCT FROM 'service_role' OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Service role and target account required' USING ERRCODE = '42501';
    END IF;

    -- Atomic SELECT FOR UPDATE to prevent race conditions
    SELECT * INTO v_rate_limit
    FROM capacity_rate_limits
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- First request: create record
        INSERT INTO capacity_rate_limits (user_id, request_count, window_start)
        VALUES (p_user_id, 1, v_now);

        v_reset_at := v_now + (p_window_ms || ' milliseconds')::INTERVAL;
        v_remaining := p_max_requests - 1;

        RETURN json_build_object(
            'allowed', true,
            'resetAt', v_reset_at,
            'remaining', v_remaining
        );
    END IF;

    -- Calculate window age
    v_window_age_ms := EXTRACT(EPOCH FROM (v_now - v_rate_limit.window_start)) * 1000;

    IF v_window_age_ms < p_window_ms THEN
        -- Within current window
        IF v_rate_limit.request_count >= p_max_requests THEN
            -- Rate limit exceeded
            v_reset_at := v_rate_limit.window_start + (p_window_ms || ' milliseconds')::INTERVAL;
            RETURN json_build_object(
                'allowed', false,
                'resetAt', v_reset_at,
                'remaining', 0
            );
        ELSE
            -- Increment count
            UPDATE capacity_rate_limits
            SET request_count = request_count + 1
            WHERE user_id = p_user_id;

            v_reset_at := v_rate_limit.window_start + (p_window_ms || ' milliseconds')::INTERVAL;
            v_remaining := p_max_requests - v_rate_limit.request_count - 1;

            RETURN json_build_object(
                'allowed', true,
                'resetAt', v_reset_at,
                'remaining', v_remaining
            );
        END IF;
    ELSE
        -- Window expired: reset
        UPDATE capacity_rate_limits
        SET request_count = 1, window_start = v_now
        WHERE user_id = p_user_id;

        v_reset_at := v_now + (p_window_ms || ' milliseconds')::INTERVAL;
        v_remaining := p_max_requests - 1;

        RETURN json_build_object(
            'allowed', true,
            'resetAt', v_reset_at,
            'remaining', v_remaining
        );
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_capacity_rate_limit(uuid,bigint,integer) TO service_role;
COMMIT;
