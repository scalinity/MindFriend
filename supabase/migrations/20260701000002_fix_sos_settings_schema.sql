-- Fix SOS Settings Schema
-- Adds missing columns that the iOS app expects

-- Add sos_enabled column (default true - feature is enabled by default)
-- The iOS app encodes this field when inserting settings
ALTER TABLE sos_settings ADD COLUMN IF NOT EXISTS sos_enabled BOOLEAN NOT NULL DEFAULT true;

-- Add include_breathing column (default true - breathing exercises included by default)
-- The iOS app encodes this field when inserting settings
ALTER TABLE sos_settings ADD COLUMN IF NOT EXISTS include_breathing BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN sos_settings.sos_enabled IS 'Whether the SOS feature is enabled for this user';
COMMENT ON COLUMN sos_settings.include_breathing IS 'Whether to include breathing exercises in SOS intervention';
