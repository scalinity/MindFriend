-- Add timezone support to coach_settings
-- This fixes the critical bug where silent hours are interpreted as UTC instead of user's local timezone

-- Add timezone column with default 'UTC'
ALTER TABLE coach_settings
ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';

-- Add check constraint to validate timezone format (IANA timezone identifiers)
-- Examples: 'America/Los_Angeles', 'Europe/London', 'Asia/Tokyo'
ALTER TABLE coach_settings
ADD CONSTRAINT coach_settings_timezone_valid 
CHECK (timezone ~ '^[A-Za-z]+/[A-Za-z_]+$' OR timezone = 'UTC');

-- Add comment explaining the timezone column
COMMENT ON COLUMN coach_settings.timezone IS 
  'User''s IANA timezone identifier (e.g., America/Los_Angeles). Used to interpret silent_hours_start/end correctly. Default: UTC.';

-- Add index for timezone lookups (useful for analytics)
CREATE INDEX IF NOT EXISTS idx_coach_settings_timezone 
  ON coach_settings(timezone);
