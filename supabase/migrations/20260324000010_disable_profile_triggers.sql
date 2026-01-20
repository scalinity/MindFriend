-- Temporarily disable profile triggers to test if they're causing the issue
-- Note: Triggers may not exist in production, so we handle that gracefully

-- Disable triggers if they exist
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_profiles_column_restrictions') THEN
    ALTER TABLE profiles DISABLE TRIGGER tr_profiles_column_restrictions;
    RAISE NOTICE 'Disabled tr_profiles_column_restrictions';
  ELSE
    RAISE NOTICE 'tr_profiles_column_restrictions does not exist';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'tr_profiles_insert_defaults') THEN
    ALTER TABLE profiles DISABLE TRIGGER tr_profiles_insert_defaults;
    RAISE NOTICE 'Disabled tr_profiles_insert_defaults';
  ELSE
    RAISE NOTICE 'tr_profiles_insert_defaults does not exist';
  END IF;
END $$;

-- Test moved to next migration
