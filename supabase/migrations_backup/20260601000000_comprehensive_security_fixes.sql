-- =============================================================================
-- Comprehensive Security Fixes Migration
-- Fixes security issues flagged by Supabase Security Advisor
-- =============================================================================
-- Issues addressed:
-- 1. SECURITY DEFINER functions without SET search_path = public
-- 2. Views without SECURITY INVOKER
-- =============================================================================

-- =============================================================================
-- PART 1: Fix all SECURITY DEFINER functions with search_path
-- Uses dynamic ALTER FUNCTION to add search_path to all affected functions
-- =============================================================================

DO $$
DECLARE
    func_record RECORD;
BEGIN
    FOR func_record IN
        SELECT
            p.proname AS function_name,
            pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prosecdef = true  -- SECURITY DEFINER
          AND (p.proconfig IS NULL OR NOT (p.proconfig::text[] @> ARRAY['search_path=public']))
    LOOP
        BEGIN
            EXECUTE format(
                'ALTER FUNCTION public.%I(%s) SET search_path = public',
                func_record.function_name,
                func_record.args
            );
            RAISE NOTICE 'Fixed search_path for function: %(%)', func_record.function_name, func_record.args;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Could not fix function %(%), error: %', func_record.function_name, func_record.args, SQLERRM;
        END;
    END LOOP;
END $$;

-- =============================================================================
-- PART 2: Recreate views with SECURITY INVOKER
-- =============================================================================

-- Drop and recreate v_recent_escalation_attempts with SECURITY INVOKER
DROP VIEW IF EXISTS v_recent_escalation_attempts;
CREATE VIEW v_recent_escalation_attempts
WITH (security_invoker = true)
AS
SELECT
    id,
    user_id,
    event_type,
    severity,
    attempted_changes,
    reason,
    created_at
FROM security_audit_log
WHERE event_type = 'PRIVILEGE_ESCALATION_ATTEMPT'
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

COMMENT ON VIEW v_recent_escalation_attempts IS
    'Shows all privilege escalation attempts from the last 24 hours for investigation. Uses SECURITY INVOKER.';

-- Drop and recreate v_repeat_escalation_offenders with SECURITY INVOKER
DROP VIEW IF EXISTS v_repeat_escalation_offenders;
CREATE VIEW v_repeat_escalation_offenders
WITH (security_invoker = true)
AS
SELECT
    user_id,
    COUNT(*) as attempt_count,
    MAX(created_at) as last_attempt,
    ARRAY_AGG(DISTINCT severity ORDER BY severity DESC) as severity_levels
FROM security_audit_log
WHERE event_type = 'PRIVILEGE_ESCALATION_ATTEMPT'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY user_id
HAVING COUNT(*) > 1
ORDER BY attempt_count DESC;

COMMENT ON VIEW v_repeat_escalation_offenders IS
    'Identifies users with multiple escalation attempts (potential attackers). Uses SECURITY INVOKER.';

-- =============================================================================
-- PART 3: Fix is_moderator function (specific fix for known issue)
-- =============================================================================

CREATE OR REPLACE FUNCTION is_moderator()
RETURNS boolean AS $$
BEGIN
    RETURN COALESCE(
        (SELECT (auth.jwt() -> 'user_metadata' ->> 'role') = 'moderator'),
        false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public;

-- =============================================================================
-- PART 4: Fix generate_anonymous_name function
-- =============================================================================

CREATE OR REPLACE FUNCTION generate_anonymous_name()
RETURNS text AS $$
DECLARE
    animals text[] := ARRAY[
        'Otter', 'Fox', 'Bear', 'Deer', 'Owl', 'Rabbit', 'Squirrel', 'Hedgehog',
        'Wolf', 'Badger', 'Raccoon', 'Moose', 'Panda', 'Koala', 'Penguin',
        'Seal', 'Dolphin', 'Whale', 'Eagle', 'Hawk', 'Sparrow', 'Robin',
        'Swan', 'Duck', 'Turtle', 'Frog', 'Snake', 'Lizard', 'Butterfly', 'Bee',
        'Ant', 'Spider', 'Crab', 'Lobster', 'Starfish', 'Jellyfish', 'Octopus',
        'Shark', 'Lion', 'Tiger', 'Elephant', 'Giraffe', 'Zebra', 'Kangaroo',
        'Sloth', 'Chipmunk', 'Beaver', 'Hamster', 'Porcupine', 'Flamingo'
    ];
    selected_animal text;
BEGIN
    selected_animal := animals[floor(random() * array_length(animals, 1) + 1)];
    RETURN 'Anonymous ' || selected_animal;
END;
$$ LANGUAGE plpgsql VOLATILE SET search_path = public;

-- =============================================================================
-- PART 5: Second pass - ensure ALL SECURITY DEFINER functions have search_path
-- =============================================================================

DO $$
DECLARE
    func_record RECORD;
BEGIN
    FOR func_record IN
        SELECT
            p.proname AS function_name,
            pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prosecdef = true
          AND (p.proconfig IS NULL OR NOT (p.proconfig::text[] @> ARRAY['search_path=public']))
    LOOP
        BEGIN
            EXECUTE format(
                'ALTER FUNCTION public.%I(%s) SET search_path = public',
                func_record.function_name,
                func_record.args
            );
            RAISE NOTICE 'Second pass: Fixed search_path for: %(%)', func_record.function_name, func_record.args;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Second pass: Could not fix %(%), error: %', func_record.function_name, func_record.args, SQLERRM;
        END;
    END LOOP;
END $$;

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
    unfixed_count INT;
BEGIN
    SELECT COUNT(*) INTO unfixed_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND (p.proconfig IS NULL OR NOT (p.proconfig::text[] @> ARRAY['search_path=public']));

    IF unfixed_count > 0 THEN
        RAISE WARNING 'There are still % SECURITY DEFINER functions without search_path set', unfixed_count;
    ELSE
        RAISE NOTICE 'SUCCESS: All SECURITY DEFINER functions now have search_path = public';
    END IF;
END $$;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
