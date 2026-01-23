-- Sensory Regulation Toolkit: Core Tables
-- Purpose: Store session metadata, user favorites, and preferences
-- Note: Patterns (tactile/visual/audio) are embedded in iOS app; DB stores metadata only

-- Sensory session records (metadata only, patterns stored in app)
CREATE TABLE IF NOT EXISTS sensory_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    modality TEXT NOT NULL CHECK (modality IN ('tactile', 'visual', 'audio')),
    pattern_id TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    interrupted BOOLEAN DEFAULT false,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sensory_sessions_user_id ON sensory_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sensory_sessions_completed_at ON sensory_sessions(completed_at);
CREATE INDEX IF NOT EXISTS idx_sensory_sessions_pattern_id ON sensory_sessions(pattern_id);

-- User favorites for quick access
CREATE TABLE IF NOT EXISTS sensory_favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    modality TEXT NOT NULL CHECK (modality IN ('tactile', 'visual', 'audio')),
    pattern_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, modality, pattern_id)
);

CREATE INDEX IF NOT EXISTS idx_sensory_favorites_user_id ON sensory_favorites(user_id);

-- User settings (synced from iOS UserDefaults)
CREATE TABLE IF NOT EXISTS sensory_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    default_speed TEXT NOT NULL DEFAULT 'medium' CHECK (default_speed IN ('slow', 'medium', 'fast')),
    haptic_intensity REAL NOT NULL DEFAULT 1.0 CHECK (haptic_intensity BETWEEN 0.0 AND 1.0),
    enable_auto_pause BOOLEAN NOT NULL DEFAULT true,
    default_session_duration INTEGER NOT NULL DEFAULT 600 CHECK (default_session_duration BETWEEN 60 AND 1800),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Trigger function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_sensory_sessions_updated_at'
    ) THEN
        CREATE TRIGGER update_sensory_sessions_updated_at
        BEFORE UPDATE ON sensory_sessions
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_sensory_settings_updated_at'
    ) THEN
        CREATE TRIGGER update_sensory_settings_updated_at
        BEFORE UPDATE ON sensory_settings
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- Comments for documentation
COMMENT ON TABLE sensory_sessions IS 'Session metadata for sensory regulation toolkit (tactile/visual/audio)';
COMMENT ON TABLE sensory_favorites IS 'User-favorited patterns for quick access';
COMMENT ON TABLE sensory_settings IS 'User preferences for sensory toolkit (speed, intensity, auto-pause)';
