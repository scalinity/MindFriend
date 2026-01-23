-- Minimal test to isolate the issue

-- Create a trivial test function
CREATE OR REPLACE FUNCTION test_minimal()
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN json_build_object('test', 'success');
END;
$$;

-- Test minimal function
DO $$
DECLARE
  result JSON;
BEGIN
  SELECT test_minimal() INTO result;
  RAISE NOTICE 'Minimal test: %', result;
END $$;

-- Test if auth.role() works
DO $$
DECLARE
  role_result TEXT;
BEGIN
  SELECT auth.role() INTO role_result;
  RAISE NOTICE 'auth.role() = %', role_result;
END $$;

-- Test querying profiles directly
DO $$
DECLARE
  test_count INT;
BEGIN
  SELECT COUNT(*) INTO test_count FROM profiles;
  RAISE NOTICE 'Profile count: %', test_count;
END $$;

-- Re-enable the trigger we disabled (if it existed)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_profiles_insert_defaults' AND tgenabled = 'D') THEN
    ALTER TABLE profiles ENABLE TRIGGER tr_profiles_insert_defaults;
    RAISE NOTICE 'Re-enabled tr_profiles_insert_defaults';
  END IF;
END $$;
