-- COMPREHENSIVE Security Hardening: Fix all SECURITY DEFINER Functions search_path
-- Issue #003: Prevent search path injection attacks on ALL SECURITY DEFINER functions
-- This migration batch-updates all remaining functions that lack SET search_path = public

-- Already fixed in previous migrations:
-- - check_and_increment_ai_quota (20260317000001)
-- - check_rate_limit (20260317000001)
-- - is_handle_available (20260206000000)
-- - enforce_profiles_column_restrictions (20260317000000)

-- Fixing all remaining SECURITY DEFINER functions (approximately 90+ functions):

-- From various migrations - set search_path for all SECURITY DEFINER functions
-- This script safely alters functions that may or may not have the setting already

-- Helper: Safely add search_path to a function if it doesn't have it
DO $$
DECLARE
    proc_record RECORD;
BEGIN
    -- Iterate through all SECURITY DEFINER functions in public schema
    FOR proc_record IN
        SELECT p.oid, p.proname, pg_get_functiondef(p.oid) as func_def
        FROM pg_proc p
        WHERE p.prosecdef = true
          AND p.pronamespace = 'public'::regnamespace::oid
        ORDER BY p.proname
    LOOP
        -- Check if search_path is already set
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc
            WHERE oid = proc_record.oid
            AND proconfig::text LIKE '%search_path%'
        ) THEN
            -- Try to add search_path to this function
            -- Note: This uses dynamic SQL which requires careful handling
            EXECUTE 'ALTER FUNCTION ' || proc_record.proname || ' SET search_path = public';
            RAISE NOTICE 'Fixed search_path for function: %', proc_record.proname;
        END IF;
    END LOOP;
END $$;

-- Manual fixes for known SECURITY DEFINER functions that may need search_path
-- (Backup to the above automated approach)

-- From 20260208000000_streak_recovery.sql
ALTER FUNCTION IF EXISTS public.use_streak_shield(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.activate_streak_recovery(UUID) SET search_path = public;

-- From 20260219000000_proactive_intelligence.sql
ALTER FUNCTION IF EXISTS public.should_send_proactive_message(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.get_next_proactive_nudge(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.mark_proactive_sent(UUID, TEXT) SET search_path = public;
ALTER FUNCTION IF EXISTS public.get_user_proactive_settings(UUID) SET search_path = public;

-- From 20260311000000_achievement_system_v2.sql
ALTER FUNCTION IF EXISTS public.award_achievement_xp(UUID, INT, TEXT) SET search_path = public;
ALTER FUNCTION IF EXISTS public.check_achievement_milestone(UUID, TEXT) SET search_path = public;

-- From 20260306000000_creative_expression.sql
ALTER FUNCTION IF EXISTS public.get_creative_quota(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.check_creative_rate_limit(UUID, TEXT) SET search_path = public;
ALTER FUNCTION IF EXISTS public.award_creative_points(UUID, INT, TEXT) SET search_path = public;

-- From 20260216000000_celebration_sharing.sql
ALTER FUNCTION IF EXISTS public.check_milestone_triggers(UUID, TEXT) SET search_path = public;
ALTER FUNCTION IF EXISTS public.get_celebration_stats(UUID) SET search_path = public;

-- From 20260220000000_structured_programs.sql
ALTER FUNCTION IF EXISTS public.get_program_progress(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.update_program_session(UUID, UUID, TEXT) SET search_path = public;
ALTER FUNCTION IF EXISTS public.check_program_milestone(UUID) SET search_path = public;

-- From 20260303000000_live_experiences.sql
ALTER FUNCTION IF EXISTS public.get_live_sessions(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.get_circle_rooms(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.check_live_event_access(UUID, UUID) SET search_path = public;

-- From 20260120000000_progression_system.sql
ALTER FUNCTION IF EXISTS public.update_user_level(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.check_level_milestone(UUID, INT) SET search_path = public;

-- From 20260212000000_quest_choice.sql
ALTER FUNCTION IF EXISTS public.get_available_quest_choices(UUID) SET search_path = public;
ALTER FUNCTION IF EXISTS public.record_quest_choice(UUID, UUID) SET search_path = public;

-- From 20260202000000_assign_daily_quest_rpc.sql
ALTER FUNCTION IF EXISTS public.assign_daily_quest(UUID) SET search_path = public;

-- From 20260228000000_atomic_family_member_add.sql
ALTER FUNCTION IF EXISTS public.add_family_member(UUID, UUID, TEXT, TEXT, DATE) SET search_path = public;

-- From 20260321000000_optimize_family_rls.sql
ALTER FUNCTION IF EXISTS public.is_family_member(UUID) SET search_path = public;

-- From 20260216000001_mood_adaptive_security_fix.sql
ALTER FUNCTION IF EXISTS public.check_mood_based_content(UUID, UUID) SET search_path = public;

-- Verification: All SECURITY DEFINER functions should now have search_path set
-- Run this query to verify (produces empty result if all are fixed):
-- SELECT p.proname FROM pg_proc p
-- WHERE p.prosecdef = true
--   AND p.pronamespace = 'public'::regnamespace::oid
--   AND (p.proconfig IS NULL OR NOT ('search_path=public' = ANY(p.proconfig)));

COMMENT ON SCHEMA public IS 'All SECURITY DEFINER functions in public schema have SET search_path = public for search path injection protection';
