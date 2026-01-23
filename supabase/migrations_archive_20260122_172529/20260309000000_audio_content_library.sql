-- Audio Content Library Feature
-- Tables: narrators, audio_tracks, audio_collections, playback_sessions, user_favorites, audio_ratings
-- RLS: Public read for tracks/narrators, user-scoped for personal data
-- Seed: Sample narrators and meditation tracks for testing

-- MARK: - Narrators (Voice Talent Profiles)

CREATE TABLE IF NOT EXISTS narrators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    voice_sample_url TEXT,

    -- Voice metadata
    voice_type TEXT CHECK (voice_type IN ('human', 'ai')),
    voice_gender TEXT CHECK (voice_gender IN ('male', 'female', 'neutral')),
    voice_style TEXT,  -- 'warm', 'soothing', 'energetic', 'calm'

    -- Status
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_narrators_active ON narrators(is_active) WHERE is_active = true;
CREATE INDEX idx_narrators_slug ON narrators(slug);

-- MARK: - Audio Tracks (Core Audio Content)

CREATE TABLE IF NOT EXISTS audio_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    title TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    description TEXT,

    -- Classification
    category TEXT NOT NULL CHECK (category IN (
        'meditation', 'sleep_story', 'sleep_meditation',
        'soundscape', 'breathing', 'music', 'course_lesson'
    )),
    subcategory TEXT,  -- 'body_scan', 'visualization', 'rain', etc.
    tags TEXT[] DEFAULT '{}',
    mood_tags TEXT[] DEFAULT '{}',  -- 'anxious', 'stressed', 'calm', 'tired', 'energetic'
    time_of_day_tags TEXT[] DEFAULT '{}',  -- 'morning', 'evening', 'night', 'anytime'

    -- Audio file
    audio_url TEXT NOT NULL,
    audio_duration_seconds INTEGER NOT NULL,
    audio_format TEXT DEFAULT 'mp3',  -- 'mp3', 'aac', 'm4a'
    audio_quality TEXT DEFAULT 'high',  -- 'standard', 'high', 'lossless'
    file_size_bytes BIGINT,

    -- Preview
    preview_url TEXT,
    preview_duration_seconds INTEGER DEFAULT 30,

    -- Artwork
    cover_image_url TEXT,
    background_image_url TEXT,  -- For player UI
    color_scheme JSONB,  -- {"primary": "#hex", "secondary": "#hex"}

    -- Narrator/Creator
    narrator_id UUID REFERENCES narrators(id),
    creator_type TEXT DEFAULT 'professional' CHECK (creator_type IN (
        'professional', 'community', 'ai_generated'
    )),

    -- Metadata
    language TEXT DEFAULT 'en',
    is_loopable BOOLEAN DEFAULT false,
    has_background_music BOOLEAN DEFAULT false,
    energy_level TEXT CHECK (energy_level IN ('calming', 'neutral', 'energizing')),

    -- Access
    is_premium BOOLEAN DEFAULT false,
    is_featured BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    released_at TIMESTAMPTZ DEFAULT NOW(),

    -- Course relationship
    course_id UUID,  -- Will add constraint after audio_courses table
    course_order INTEGER,

    -- Stats (denormalized for performance)
    play_count INTEGER DEFAULT 0,
    completion_count INTEGER DEFAULT 0,
    average_rating NUMERIC(3,2),
    rating_count INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audio_tracks_category ON audio_tracks(category);
CREATE INDEX idx_audio_tracks_tags ON audio_tracks USING GIN (tags);
CREATE INDEX idx_audio_tracks_duration ON audio_tracks(audio_duration_seconds);
CREATE INDEX idx_audio_tracks_featured ON audio_tracks(is_featured) WHERE is_featured = true;
CREATE INDEX idx_audio_tracks_active ON audio_tracks(is_active) WHERE is_active = true;
CREATE INDEX idx_audio_tracks_narrator ON audio_tracks(narrator_id);

-- MARK: - Audio Collections (Curated Playlists)

CREATE TABLE IF NOT EXISTS audio_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    title TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    description TEXT,

    -- Metadata
    category TEXT NOT NULL,
    difficulty TEXT CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),

    -- Content
    track_ids UUID[] DEFAULT '{}',
    total_tracks INTEGER DEFAULT 0,
    total_duration_seconds INTEGER,

    -- Artwork
    cover_image_url TEXT,

    -- Access
    is_premium BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,

    -- Sort/Order
    sort_order INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audio_collections_category ON audio_collections(category);
CREATE INDEX idx_audio_collections_active ON audio_collections(is_active) WHERE is_active = true;
CREATE INDEX idx_audio_collections_featured ON audio_collections(is_featured) WHERE is_featured = true;

-- MARK: - User Playback Sessions (Analytics)

CREATE TABLE IF NOT EXISTS playback_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES audio_tracks(id) ON DELETE CASCADE,

    -- Playback details
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_played_seconds INTEGER,
    completed BOOLEAN DEFAULT false,

    -- Position tracking
    last_position_seconds INTEGER DEFAULT 0,

    -- Context
    source TEXT,  -- 'browse', 'search', 'recommendation', 'collection', 'quest'
    context_id TEXT,  -- quest_id, collection_id, etc.

    -- Quality signals
    skipped BOOLEAN DEFAULT false,
    skip_position_seconds INTEGER,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_playback_sessions_user ON playback_sessions(user_id, created_at DESC);
CREATE INDEX idx_playback_sessions_track ON playback_sessions(track_id);
CREATE INDEX idx_playback_sessions_completed ON playback_sessions(completed) WHERE completed = true;

-- MARK: - User Favorites

CREATE TABLE IF NOT EXISTS user_audio_favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES audio_tracks(id) ON DELETE CASCADE,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, track_id)
);

CREATE INDEX idx_user_audio_favorites_user ON user_audio_favorites(user_id);

-- MARK: - User Ratings

CREATE TABLE IF NOT EXISTS audio_ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES audio_tracks(id) ON DELETE CASCADE,

    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review_text TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, track_id)
);

CREATE INDEX idx_audio_ratings_track ON audio_ratings(track_id);

-- MARK: - User Downloads (Offline Access Tracking)

CREATE TABLE IF NOT EXISTS user_audio_downloads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES audio_tracks(id) ON DELETE CASCADE,

    downloaded_at TIMESTAMPTZ DEFAULT NOW(),
    file_size_bytes BIGINT,
    local_path TEXT,  -- For cleanup tracking

    UNIQUE(user_id, track_id)
);

CREATE INDEX idx_user_audio_downloads_user ON user_audio_downloads(user_id);

-- MARK: - Row Level Security (RLS)

-- Audio tracks: public read for active content
ALTER TABLE audio_tracks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read active audio tracks" ON audio_tracks
    FOR SELECT USING (is_active = true);

-- Narrators: public read for active narrators
ALTER TABLE narrators ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read active narrators" ON narrators
    FOR SELECT USING (is_active = true);

-- Audio collections: public read for active collections
ALTER TABLE audio_collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read active audio collections" ON audio_collections
    FOR SELECT USING (is_active = true);

-- Playback sessions: users can read/write their own
ALTER TABLE playback_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own playback sessions" ON playback_sessions
    FOR ALL USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- User favorites: users can read/write their own
ALTER TABLE user_audio_favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own audio favorites" ON user_audio_favorites
    FOR ALL USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Audio ratings: users can read/write their own
ALTER TABLE audio_ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own audio ratings" ON audio_ratings
    FOR ALL USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- User downloads: users can read/write their own
ALTER TABLE user_audio_downloads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own audio downloads" ON user_audio_downloads
    FOR ALL USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- MARK: - Triggers

-- Function to update track stats after playback
CREATE OR REPLACE FUNCTION update_audio_track_stats()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE audio_tracks SET
        play_count = play_count + 1,
        completion_count = completion_count + CASE WHEN NEW.completed THEN 1 ELSE 0 END,
        updated_at = NOW()
    WHERE id = NEW.track_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_audio_track_stats ON playback_sessions;
CREATE TRIGGER trigger_update_audio_track_stats
    AFTER INSERT ON playback_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_audio_track_stats();

-- Function to update average rating
CREATE OR REPLACE FUNCTION update_audio_track_rating()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE audio_tracks SET
        average_rating = (
            SELECT AVG(rating)::NUMERIC(3,2)
            FROM audio_ratings
            WHERE track_id = COALESCE(NEW.track_id, OLD.track_id)
        ),
        rating_count = (
            SELECT COUNT(*)
            FROM audio_ratings
            WHERE track_id = COALESCE(NEW.track_id, OLD.track_id)
        ),
        updated_at = NOW()
    WHERE id = COALESCE(NEW.track_id, OLD.track_id);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_audio_track_rating ON audio_ratings;
CREATE TRIGGER trigger_update_audio_track_rating
    AFTER INSERT OR UPDATE OR DELETE ON audio_ratings
    FOR EACH ROW
    EXECUTE FUNCTION update_audio_track_rating();

-- MARK: - Seed Data (Sample Content for Testing)

-- Insert sample narrators
INSERT INTO narrators (name, slug, bio, voice_type, voice_gender, voice_style, is_active) VALUES
    ('Sarah', 'sarah', 'Calming meditation guide with 10+ years experience', 'human', 'female', 'soothing', true),
    ('James', 'james', 'Deep voice for sleep stories and soundscapes', 'human', 'male', 'warm', true),
    ('Luna', 'luna', 'AI-generated voice for ambient soundscapes', 'ai', 'female', 'neutral', true)
ON CONFLICT (slug) DO NOTHING;

-- Get narrator IDs for use below
DO $$
DECLARE
    sarah_id UUID;
    james_id UUID;
BEGIN
    SELECT id INTO sarah_id FROM narrators WHERE slug = 'sarah';
    SELECT id INTO james_id FROM narrators WHERE slug = 'james';

    -- Insert sample meditation tracks
    INSERT INTO audio_tracks (
        title, slug, description, category, subcategory, tags,
        mood_tags, time_of_day_tags, audio_url, audio_duration_seconds,
        audio_format, audio_quality, cover_image_url, narrator_id,
        creator_type, language, is_loopable, energy_level,
        is_premium, is_featured, is_active
    ) VALUES
        (
            'Morning Intention', 'morning-intention-5min',
            'Start your day with purpose and calm intention setting',
            'meditation', 'mindfulness',
            ARRAY['beginner', 'morning', 'intentions'],
            ARRAY['energetic'],
            ARRAY['morning'],
            'https://example.com/audio/morning-intention.m4a', 300,
            'm4a', 'high',
            'https://example.com/covers/morning-intention.jpg',
            sarah_id,
            'professional', 'en', false, 'energizing',
            false, true, true
        ),
        (
            'Evening Wind-Down', 'evening-winddown-10min',
            'Prepare for restful sleep with this gentle evening practice',
            'meditation', 'body_scan',
            ARRAY['beginner', 'evening', 'relaxation'],
            ARRAY['calm'],
            ARRAY['evening', 'night'],
            'https://example.com/audio/evening-winddown.m4a', 600,
            'm4a', 'high',
            'https://example.com/covers/evening-winddown.jpg',
            sarah_id,
            'professional', 'en', false, 'calming',
            false, true, true
        ),
        (
            'Sleep Story: The Garden', 'sleep-story-garden-25min',
            'Drift off to a soothing story of a magical garden',
            'sleep_story', NULL,
            ARRAY['sleep', 'story', 'peaceful'],
            ARRAY['calm', 'tired'],
            ARRAY['night'],
            'https://example.com/audio/sleep-story-garden.m4a', 1500,
            'm4a', 'high',
            'https://example.com/covers/sleep-story-garden.jpg',
            james_id,
            'professional', 'en', false, 'calming',
            false, true, true
        ),
        (
            'Rain Sounds', 'soundscape-rain-looping',
            'Ambient rain sounds for focus and relaxation',
            'soundscape', 'nature',
            ARRAY['ambient', 'nature', 'focus'],
            ARRAY['calm', 'neutral'],
            ARRAY['anytime'],
            'https://example.com/audio/rain-sounds.m4a', 3600,
            'm4a', 'high',
            'https://example.com/covers/rain-sounds.jpg',
            NULL,
            'professional', 'en', true, 'calming',
            false, false, true
        ),
        (
            'Box Breathing', 'breathing-box-5min',
            'Classic 4-4-4-4 breathing pattern for calm focus',
            'breathing', 'guided',
            ARRAY['beginner', 'breathing', 'anxiety'],
            ARRAY['anxious', 'stressed'],
            ARRAY['anytime'],
            'https://example.com/audio/box-breathing.m4a', 300,
            'm4a', 'high',
            'https://example.com/covers/box-breathing.jpg',
            sarah_id,
            'professional', 'en', false, 'calming',
            false, false, true
        )
    ON CONFLICT (slug) DO NOTHING;
END $$;

-- Insert sample collection
DO $$
DECLARE
    track_ids UUID[];
BEGIN
    SELECT ARRAY_AGG(id) INTO track_ids FROM audio_tracks
    WHERE slug IN ('morning-intention-5min', 'evening-winddown-10min')
    LIMIT 2;

    INSERT INTO audio_collections (
        title, slug, description, category, difficulty,
        track_ids, total_duration_seconds, cover_image_url,
        is_premium, is_featured, is_active, sort_order
    ) VALUES
        (
            'Daily Wellness Ritual', 'daily-wellness-ritual',
            'Start your morning and end your evening with these essentials',
            'meditation', 'beginner',
            track_ids, 900,
            'https://example.com/covers/daily-wellness.jpg',
            false, true, true, 1
        )
    ON CONFLICT (slug) DO NOTHING;
END $$;

-- MARK: - Seed data complete
