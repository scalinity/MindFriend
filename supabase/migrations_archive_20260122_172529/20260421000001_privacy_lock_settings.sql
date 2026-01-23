-- Privacy Quick Lock Settings Table
-- Feature: Optional app-level biometric authentication with auto-lock after inactivity

CREATE TABLE IF NOT EXISTS privacy_lock_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    app_lock_enabled BOOLEAN DEFAULT FALSE,
    auto_lock_seconds INTEGER DEFAULT 300,
    quick_lock_method TEXT DEFAULT 'menu' CHECK (quick_lock_method IN ('menu', 'triple_tap')),
    triple_tap_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE privacy_lock_settings ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only read their own privacy lock settings
CREATE POLICY "Users can read own privacy lock settings"
  ON privacy_lock_settings FOR SELECT
  USING (auth.uid() = user_id);

-- Policy: Users can only insert their own privacy lock settings
CREATE POLICY "Users can insert own privacy lock settings"
  ON privacy_lock_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: Users can only update their own privacy lock settings
CREATE POLICY "Users can update own privacy lock settings"
  ON privacy_lock_settings FOR UPDATE
  USING (auth.uid() = user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_privacy_lock_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update updated_at
DROP TRIGGER IF EXISTS trg_privacy_lock_settings_updated ON privacy_lock_settings;
CREATE TRIGGER trg_privacy_lock_settings_updated
    BEFORE UPDATE ON privacy_lock_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_privacy_lock_settings_updated_at();
