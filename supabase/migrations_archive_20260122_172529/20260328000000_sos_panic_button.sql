-- SOS Panic Button Feature Migration
-- Creates sos_settings and sos_events tables with RLS policies

-- ============================================
-- SOS Settings Table
-- ============================================
CREATE TABLE IF NOT EXISTS sos_settings (
    user_id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,

    -- Emergency contact
    auto_notify_enabled BOOLEAN NOT NULL DEFAULT false,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,

    -- Preferences
    preferred_breathing_pattern TEXT NOT NULL DEFAULT 'calm_478'
        CHECK (preferred_breathing_pattern IN ('box_breathing', 'simple', 'calm_478')),
    countdown_seconds INTEGER NOT NULL DEFAULT 3 CHECK (countdown_seconds BETWEEN 1 AND 10),
    include_grounding BOOLEAN NOT NULL DEFAULT true,
    include_voice_guidance BOOLEAN NOT NULL DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sos_settings IS 'User preferences for SOS panic button feature';
COMMENT ON COLUMN sos_settings.auto_notify_enabled IS 'Whether to auto-notify emergency contact on SOS activation';
COMMENT ON COLUMN sos_settings.preferred_breathing_pattern IS 'box_breathing (4-4-4-4), simple (4-4), calm_478 (4-7-8)';
COMMENT ON COLUMN sos_settings.countdown_seconds IS 'Seconds before family alert is sent (allows cancel)';

-- ============================================
-- SOS Events Table
-- ============================================
CREATE TABLE IF NOT EXISTS sos_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    -- Timing
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,

    -- Context
    trigger_location TEXT, -- 'home', 'chat', 'profile', etc.

    -- Mood tracking
    mood_before INTEGER CHECK (mood_before BETWEEN 1 AND 5),
    mood_after INTEGER CHECK (mood_after BETWEEN 1 AND 5),

    -- Intervention progress
    completed_phases TEXT[] NOT NULL DEFAULT '{}',
    was_interrupted BOOLEAN NOT NULL DEFAULT false,
    intervention_duration_seconds INTEGER,

    -- Feedback
    helpfulness_rating INTEGER CHECK (helpfulness_rating BETWEEN 1 AND 5),
    notes TEXT,

    -- Emergency contact
    family_alert_sent BOOLEAN NOT NULL DEFAULT false,
    contact_notified BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sos_events IS 'Logs of SOS panic button activations for analytics and safety monitoring';
COMMENT ON COLUMN sos_events.completed_phases IS 'Array of phase names: breathing, grounding, resources, checkin';
COMMENT ON COLUMN sos_events.trigger_location IS 'Screen where SOS was triggered for UX analysis';

-- ============================================
-- Indexes for Performance
-- ============================================
CREATE INDEX IF NOT EXISTS idx_sos_events_user_id ON sos_events(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_events_started_at ON sos_events(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_sos_events_user_started ON sos_events(user_id, started_at DESC);

-- ============================================
-- Enable RLS
-- ============================================
ALTER TABLE sos_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_events ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS Policies: sos_settings
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_settings' AND policyname = 'Users can read own SOS settings') THEN
        CREATE POLICY "Users can read own SOS settings"
            ON sos_settings FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_settings' AND policyname = 'Users can insert own SOS settings') THEN
        CREATE POLICY "Users can insert own SOS settings"
            ON sos_settings FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_settings' AND policyname = 'Users can update own SOS settings') THEN
        CREATE POLICY "Users can update own SOS settings"
            ON sos_settings FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================
-- RLS Policies: sos_events
-- ============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_events' AND policyname = 'Users can read own SOS events') THEN
        CREATE POLICY "Users can read own SOS events"
            ON sos_events FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_events' AND policyname = 'Users can insert own SOS events') THEN
        CREATE POLICY "Users can insert own SOS events"
            ON sos_events FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_events' AND policyname = 'Users can update own SOS events') THEN
        CREATE POLICY "Users can update own SOS events"
            ON sos_events FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Family admins can read family member SOS events (for safety monitoring)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sos_events' AND policyname = 'Family admins can read family member SOS events') THEN
        CREATE POLICY "Family admins can read family member SOS events"
            ON sos_events FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM family_members fm1
                    JOIN family_members fm2 ON fm1.family_id = fm2.family_id
                    WHERE fm1.user_id = auth.uid()
                    AND fm1.role IN ('admin', 'parent')
                    AND fm2.user_id = sos_events.user_id
                )
            );
    END IF;
END $$;

-- ============================================
-- Updated At Trigger
-- ============================================
CREATE OR REPLACE FUNCTION update_sos_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_sos_settings_updated_at ON sos_settings;
CREATE TRIGGER trigger_sos_settings_updated_at
    BEFORE UPDATE ON sos_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_sos_settings_updated_at();
