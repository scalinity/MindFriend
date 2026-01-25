-- Ambient Preferences Table
-- Stores user theme and background preferences for the ambient wellness presence feature

CREATE TABLE IF NOT EXISTS ambient_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    active_theme TEXT NOT NULL DEFAULT 'auto' CHECK (active_theme IN ('auto', 'dawn', 'day', 'dusk', 'night', 'ocean', 'forest', 'calm')),
    background_type TEXT NOT NULL DEFAULT 'dynamic' CHECK (background_type IN ('static', 'dynamic', 'animated')),
    auto_adjust_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add comment
COMMENT ON TABLE ambient_preferences IS 'User ambient theme and background preferences for visual wellness experience';

-- Enable RLS
ALTER TABLE ambient_preferences ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only manage their own preferences
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'ambient_preferences' AND policyname = 'Users can view own ambient preferences'
    ) THEN
        CREATE POLICY "Users can view own ambient preferences"
            ON ambient_preferences FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'ambient_preferences' AND policyname = 'Users can insert own ambient preferences'
    ) THEN
        CREATE POLICY "Users can insert own ambient preferences"
            ON ambient_preferences FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'ambient_preferences' AND policyname = 'Users can update own ambient preferences'
    ) THEN
        CREATE POLICY "Users can update own ambient preferences"
            ON ambient_preferences FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'ambient_preferences' AND policyname = 'Users can delete own ambient preferences'
    ) THEN
        CREATE POLICY "Users can delete own ambient preferences"
            ON ambient_preferences FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_ambient_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_ambient_preferences_updated_at ON ambient_preferences;
CREATE TRIGGER trigger_update_ambient_preferences_updated_at
    BEFORE UPDATE ON ambient_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_ambient_preferences_updated_at();

-- Grant access
GRANT SELECT, INSERT, UPDATE, DELETE ON ambient_preferences TO authenticated;
