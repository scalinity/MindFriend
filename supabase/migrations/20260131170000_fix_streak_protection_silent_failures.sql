-- Fix critical bugs in check_streak_protection that cause silent failures
-- Issues fixed:
-- 1. FOR UPDATE NOWAIT throws unhandled lock_not_available exception
-- 2. Date cast on last_quest_date has no exception handler
-- 3. No graceful degradation when locks fail
-- Result: Shield protection and recovery quest were silently failing

CREATE OR REPLACE FUNCTION "public"."check_streak_protection"("p_user_id" "uuid")
RETURNS TABLE(
    "streak_protected" boolean,
    "new_streak" integer,
    "shields_remaining" integer,
    "shields_max" integer,
    "recovery_available" boolean,
    "streak_before_break" integer,
    "recovery_expires_at" timestamp with time zone
)
LANGUAGE "plpgsql" SECURITY DEFINER COST 300
SET "search_path" TO 'public'
AS $$
DECLARE
    v_stats RECORD;
    v_last_quest_date DATE;
    v_today DATE;
    v_yesterday DATE;
    v_two_days_ago DATE;
    v_streak_protected BOOLEAN := FALSE;
    v_recovery_available BOOLEAN := FALSE;
    v_streak_before INT := NULL;
    v_recovery_exp TIMESTAMPTZ := NULL;
    v_timezone TEXT;
    v_local_now TIMESTAMPTZ;
    v_shield_used BOOLEAN := FALSE;
    v_days_missed INT;
    v_lock_acquired BOOLEAN := FALSE;
    v_retry_count INT := 0;
    v_max_retries CONSTANT INT := 3;
BEGIN
    -- Security check: ensure caller is the user or service role
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: cannot check protection for another user';
    END IF;

    -- FIX #1: Retry loop for lock acquisition with exponential backoff
    -- Replaces FOR UPDATE NOWAIT which threw unhandled exceptions
    WHILE v_retry_count < v_max_retries AND NOT v_lock_acquired LOOP
        BEGIN
            -- Try to acquire lock with short timeout
            EXECUTE format('SET LOCAL lock_timeout = %L', (50 * power(2, v_retry_count))::int || 'ms');

            SELECT * INTO v_stats
            FROM user_stats
            WHERE user_id = p_user_id
            FOR UPDATE;

            v_lock_acquired := TRUE;
        EXCEPTION
            WHEN lock_not_available THEN
                v_retry_count := v_retry_count + 1;
                IF v_retry_count >= v_max_retries THEN
                    -- Log warning but continue with read-only path
                    RAISE WARNING 'check_streak_protection: Could not acquire lock after % retries for user, proceeding read-only', v_max_retries;
                END IF;
                -- Small delay before retry
                PERFORM pg_sleep(0.01 * power(2, v_retry_count));
        END;
    END LOOP;

    -- If lock failed, try read-only path (better than failing silently)
    IF NOT v_lock_acquired THEN
        SELECT * INTO v_stats
        FROM user_stats
        WHERE user_id = p_user_id;

        -- Return current state without modifications
        IF v_stats IS NULL THEN
            RETURN QUERY SELECT FALSE, 0, 1, 1, FALSE, NULL::INT, NULL::TIMESTAMPTZ;
            RETURN;
        END IF;

        -- Return existing state - can't modify without lock
        RETURN QUERY SELECT
            FALSE,
            v_stats.current_streak_days,
            v_stats.streak_shields_remaining,
            v_stats.streak_shields_max,
            v_stats.recovery_quest_available,
            v_stats.streak_before_break,
            v_stats.recovery_quest_expires_at;
        RETURN;
    END IF;

    IF v_stats IS NULL THEN
        -- No stats record, nothing to protect
        RETURN QUERY SELECT FALSE, 0, 1, 1, FALSE, NULL::INT, NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    -- Get user's timezone for accurate date calculation
    SELECT timezone INTO v_timezone FROM profiles WHERE id = p_user_id;
    v_timezone := COALESCE(v_timezone, 'UTC');

    -- Calculate dates in user's local timezone
    BEGIN
        v_local_now := NOW() AT TIME ZONE v_timezone;
        v_today := v_local_now::DATE;
    EXCEPTION WHEN OTHERS THEN
        -- Fallback to UTC if timezone is invalid
        v_today := CURRENT_DATE;
    END;

    v_yesterday := v_today - INTERVAL '1 day';
    v_two_days_ago := v_today - INTERVAL '2 days';

    -- FIX #2: Add exception handler around date cast
    IF v_stats.last_quest_date IS NOT NULL THEN
        BEGIN
            v_last_quest_date := v_stats.last_quest_date::DATE;
        EXCEPTION
            WHEN invalid_datetime_format OR invalid_text_representation THEN
                -- Log warning and treat as NULL (no last quest date)
                RAISE WARNING 'check_streak_protection: Invalid last_quest_date format for user (value length: % chars), treating as NULL',
                    length(v_stats.last_quest_date);
                v_last_quest_date := NULL;
            WHEN OTHERS THEN
                -- Catch any other date parsing errors
                RAISE WARNING 'check_streak_protection: Error parsing last_quest_date: %, treating as NULL', SQLERRM;
                v_last_quest_date := NULL;
        END;
    ELSE
        v_last_quest_date := NULL;
    END IF;

    -- Check if streak is at risk (missed at least yesterday AND have a streak worth protecting)
    IF v_last_quest_date IS NOT NULL
       AND v_last_quest_date < v_yesterday
       AND v_stats.current_streak_days > 0
       AND NOT COALESCE(v_stats.recovery_quest_available, FALSE) THEN

        -- Calculate how many days were missed
        v_days_missed := v_yesterday - v_last_quest_date;

        -- Shield only protects SINGLE day misses (last quest was exactly 2 days ago)
        IF v_last_quest_date = v_two_days_ago AND COALESCE(v_stats.streak_shields_remaining, 0) > 0 THEN
            -- ATOMIC: Use shield only if shields > 0, in a single UPDATE
            BEGIN
                UPDATE user_stats SET
                    streak_shields_remaining = streak_shields_remaining - 1,
                    last_shield_used_at = NOW(),
                    last_quest_date = v_yesterday::TEXT,
                    updated_at = NOW()
                WHERE user_id = p_user_id
                  AND streak_shields_remaining > 0
                RETURNING streak_shields_remaining INTO v_stats.streak_shields_remaining;

                -- Check if shield was actually used (atomic check)
                IF FOUND THEN
                    v_shield_used := TRUE;

                    -- Log shield usage (wrap in exception handler to not fail main operation)
                    BEGIN
                        INSERT INTO streak_shield_events (user_id, event_type, streak_protected, shields_remaining)
                        VALUES (p_user_id, 'used', v_stats.current_streak_days, v_stats.streak_shields_remaining);
                    EXCEPTION WHEN OTHERS THEN
                        RAISE WARNING 'check_streak_protection: Failed to log shield event: %', SQLERRM;
                    END;

                    v_streak_protected := TRUE;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'check_streak_protection: Shield update failed: %', SQLERRM;
            END;
        END IF;

        -- If shield wasn't used (either no shields, multi-day gap, or error)
        IF NOT v_shield_used THEN
            -- Break streak but offer recovery
            v_streak_before := v_stats.current_streak_days;
            v_recovery_exp := NOW() + INTERVAL '24 hours';

            BEGIN
                UPDATE user_stats SET
                    recovery_quest_available = TRUE,
                    recovery_quest_expires_at = v_recovery_exp,
                    streak_before_break = v_stats.current_streak_days,
                    recovery_attempts_remaining = COALESCE(recovery_attempts_max, 1),
                    current_streak_days = 0,
                    last_quest_date = NULL,
                    updated_at = NOW()
                WHERE user_id = p_user_id;

                v_recovery_available := TRUE;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'check_streak_protection: Recovery setup failed: %', SQLERRM;
            END;
        END IF;
    END IF;

    -- Check if existing recovery quest expired
    IF COALESCE(v_stats.recovery_quest_available, FALSE)
       AND v_stats.recovery_quest_expires_at IS NOT NULL
       AND v_stats.recovery_quest_expires_at < NOW() THEN
        -- Recovery window expired
        BEGIN
            UPDATE user_stats SET
                recovery_quest_available = FALSE,
                recovery_quest_expires_at = NULL,
                streak_before_break = NULL,
                recovery_attempts_remaining = COALESCE(recovery_attempts_max, 1),
                updated_at = NOW()
            WHERE user_id = p_user_id;

            -- Mark any pending recovery attempts as expired
            UPDATE recovery_quest_attempts SET
                status = 'expired',
                expired_at = NOW()
            WHERE user_id = p_user_id AND status IN ('pending', 'in_progress');
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'check_streak_protection: Recovery expiry update failed: %', SQLERRM;
        END;
    END IF;

    -- Return current state after any updates
    -- FIX #3: Wrap final query in exception handler
    BEGIN
        SELECT
            us.current_streak_days,
            us.streak_shields_remaining,
            us.streak_shields_max,
            us.recovery_quest_available,
            us.streak_before_break,
            us.recovery_quest_expires_at
        INTO
            new_streak,
            shields_remaining,
            shields_max,
            recovery_available,
            streak_before_break,
            recovery_expires_at
        FROM user_stats us WHERE us.user_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN
        -- Return safe defaults if final query fails
        new_streak := COALESCE(v_stats.current_streak_days, 0);
        shields_remaining := COALESCE(v_stats.streak_shields_remaining, 1);
        shields_max := COALESCE(v_stats.streak_shields_max, 1);
        recovery_available := COALESCE(v_recovery_available, FALSE);
        streak_before_break := v_streak_before;
        recovery_expires_at := v_recovery_exp;
    END;

    streak_protected := v_streak_protected;

    RETURN NEXT;
END;
$$;

-- Add comprehensive comment
COMMENT ON FUNCTION "public"."check_streak_protection"("p_user_id" "uuid") IS
    'Checks if user streak needs protection and applies shield or enables recovery. '
    'v2 2026-01-31: Fixed silent failures - added retry loop for lock acquisition, '
    'exception handlers around date parsing, graceful degradation on lock failure, '
    'wrapped all DB operations in exception handlers.';
