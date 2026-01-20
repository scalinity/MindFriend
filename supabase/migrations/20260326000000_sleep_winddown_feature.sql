-- Sleep & Wind-Down Feature - Phase 1
-- Tables: sleep_content, sleep_sessions
-- Created: 2026-01-19

-- =============================================================================
-- SLEEP CONTENT TABLE
-- Stores all sleep-related audio content (stories, soundscapes, routines)
-- =============================================================================

CREATE TABLE IF NOT EXISTS sleep_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    content_type TEXT NOT NULL,
    category TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    narrator TEXT,
    is_premium BOOLEAN NOT NULL DEFAULT false,
    is_kids BOOLEAN NOT NULL DEFAULT false,
    audio_url TEXT NOT NULL,
    thumbnail_url TEXT,
    is_loopable BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_featured BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT valid_content_type CHECK (content_type IN ('story', 'soundscape', 'routine')),
    CONSTRAINT valid_category CHECK (category IN ('nature', 'fiction', 'nonfiction', 'asmr', 'ambient', 'white_noise', 'binaural', 'routine')),
    CONSTRAINT positive_duration CHECK (duration_seconds > 0),
    -- Enforce valid content_type/category combinations
    CONSTRAINT valid_category_for_type CHECK (
        (content_type = 'story' AND category IN ('nature', 'fiction', 'nonfiction', 'asmr')) OR
        (content_type = 'soundscape' AND category IN ('nature', 'ambient', 'white_noise', 'binaural')) OR
        (content_type = 'routine' AND category = 'routine')
    )
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_sleep_content_type ON sleep_content(content_type);
CREATE INDEX IF NOT EXISTS idx_sleep_content_category ON sleep_content(category);
CREATE INDEX IF NOT EXISTS idx_sleep_content_type_category ON sleep_content(content_type, category);
CREATE INDEX IF NOT EXISTS idx_sleep_content_premium ON sleep_content(is_premium);
CREATE INDEX IF NOT EXISTS idx_sleep_content_kids ON sleep_content(is_kids);
CREATE INDEX IF NOT EXISTS idx_sleep_content_featured ON sleep_content(is_featured) WHERE is_featured = true;
CREATE INDEX IF NOT EXISTS idx_sleep_content_active ON sleep_content(is_active) WHERE is_active = true;

-- =============================================================================
-- SLEEP SESSIONS TABLE
-- Tracks user playback sessions for analytics and resume functionality
-- =============================================================================

CREATE TABLE IF NOT EXISTS sleep_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id UUID NOT NULL REFERENCES sleep_content(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_listened_seconds INTEGER DEFAULT 0,
    completed BOOLEAN DEFAULT false,
    sleep_timer_used BOOLEAN DEFAULT false,
    timer_duration_minutes INTEGER,
    last_position_seconds INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_user ON sleep_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_content ON sleep_sessions(content_id);
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_user_content ON sleep_sessions(user_id, content_id);
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_resume ON sleep_sessions(user_id, content_id, completed)
    WHERE completed = false;
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_recent ON sleep_sessions(user_id, started_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS
ALTER TABLE sleep_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_sessions ENABLE ROW LEVEL SECURITY;

-- Sleep content: readable by all authenticated users
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_content' AND policyname = 'Sleep content readable by authenticated users'
    ) THEN
        CREATE POLICY "Sleep content readable by authenticated users"
            ON sleep_content FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- Sleep sessions: users can only access their own sessions
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_sessions' AND policyname = 'Users can read own sleep sessions'
    ) THEN
        CREATE POLICY "Users can read own sleep sessions"
            ON sleep_sessions FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_sessions' AND policyname = 'Users can insert own sleep sessions'
    ) THEN
        CREATE POLICY "Users can insert own sleep sessions"
            ON sleep_sessions FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_sessions' AND policyname = 'Users can update own sleep sessions'
    ) THEN
        CREATE POLICY "Users can update own sleep sessions"
            ON sleep_sessions FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sleep_sessions' AND policyname = 'Users can delete own sleep sessions'
    ) THEN
        CREATE POLICY "Users can delete own sleep sessions"
            ON sleep_sessions FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- SEED DATA: Initial sleep content for launch
-- =============================================================================

INSERT INTO sleep_content (title, description, content_type, category, duration_seconds, narrator, is_premium, is_kids, audio_url, thumbnail_url, is_loopable, is_featured, sort_order)
VALUES
    -- Sleep Stories (Free)
    ('Rainy Night in the Forest', 'A gentle walk through a misty forest as rain softly falls on the canopy above. Let the sounds of nature guide you to peaceful sleep.', 'story', 'nature', 1800, 'Sarah', false, false, 'https://storage.supabase.co/sleep/stories/rainy-forest.m4a', NULL, false, true, 1),
    ('The Sleepy Village', 'Visit a cozy village where everyone is settling in for the night. Follow the lamplighter as he dims the streets.', 'story', 'fiction', 1500, 'Michael', false, false, 'https://storage.supabase.co/sleep/stories/sleepy-village.m4a', NULL, false, true, 2),
    ('Mountain Lake at Dusk', 'Sit by a still mountain lake as the sun sets and the stars emerge one by one. Listen to the gentle lapping of waves.', 'story', 'nature', 1200, 'Sarah', false, false, 'https://storage.supabase.co/sleep/stories/mountain-lake.m4a', NULL, false, false, 3),
    ('The Midnight Train', 'Board a sleeper car on a train traveling through the peaceful countryside. Feel the gentle rhythm of the tracks.', 'story', 'fiction', 2100, 'James', false, false, 'https://storage.supabase.co/sleep/stories/midnight-train.m4a', NULL, false, false, 4),

    -- Sleep Stories (Premium)
    ('The Lighthouse Keeper', 'Join the lighthouse keeper on a quiet evening as he tends to his light overlooking the calm sea.', 'story', 'fiction', 2400, 'Michael', true, false, 'https://storage.supabase.co/sleep/stories/lighthouse.m4a', NULL, false, true, 5),
    ('Autumn in the Orchard', 'Wander through an apple orchard on a crisp autumn day as leaves gently fall around you.', 'story', 'nature', 1800, 'Sarah', true, false, 'https://storage.supabase.co/sleep/stories/autumn-orchard.m4a', NULL, false, false, 6),

    -- Soundscapes (Free)
    ('Ocean Waves', 'Rhythmic ocean waves rolling onto a peaceful beach. Perfect for deep relaxation and sleep.', 'soundscape', 'nature', 3600, NULL, false, false, 'https://storage.supabase.co/sleep/soundscapes/ocean-waves.m4a', NULL, true, true, 1),
    ('Gentle Rain', 'Soft rainfall against a window with occasional distant thunder. A classic for sleep.', 'soundscape', 'ambient', 3600, NULL, false, false, 'https://storage.supabase.co/sleep/soundscapes/gentle-rain.m4a', NULL, true, true, 2),
    ('Forest Night', 'Crickets, owl calls, and the peaceful sounds of a forest at night.', 'soundscape', 'nature', 3600, NULL, false, false, 'https://storage.supabase.co/sleep/soundscapes/forest-night.m4a', NULL, true, false, 3),
    ('White Noise', 'Pure white noise for undisturbed sleep. Masks background sounds effectively.', 'soundscape', 'white_noise', 3600, NULL, false, false, 'https://storage.supabase.co/sleep/soundscapes/white-noise.m4a', NULL, true, false, 4),

    -- Soundscapes (Premium)
    ('Binaural Sleep Waves', 'Delta wave binaural beats designed to encourage deep sleep states.', 'soundscape', 'binaural', 3600, NULL, true, false, 'https://storage.supabase.co/sleep/soundscapes/binaural-sleep.m4a', NULL, true, true, 5),
    ('Thunderstorm', 'A distant thunderstorm with rain, creating a cozy atmosphere for sleep.', 'soundscape', 'ambient', 3600, NULL, true, false, 'https://storage.supabase.co/sleep/soundscapes/thunderstorm.m4a', NULL, true, false, 6),
    ('Campfire', 'Crackling campfire with gentle night sounds. Feel the warmth as you drift off.', 'soundscape', 'ambient', 3600, NULL, true, false, 'https://storage.supabase.co/sleep/soundscapes/campfire.m4a', NULL, true, false, 7),

    -- Kids Sleep Stories
    ('The Sleepy Bear', 'Follow a little bear as he says goodnight to all his forest friends and finds the coziest spot to sleep.', 'story', 'fiction', 900, 'Emma', false, true, 'https://storage.supabase.co/sleep/kids/sleepy-bear.m4a', NULL, false, true, 1),
    ('Starlight Dreams', 'Float among the stars and visit friendly planets in this gentle bedtime adventure.', 'story', 'fiction', 720, 'Emma', false, true, 'https://storage.supabase.co/sleep/kids/starlight-dreams.m4a', NULL, false, false, 2)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Function to get resume position for a user and content
CREATE OR REPLACE FUNCTION get_sleep_resume_position(p_user_id UUID, p_content_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_position INTEGER;
BEGIN
    SELECT last_position_seconds INTO v_position
    FROM sleep_sessions
    WHERE user_id = p_user_id
      AND content_id = p_content_id
      AND completed = false
      AND last_position_seconds > 30  -- Only resume if > 30 seconds in
    ORDER BY started_at DESC
    LIMIT 1;

    RETURN COALESCE(v_position, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_sleep_resume_position(UUID, UUID) TO authenticated;
