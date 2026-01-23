-- =====================================================
-- Migration: Fix Rate Limit RPC for Service Role Key
-- Description: Allow service role to call rate limit check
-- Date: 2026-01-24
-- =====================================================

-- Atomic Rate Limit Check Function (FIXED for service role)
-- SECURITY FIX: Allow service role key to check rate limits on behalf of users
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
    v_calling_uid UUID;
BEGIN
    -- Get the calling user ID (can be NULL for service role)
    v_calling_uid := auth.uid();

    -- SECURITY: Verify caller is either checking their own rate limit OR using service role
    -- Service role has NULL auth.uid() but elevated permissions
    IF v_calling_uid IS NOT NULL AND v_calling_uid != p_user_id THEN
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

COMMENT ON FUNCTION check_capacity_rate_limit IS 'Atomically check and increment rate limit counter (service role compatible)';
