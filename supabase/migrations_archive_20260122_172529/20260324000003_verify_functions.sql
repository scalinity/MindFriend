-- Verify both functions exist and are working

-- Check if ensure_profile_exists exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ensure_profile_exists') THEN
        RAISE EXCEPTION 'CRITICAL: ensure_profile_exists function is missing!';
    ELSE
        RAISE NOTICE 'OK: ensure_profile_exists function exists';
    END IF;
END $$;

-- Check if check_and_increment_ai_quota exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'check_and_increment_ai_quota') THEN
        RAISE EXCEPTION 'CRITICAL: check_and_increment_ai_quota function is missing!';
    ELSE
        RAISE NOTICE 'OK: check_and_increment_ai_quota function exists';
    END IF;
END $$;

-- List all users who don't have profiles (should be empty)
DO $$
DECLARE
    missing_count INT;
BEGIN
    SELECT COUNT(*) INTO missing_count
    FROM auth.users au
    LEFT JOIN profiles p ON au.id = p.id
    WHERE p.id IS NULL;

    IF missing_count > 0 THEN
        RAISE NOTICE 'WARNING: % users missing profiles', missing_count;
    ELSE
        RAISE NOTICE 'OK: All users have profiles';
    END IF;
END $$;

-- Show the actual function definition to verify it has the NULL check
SELECT
    proname,
    pg_get_functiondef(oid) as definition
FROM pg_proc
WHERE proname = 'check_and_increment_ai_quota';
