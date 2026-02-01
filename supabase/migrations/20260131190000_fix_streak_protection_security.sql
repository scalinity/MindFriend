-- Fix security and correctness issues in check_streak_protection
-- Issues fixed:
-- 1. Authorization bypass via NULL auth.uid() (service role must be explicitly checked)
-- 2. Added jitter to retry delays to prevent thundering herd
-- 3. Removed incorrect last_quest_date update when shield is used

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
    v_jitter FLOAT;
BEGIN
    -- FIX #1: Enhanced security check
    -- Service role (auth.uid() = NULL) is allowed for cron jobs
    -- Regular users can only check their own protection
    IF auth.uid() IS NOT NULL THEN
        -- Authenticated user - must be checking their own protection
        IF auth.uid() != p_user_id THEN
            RAISE EXCEPTION 'Unauthorized: cannot check protection for another user';
        END IF;
    ELSE
        -- NULL auth.uid() - only allowed from service role context
        -- This happens when called from Edge Functions using service role key
        -- Additional validation: check if request has service role claim
        IF current_setting('request.jwt.claims', true) IS NOT NULL THEN
            -- Has JWT claims but no uid - could be anonymous key
            IF (current_setting('request.jwt.claims', true)::jsonb->>'role') NOT IN ('service_role', 'authenticated') THEN
                RAISE EXCEPTION 'Unauthorized: anonymous access denied';
            END IF;
        END IF;
        -- If no JWT claims at all, allow (direct service role call without JWT)
    END IF;

    -- FIX #2: Retry loop with jitter to prevent thundering herd
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
                    RAISE WARNING 'check_streak_protection: Could not acquire lock after % retries, proceeding read-only', v_max_retries;
                END IF;
                -- FIX #2: Add jitter to delay (0.5x to 1.5x base delay) to prevent thundering herd
                v_jitter := 0.5 + random();  -- Random between 0.5 and 1.5
                PERFORM pg_sleep(0.01 * power(2, v_retry_count) * v_jitter);
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
        -- Log and fallback to UTC if timezone is invalid
        RAISE WARNING 'check_streak_protection: Invalid timezone "%" for user, falling back to UTC', v_timezone;
        v_today := CURRENT_DATE;
    END;

    v_yesterday := v_today - INTERVAL '1 day';
    v_two_days_ago := v_today - INTERVAL '2 days';

    -- Date cast with exception handler
    IF v_stats.last_quest_date IS NOT NULL THEN
        BEGIN
            v_last_quest_date := v_stats.last_quest_date::DATE;
        EXCEPTION
            WHEN invalid_datetime_format OR invalid_text_representation THEN
                RAISE WARNING 'check_streak_protection: Invalid last_quest_date format (length: % chars), treating as NULL',
                    length(v_stats.last_quest_date);
                v_last_quest_date := NULL;
            WHEN OTHERS THEN
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
            -- FIX #3: Do NOT update last_quest_date - shield "forgives" the miss
            -- but doesn't pretend the user completed a quest
            BEGIN
                UPDATE user_stats SET
                    streak_shields_remaining = streak_shields_remaining - 1,
                    last_shield_used_at = NOW(),
                    -- REMOVED: last_quest_date = v_yesterday::TEXT (incorrect - would fake quest completion)
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
            -- Calculate recovery expiry at midnight user's local time + 1 day
            BEGIN
                v_recovery_exp := ((v_today + INTERVAL '1 day')::DATE::TIMESTAMP AT TIME ZONE v_timezone) + INTERVAL '23 hours 59 minutes';
            EXCEPTION WHEN OTHERS THEN
                -- Fallback to 24 hours from now if timezone calculation fails
                v_recovery_exp := NOW() + INTERVAL '24 hours';
            END;

            BEGIN
                UPDATE user_stats SET
                    recovery_quest_available = TRUE,
                    recovery_quest_expires_at = v_recovery_exp,
                    streak_before_break = v_stats.current_streak_days,
                    recovery_attempts_remaining = COALESCE(recovery_attempts_max, 1),
                    current_streak_days = 0,
                    -- Keep last_quest_date for history tracking
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

-- Update comment with security and correctness fixes
COMMENT ON FUNCTION "public"."check_streak_protection"("p_user_id" "uuid") IS
    'Checks if user streak needs protection and applies shield or enables recovery. '
    'v3 2026-01-31: Fixed authorization bypass (NULL auth.uid()), added jitter to retries, '
    'fixed incorrect last_quest_date update on shield usage, improved recovery expiry calculation.';
