-- =====================================================
-- Migration: Add Atomic Rate Limit Check RPC
-- Description: Fixes race condition in capacity rate limiting
-- Date: 2026-01-23
-- =====================================================

-- Atomic Rate Limit Check Function
-- RACE CONDITION FIX: Atomic check-and-increment for rate limiting
-- Returns: JSON with {allowed: boolean, resetAt: timestamptz, remaining: int}
CREATE OR REPLACE FUNCTION check_capacity_rate_limit(
    p_user_id UUID,
    p_window_ms BIGINT,
    p_max_requests INT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rate_limit RECORD;
    v_now TIMESTAMPTZ := now();
    v_window_age_ms BIGINT;
    v_reset_at TIMESTAMPTZ;
    v_remaining INT;
BEGIN
    -- SECURITY: Verify caller is checking their own rate limit
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: Can only check own rate limit';
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

COMMENT ON FUNCTION check_capacity_rate_limit IS 'Atomically check and increment rate limit counter (prevents race conditions)';
