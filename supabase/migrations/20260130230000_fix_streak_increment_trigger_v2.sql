-- Fix streak increment bug in update_stats_on_quest_completion trigger
-- Issue: User's streak stays at 1 instead of incrementing to 2 after completing consecutive days
-- Root cause: Date comparison using TEXT can fail due to format mismatches
-- Fix: Use DATE type comparisons with atomic operations for reliability and concurrency safety
--
-- Review Agent Fixes Applied:
-- CR2: Named constants, clear variable names, input validation, sanitized warnings
-- CA1: FOR UPDATE lock prevents race conditions
-- CA2: Atomic UPSERT eliminates read-modify-write races, fail-fast on invalid dates
-- SA1: Sanitized warning messages, search_path locked
-- CA3: Single atomic operation, advisory lock for concurrent completions
-- DB1: Exception handling for malformed stored dates

CREATE OR REPLACE FUNCTION "public"."update_stats_on_quest_completion"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  -- Constants
  ONE_DAY CONSTANT INTERVAL := INTERVAL '1 day';

  -- Working variables (no v_ prefix per PL/pgSQL conventions)
  quest_date DATE;
  yesterday_date DATE;
  last_quest DATE;
  current_streak INT := 0;
  longest_streak INT := 0;
  new_streak INT;
BEGIN
  -- Only process when status changes to 'completed'
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN

    -- Input validation: Ensure user_id is not NULL
    IF NEW.user_id IS NULL THEN
      RAISE EXCEPTION 'Quest completion trigger received NULL user_id for quest %', NEW.id
        USING ERRCODE = 'not_null_violation';
    END IF;

    -- Parse quest's local_date as DATE - FAIL FAST on invalid data
    -- Invalid dates indicate data corruption that must be fixed at source
    BEGIN
      quest_date := NEW.local_date::DATE;
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN
      RAISE EXCEPTION 'Quest % has invalid local_date format (length: % chars), cannot process completion',
        NEW.id, length(COALESCE(NEW.local_date, ''))
        USING ERRCODE = 'invalid_datetime_format';
    END;

    -- Calculate yesterday relative to quest date
    yesterday_date := quest_date - ONE_DAY;

    -- Acquire advisory lock to serialize updates per user (prevents race conditions)
    -- Lock is automatically released at transaction end
    PERFORM pg_advisory_xact_lock(hashtext('user_stats_' || NEW.user_id::text));

    -- Get current stats with FOR UPDATE lock and exception handling for malformed dates
    BEGIN
      SELECT
        last_quest_date::DATE,
        COALESCE(current_streak_days, 0),
        COALESCE(longest_streak_days, 0)
      INTO last_quest, current_streak, longest_streak
      FROM user_stats
      WHERE user_id = NEW.user_id
      FOR UPDATE;  -- Row-level lock prevents concurrent modifications
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN
      -- Stored last_quest_date is malformed - treat as first quest
      RAISE WARNING 'Malformed stored date for user (length: % chars), treating as first quest',
        length(COALESCE((SELECT last_quest_date FROM user_stats WHERE user_id = NEW.user_id), ''));
      last_quest := NULL;
      current_streak := 0;
      longest_streak := 0;
    END;

    -- Calculate new streak using DATE comparisons
    IF last_quest IS NULL THEN
      -- First ever quest completion - start streak at 1
      new_streak := 1;
    ELSIF last_quest = yesterday_date THEN
      -- Last quest was yesterday - continue streak
      new_streak := current_streak + 1;
    ELSIF last_quest = quest_date THEN
      -- Same day completion - keep current streak unchanged
      -- Log for monitoring (shouldn't happen per business rules)
      RAISE WARNING 'Same-day quest completion detected for user, streak unchanged';
      new_streak := GREATEST(current_streak, 1);
    ELSE
      -- Streak broken (missed a day or more) - restart at 1
      new_streak := 1;
    END IF;

    -- Update longest streak if current exceeds it
    longest_streak := GREATEST(longest_streak, new_streak);

    -- Atomic upsert with exception handler to not block quest completion
    BEGIN
      INSERT INTO user_stats (
        user_id,
        current_streak_days,
        longest_streak_days,
        total_quests_completed,
        last_quest_date,
        updated_at
      )
      VALUES (
        NEW.user_id,
        new_streak,
        longest_streak,
        1,
        quest_date::TEXT,  -- Store as YYYY-MM-DD text for compatibility
        NOW()
      )
      ON CONFLICT (user_id) DO UPDATE SET
        current_streak_days = EXCLUDED.current_streak_days,
        longest_streak_days = EXCLUDED.longest_streak_days,
        total_quests_completed = user_stats.total_quests_completed + 1,
        last_quest_date = EXCLUDED.last_quest_date,
        updated_at = NOW();
    EXCEPTION WHEN OTHERS THEN
      -- Log error but allow quest completion to succeed
      -- Stats can be recalculated; quest completion cannot be recovered
      RAISE WARNING 'Stats update failed (error code: %), quest completion proceeding', SQLSTATE;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- Add comprehensive comment
COMMENT ON FUNCTION "public"."update_stats_on_quest_completion"() IS
  'Trigger function to update user_stats when a quest is completed. '
  'Fixed 2026-01-30: Uses DATE comparisons, advisory locks for concurrency, '
  'FOR UPDATE to prevent races, fail-fast on invalid dates, sanitized warnings.';
