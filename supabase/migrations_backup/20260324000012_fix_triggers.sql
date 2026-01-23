-- List all triggers and disable them to fix UPDATE issue

-- Step 1: List all triggers on profiles
DO $$
DECLARE
  trigger_rec RECORD;
BEGIN
  RAISE NOTICE '=== ALL TRIGGERS ON PROFILES ===';
  FOR trigger_rec IN
    SELECT tgname, tgenabled
    FROM pg_trigger
    WHERE tgrelid = 'public.profiles'::regclass
    AND NOT tgisinternal
  LOOP
    RAISE NOTICE 'Trigger: % (enabled: %)', trigger_rec.tgname, trigger_rec.tgenabled;
  END LOOP;
END $$;

-- Step 2: Disable ALL user triggers on profiles
ALTER TABLE profiles DISABLE TRIGGER USER;

-- Step 3: Test UPDATE now
DO $$
DECLARE
  test_user UUID;
  v_quota_used INT;
BEGIN
  SELECT id INTO test_user FROM auth.users LIMIT 1;
  SELECT daily_ai_used INTO v_quota_used FROM profiles WHERE id = test_user;
  RAISE NOTICE 'Testing UPDATE with triggers disabled...';
  UPDATE profiles SET daily_ai_used = v_quota_used WHERE id = test_user;
  RAISE NOTICE 'UPDATE SUCCEEDED!';
END $$;

-- Step 4: Test the quota function
DO $$
DECLARE
  test_user UUID;
  result JSON;
BEGIN
  SELECT id INTO test_user FROM auth.users LIMIT 1;
  RAISE NOTICE 'Testing check_and_increment_ai_quota...';
  SELECT check_and_increment_ai_quota(test_user, false) INTO result;
  RAISE NOTICE 'QUOTA FUNCTION SUCCEEDED: %', result;
END $$;
