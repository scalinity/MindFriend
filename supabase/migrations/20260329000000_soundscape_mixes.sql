-- Migration: Soundscape Mixer Feature
-- Creates tables for soundscape sounds and user-saved mixes

-- =============================================================================
-- SOUNDSCAPE SOUNDS TABLE
-- Individual sounds that can be layered in the mixer
-- =============================================================================

CREATE TABLE IF NOT EXISTS soundscape_sounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN (
        'binaural', 'nature', 'ambient', 'lofi', 'white_noise'
    )),
    audio_url TEXT NOT NULL,
    thumbnail_url TEXT,
    icon_name TEXT NOT NULL DEFAULT 'waveform',
    is_premium BOOLEAN NOT NULL DEFAULT false,
    duration_seconds INTEGER, -- NULL for infinite loops (most soundscapes)
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for soundscape_sounds
CREATE INDEX IF NOT EXISTS idx_soundscape_sounds_category
    ON soundscape_sounds(category);
CREATE INDEX IF NOT EXISTS idx_soundscape_sounds_active
    ON soundscape_sounds(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_soundscape_sounds_category_active
    ON soundscape_sounds(category, is_active, sort_order) WHERE is_active = true;

-- RLS for soundscape_sounds (public read for active sounds)
ALTER TABLE soundscape_sounds ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'soundscape_sounds'
        AND policyname = 'Users can read active soundscape sounds'
    ) THEN
        CREATE POLICY "Users can read active soundscape sounds"
            ON soundscape_sounds FOR SELECT
            USING (is_active = true);
    END IF;
END $$;

-- =============================================================================
-- SOUNDSCAPE MIXES TABLE
-- User-saved mix configurations
-- =============================================================================

CREATE TABLE IF NOT EXISTS soundscape_mixes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (
        length(trim(name)) >= 1 AND length(name) <= 100
    ),
    layers JSONB NOT NULL DEFAULT '[]' CHECK (
        jsonb_array_length(layers) <= 5
    ),
    -- JSONB structure: [{"sound_id": "uuid", "volume": 0.75, "pan": 0.0}, ...]
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for soundscape_mixes
CREATE INDEX IF NOT EXISTS idx_soundscape_mixes_user
    ON soundscape_mixes(user_id);
CREATE INDEX IF NOT EXISTS idx_soundscape_mixes_user_recent
    ON soundscape_mixes(user_id, updated_at DESC);

-- RLS for soundscape_mixes
ALTER TABLE soundscape_mixes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'soundscape_mixes'
        AND policyname = 'Users can read own soundscape mixes'
    ) THEN
        CREATE POLICY "Users can read own soundscape mixes"
            ON soundscape_mixes FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'soundscape_mixes'
        AND policyname = 'Users can insert own soundscape mixes'
    ) THEN
        CREATE POLICY "Users can insert own soundscape mixes"
            ON soundscape_mixes FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'soundscape_mixes'
        AND policyname = 'Users can update own soundscape mixes'
    ) THEN
        CREATE POLICY "Users can update own soundscape mixes"
            ON soundscape_mixes FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'soundscape_mixes'
        AND policyname = 'Users can delete own soundscape mixes'
    ) THEN
        CREATE POLICY "Users can delete own soundscape mixes"
            ON soundscape_mixes FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- TRIGGER: Auto-update updated_at
-- =============================================================================

CREATE OR REPLACE FUNCTION update_soundscape_mixes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_soundscape_mixes_updated_at ON soundscape_mixes;
CREATE TRIGGER trigger_soundscape_mixes_updated_at
    BEFORE UPDATE ON soundscape_mixes
    FOR EACH ROW
    EXECUTE FUNCTION update_soundscape_mixes_updated_at();

-- =============================================================================
-- SEED DATA: Soundscape Sounds
-- =============================================================================

INSERT INTO soundscape_sounds (id, title, category, audio_url, icon_name, is_premium, sort_order)
VALUES
    -- Nature Sounds (7)
    (gen_random_uuid(), 'Rain', 'nature', 'https://storage.supabase.co/soundscapes/rain.m4a', 'cloud.rain.fill', false, 1),
    (gen_random_uuid(), 'Ocean Waves', 'nature', 'https://storage.supabase.co/soundscapes/ocean.m4a', 'water.waves', false, 2),
    (gen_random_uuid(), 'Forest', 'nature', 'https://storage.supabase.co/soundscapes/forest.m4a', 'leaf.fill', false, 3),
    (gen_random_uuid(), 'Thunder', 'nature', 'https://storage.supabase.co/soundscapes/thunder.m4a', 'cloud.bolt.fill', false, 4),
    (gen_random_uuid(), 'Birds', 'nature', 'https://storage.supabase.co/soundscapes/birds.m4a', 'bird.fill', false, 5),
    (gen_random_uuid(), 'Creek', 'nature', 'https://storage.supabase.co/soundscapes/creek.m4a', 'drop.fill', true, 6),
    (gen_random_uuid(), 'Wind', 'nature', 'https://storage.supabase.co/soundscapes/wind.m4a', 'wind', true, 7),

    -- Ambient (4)
    (gen_random_uuid(), 'Fireplace', 'ambient', 'https://storage.supabase.co/soundscapes/fire.m4a', 'flame.fill', false, 1),
    (gen_random_uuid(), 'Cafe', 'ambient', 'https://storage.supabase.co/soundscapes/cafe.m4a', 'cup.and.saucer.fill', false, 2),
    (gen_random_uuid(), 'Train', 'ambient', 'https://storage.supabase.co/soundscapes/train.m4a', 'tram.fill', false, 3),
    (gen_random_uuid(), 'Library', 'ambient', 'https://storage.supabase.co/soundscapes/library.m4a', 'books.vertical.fill', true, 4),

    -- White Noise (4)
    (gen_random_uuid(), 'White Noise', 'white_noise', 'https://storage.supabase.co/soundscapes/white.m4a', 'waveform', false, 1),
    (gen_random_uuid(), 'Pink Noise', 'white_noise', 'https://storage.supabase.co/soundscapes/pink.m4a', 'waveform', false, 2),
    (gen_random_uuid(), 'Brown Noise', 'white_noise', 'https://storage.supabase.co/soundscapes/brown.m4a', 'waveform', false, 3),
    (gen_random_uuid(), 'Fan', 'white_noise', 'https://storage.supabase.co/soundscapes/fan.m4a', 'fanblades.fill', false, 4),

    -- Binaural Beats (4) - All premium
    (gen_random_uuid(), 'Delta Waves (Deep Sleep)', 'binaural', 'https://storage.supabase.co/soundscapes/delta.m4a', 'headphones', true, 1),
    (gen_random_uuid(), 'Theta Waves (Meditation)', 'binaural', 'https://storage.supabase.co/soundscapes/theta.m4a', 'headphones', true, 2),
    (gen_random_uuid(), 'Alpha Waves (Relaxation)', 'binaural', 'https://storage.supabase.co/soundscapes/alpha.m4a', 'headphones', true, 3),
    (gen_random_uuid(), 'Beta Waves (Focus)', 'binaural', 'https://storage.supabase.co/soundscapes/beta.m4a', 'headphones', true, 4),

    -- Lo-fi (3) - All premium
    (gen_random_uuid(), 'Lo-fi Beats', 'lofi', 'https://storage.supabase.co/soundscapes/lofi-beats.m4a', 'music.note', true, 1),
    (gen_random_uuid(), 'Chill Hop', 'lofi', 'https://storage.supabase.co/soundscapes/chillhop.m4a', 'music.note', true, 2),
    (gen_random_uuid(), 'Jazz Loops', 'lofi', 'https://storage.supabase.co/soundscapes/jazz-loops.m4a', 'music.note', true, 3)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE soundscape_sounds IS 'Individual sounds that can be layered in the soundscape mixer';
COMMENT ON TABLE soundscape_mixes IS 'User-saved soundscape mix configurations with layer settings';
COMMENT ON COLUMN soundscape_sounds.category IS 'Sound category: binaural, nature, ambient, lofi, white_noise';
COMMENT ON COLUMN soundscape_sounds.duration_seconds IS 'Duration in seconds, NULL for infinite looping sounds';
COMMENT ON COLUMN soundscape_mixes.layers IS 'JSONB array of layer configs: [{sound_id, volume, pan}, ...]';
