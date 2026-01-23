-- Add timezone support to coach_settings
-- This fixes the critical bug where silent hours are interpreted as UTC instead of user's local timezone
-- Note: Table is created in later migration (20260701000004_cognitive_coach_schema.sql)

DO $$
BEGIN
    -- Only proceed if table exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'coach_settings'
    ) THEN
        -- Add timezone column with default 'UTC'
        ALTER TABLE coach_settings
        ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';

        -- Add check constraint to validate timezone format (IANA timezone identifiers)
        -- Examples: 'America/Los_Angeles', 'Europe/London', 'Asia/Tokyo'
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'coach_settings_timezone_valid'
        ) THEN
            ALTER TABLE coach_settings
            ADD CONSTRAINT coach_settings_timezone_valid
            CHECK (timezone ~ '^[A-Za-z]+/[A-Za-z_]+$' OR timezone = 'UTC');
        END IF;

        -- Add comment explaining the timezone column
        COMMENT ON COLUMN coach_settings.timezone IS
          'User''s IANA timezone identifier (e.g., America/Los_Angeles). Used to interpret silent_hours_start/end correctly. Default: UTC.';

        -- Add index for timezone lookups (useful for analytics)
        CREATE INDEX IF NOT EXISTS idx_coach_settings_timezone
          ON coach_settings(timezone);

        RAISE NOTICE 'Added timezone support to coach_settings';
    ELSE
        RAISE NOTICE 'coach_settings table does not exist yet, skipping timezone column addition';
    END IF;
END $$;
