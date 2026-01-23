-- Dynamic Content Generation Feature
-- AI-generated personalized content with TTS (ElevenLabs)
-- Tables: generated_content, gen_content_requests, gen_content_ratings, voice_preferences, gen_content_flags, gen_content_series
-- Functions: check_and_increment_content_quota

-- MARK: - Voice Preferences (User Settings)

CREATE TABLE IF NOT EXISTS voice_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Voice settings
    preferred_voice_id TEXT,        -- ElevenLabs voice ID
    preferred_pace NUMERIC(3,2) DEFAULT 1.0 CHECK (preferred_pace >= 0.5 AND preferred_pace <= 2.0),

    -- Background preferences
    preferred_backgrounds TEXT[] DEFAULT '{}',  -- ['rain', 'ocean', 'forest', 'silence']
    background_volume NUMERIC(3,2) DEFAULT 0.2 CHECK (background_volume >= 0 AND background_volume <= 1.0),

    -- Language & culture
    language TEXT DEFAULT 'en' CHECK (language ~ '^[a-z]{2}$'),
    cultural_context TEXT,          -- User's cultural background for content adaptation
    content_tone TEXT DEFAULT 'secular' CHECK (content_tone IN ('secular', 'spiritual', 'religious')),

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_voice_preferences_language ON voice_preferences(language);

-- MARK: - Generated Content Series (Multi-day Programs for AI-generated content)
-- Note: This is separate from content_series (creator content) in content_creators.sql

CREATE TABLE IF NOT EXISTS gen_content_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Series metadata
    title TEXT NOT NULL,
    theme TEXT NOT NULL,            -- 'work_stress', 'sleep_improvement', 'anxiety_management'
    description TEXT,

    -- Structure
    total_parts INTEGER NOT NULL CHECK (total_parts >= 1 AND total_parts <= 30),
    completed_parts INTEGER DEFAULT 0 CHECK (completed_parts >= 0),
    content_types TEXT[] DEFAULT '{}',  -- ['meditation', 'sleep_story', 'breathing']

    -- Status
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'abandoned')),

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    -- Constraint: completed_parts cannot exceed total_parts
    CONSTRAINT gen_series_valid_progress CHECK (completed_parts <= total_parts)
);

CREATE INDEX IF NOT EXISTS idx_gen_content_series_user ON gen_content_series(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gen_content_series_active ON gen_content_series(user_id, status) WHERE status = 'active';

-- MARK: - Generated Content (Main Content Table)

CREATE TABLE IF NOT EXISTS generated_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Content type
    content_type TEXT NOT NULL CHECK (content_type IN (
        'sleep_story', 'meditation', 'breathing', 'grounding',
        'mindfulness', 'cbt', 'journaling', 'affirmation'
    )),

    -- Request parameters (stored for regeneration/debugging)
    request_params JSONB NOT NULL DEFAULT '{}',

    -- Generated content
    title TEXT NOT NULL,
    text_content TEXT NOT NULL,     -- Generated script
    audio_url TEXT,                 -- Supabase Storage URL after TTS

    -- Audio metadata
    voice_id TEXT,                  -- ElevenLabs voice ID used
    background_sound TEXT,          -- 'rain', 'ocean', 'forest', 'silence'
    duration_seconds INTEGER,       -- Actual audio duration

    -- Quality & validation
    quality_score INTEGER CHECK (quality_score >= 1 AND quality_score <= 10),
    clinical_reviewed BOOLEAN DEFAULT FALSE,
    safety_flags TEXT[] DEFAULT '{}',

    -- Cost tracking
    generation_cost_usd NUMERIC(8,4) DEFAULT 0,

    -- Series relationship
    series_id UUID REFERENCES gen_content_series(id) ON DELETE SET NULL,
    series_position INTEGER,

    -- Status
    status TEXT DEFAULT 'generating' CHECK (status IN ('pending', 'generating', 'completed', 'failed')),
    error_message TEXT,

    -- Stats (denormalized)
    play_count INTEGER DEFAULT 0,
    average_rating NUMERIC(3,2),
    rating_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Constraints
    CONSTRAINT gen_content_valid_series_position CHECK (
        (series_id IS NULL AND series_position IS NULL) OR
        (series_id IS NOT NULL AND series_position IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_generated_content_user ON generated_content(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_generated_content_type ON generated_content(content_type);
CREATE INDEX IF NOT EXISTS idx_generated_content_status ON generated_content(status);
CREATE INDEX IF NOT EXISTS idx_generated_content_series ON generated_content(series_id, series_position);
CREATE INDEX IF NOT EXISTS idx_generated_content_clinical ON generated_content(clinical_reviewed) WHERE clinical_reviewed = false;

-- MARK: - Generation Requests (Request Tracking)

CREATE TABLE IF NOT EXISTS gen_content_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Request details
    content_type TEXT NOT NULL CHECK (content_type IN (
        'sleep_story', 'meditation', 'breathing', 'grounding',
        'mindfulness', 'cbt', 'journaling', 'affirmation'
    )),
    request_params JSONB NOT NULL,

    -- Status tracking
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    generated_content_id UUID REFERENCES generated_content(id) ON DELETE SET NULL,

    -- Error tracking
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,

    -- Performance metrics
    processing_time_ms INTEGER,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_gen_content_requests_user ON gen_content_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gen_content_requests_status ON gen_content_requests(status, created_at) WHERE status IN ('pending', 'processing');

-- MARK: - Generated Content Ratings (User Feedback)

CREATE TABLE IF NOT EXISTS gen_content_ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    generated_content_id UUID NOT NULL REFERENCES generated_content(id) ON DELETE CASCADE,

    -- Rating
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    helpful BOOLEAN,
    feedback_text TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Unique constraint: one rating per user per content
    UNIQUE(user_id, generated_content_id)
);

CREATE INDEX IF NOT EXISTS idx_gen_content_ratings_content ON gen_content_ratings(generated_content_id);
CREATE INDEX IF NOT EXISTS idx_gen_content_ratings_user ON gen_content_ratings(user_id, created_at DESC);

-- MARK: - Generated Content Flags (For Clinical Review)

CREATE TABLE IF NOT EXISTS gen_content_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generated_content_id UUID NOT NULL REFERENCES generated_content(id) ON DELETE CASCADE,

    -- Reporter (optional for anonymous flagging)
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Flag details
    reason TEXT NOT NULL CHECK (reason IN (
        'inappropriate', 'inaccurate', 'offensive', 'safety_concern', 'other'
    )),
    description TEXT,

    -- Review status
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
    reviewer_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gen_content_flags_content ON gen_content_flags(generated_content_id);
CREATE INDEX IF NOT EXISTS idx_gen_content_flags_status ON gen_content_flags(status, created_at) WHERE status = 'pending';

-- MARK: - Quota Function

CREATE OR REPLACE FUNCTION check_and_increment_content_quota(
    p_user_id UUID,
    p_is_premium BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
    allowed BOOLEAN,
    quota_used INT,
    quota_limit INT,
    was_reset BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_quota_used INT;
    v_quota_limit INT := 3;  -- Free tier: 3 generations per day
BEGIN
    -- Premium users: always allowed, no limit
    IF p_is_premium THEN
        -- Just count for analytics, no enforcement
        SELECT COUNT(*)::INT INTO v_quota_used
        FROM generated_content
        WHERE user_id = p_user_id
        AND DATE(created_at) = CURRENT_DATE
        AND status != 'failed';

        RETURN QUERY SELECT TRUE, v_quota_used, -1, FALSE;
        RETURN;
    END IF;

    -- Free users: count today's generations
    SELECT COUNT(*)::INT INTO v_quota_used
    FROM generated_content
    WHERE user_id = p_user_id
    AND DATE(created_at) = CURRENT_DATE
    AND status != 'failed';

    -- Check if user has already exceeded quota
    IF v_quota_used >= v_quota_limit THEN
        RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, FALSE;
        RETURN;
    END IF;

    -- Quota not exceeded, allow generation
    RETURN QUERY SELECT TRUE, v_quota_used, v_quota_limit, FALSE;
END;
$$;

COMMENT ON FUNCTION check_and_increment_content_quota IS 'Checks content generation quota. Free: 3/day, Premium: unlimited.';

-- MARK: - Triggers

-- Update generated_content stats when ratings change
CREATE OR REPLACE FUNCTION update_gen_content_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE generated_content SET
        average_rating = (
            SELECT AVG(rating)::NUMERIC(3,2)
            FROM gen_content_ratings
            WHERE generated_content_id = COALESCE(NEW.generated_content_id, OLD.generated_content_id)
        ),
        rating_count = (
            SELECT COUNT(*)
            FROM gen_content_ratings
            WHERE generated_content_id = COALESCE(NEW.generated_content_id, OLD.generated_content_id)
        ),
        updated_at = NOW()
    WHERE id = COALESCE(NEW.generated_content_id, OLD.generated_content_id);

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_gen_content_rating ON gen_content_ratings;
CREATE TRIGGER trigger_update_gen_content_rating
    AFTER INSERT OR UPDATE OR DELETE ON gen_content_ratings
    FOR EACH ROW
    EXECUTE FUNCTION update_gen_content_rating();

-- Update gen_content_series progress when content is completed
CREATE OR REPLACE FUNCTION update_gen_series_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only update if this content belongs to a series and status changed to completed
    IF NEW.series_id IS NOT NULL AND NEW.status = 'completed' AND OLD.status != 'completed' THEN
        UPDATE gen_content_series SET
            completed_parts = (
                SELECT COUNT(*)
                FROM generated_content
                WHERE series_id = NEW.series_id
                AND status = 'completed'
            ),
            status = CASE
                WHEN (SELECT COUNT(*) FROM generated_content WHERE series_id = NEW.series_id AND status = 'completed') >= total_parts
                THEN 'completed'
                ELSE status
            END,
            completed_at = CASE
                WHEN (SELECT COUNT(*) FROM generated_content WHERE series_id = NEW.series_id AND status = 'completed') >= total_parts
                THEN NOW()
                ELSE completed_at
            END,
            updated_at = NOW()
        WHERE id = NEW.series_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_gen_series_progress ON generated_content;
CREATE TRIGGER trigger_update_gen_series_progress
    AFTER UPDATE ON generated_content
    FOR EACH ROW
    EXECUTE FUNCTION update_gen_series_progress();

-- MARK: - Row Level Security

-- Voice preferences: users manage their own
ALTER TABLE voice_preferences ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own voice preferences' AND tablename = 'voice_preferences'
    ) THEN
        CREATE POLICY "Users manage own voice preferences" ON voice_preferences
            FOR ALL USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Generated content series: users manage their own
ALTER TABLE gen_content_series ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own gen content series' AND tablename = 'gen_content_series'
    ) THEN
        CREATE POLICY "Users manage own gen content series" ON gen_content_series
            FOR ALL USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Generated content: users manage their own
ALTER TABLE generated_content ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own generated content' AND tablename = 'generated_content'
    ) THEN
        CREATE POLICY "Users manage own generated content" ON generated_content
            FOR ALL USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Service role can insert generated content (for Edge Functions)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Service role can manage generated content' AND tablename = 'generated_content'
    ) THEN
        CREATE POLICY "Service role can manage generated content" ON generated_content
            FOR ALL USING (auth.role() = 'service_role');
    END IF;
END $$;

-- Content requests: users manage their own
ALTER TABLE gen_content_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own gen content requests' AND tablename = 'gen_content_requests'
    ) THEN
        CREATE POLICY "Users manage own gen content requests" ON gen_content_requests
            FOR ALL USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Content ratings: users manage their own
ALTER TABLE gen_content_ratings ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own gen content ratings' AND tablename = 'gen_content_ratings'
    ) THEN
        CREATE POLICY "Users manage own gen content ratings" ON gen_content_ratings
            FOR ALL USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Content flags: users can insert, only service role can read
ALTER TABLE gen_content_flags ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Users can flag gen content' AND tablename = 'gen_content_flags'
    ) THEN
        CREATE POLICY "Users can flag gen content" ON gen_content_flags
            FOR INSERT WITH CHECK (true);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Service role reads gen content flags' AND tablename = 'gen_content_flags'
    ) THEN
        CREATE POLICY "Service role reads gen content flags" ON gen_content_flags
            FOR SELECT USING (auth.role() = 'service_role');
    END IF;
END $$;

-- MARK: - Seed Voice Options

-- Insert default voice options (ElevenLabs voices)
-- These will be used as reference data for the voice picker
CREATE TABLE IF NOT EXISTS available_voices (
    id TEXT PRIMARY KEY,          -- ElevenLabs voice ID
    name TEXT NOT NULL,
    gender TEXT CHECK (gender IN ('male', 'female', 'neutral')),
    accent TEXT,                  -- 'american', 'british', 'australian', etc.
    style TEXT,                   -- 'calm', 'warm', 'energetic', 'whisper'
    language TEXT DEFAULT 'en',
    preview_url TEXT,
    is_premium BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for available_voices (public read)
ALTER TABLE available_voices ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can read available voices' AND tablename = 'available_voices'
    ) THEN
        CREATE POLICY "Anyone can read available voices" ON available_voices
            FOR SELECT USING (is_active = true);
    END IF;
END $$;

-- Seed ElevenLabs voices (IDs are examples - replace with actual IDs)
INSERT INTO available_voices (id, name, gender, accent, style, language, is_premium, is_active) VALUES
    ('EXAVITQu4vr4xnSDxMaL', 'Sarah', 'female', 'american', 'calm', 'en', false, true),
    ('TxGEqnHWrfWFTfGW9XjX', 'Josh', 'male', 'american', 'warm', 'en', false, true),
    ('pNInz6obpgDQGcFmaJgB', 'Adam', 'male', 'american', 'deep', 'en', false, true),
    ('21m00Tcm4TlvDq8ikWAM', 'Rachel', 'female', 'american', 'soothing', 'en', true, true),
    ('AZnzlk1XvdvUeBnXmlld', 'Domi', 'female', 'american', 'energetic', 'en', true, true),
    ('MF3mGyEYCl7XYWbV9V6O', 'Elli', 'female', 'american', 'whisper', 'en', true, true),
    ('VR6AewLTigWG4xSOukaG', 'Arnold', 'male', 'american', 'warm', 'en', true, true),
    ('pqHfZKP75CvOlQylNhV4', 'Bill', 'male', 'american', 'calm', 'en', true, true)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    gender = EXCLUDED.gender,
    accent = EXCLUDED.accent,
    style = EXCLUDED.style,
    is_premium = EXCLUDED.is_premium,
    is_active = EXCLUDED.is_active;

-- MARK: - Comments

COMMENT ON TABLE generated_content IS 'AI-generated personalized content (meditations, sleep stories, etc.)';
COMMENT ON TABLE gen_content_requests IS 'Tracks all content generation requests for analytics and debugging';
COMMENT ON TABLE gen_content_ratings IS 'User ratings and feedback for generated content';
COMMENT ON TABLE gen_content_flags IS 'Flagged content for clinical review';
COMMENT ON TABLE gen_content_series IS 'Multi-day AI-generated content programs (e.g., 7-day anxiety program)';
COMMENT ON TABLE voice_preferences IS 'User preferences for voice, pace, and content settings';
COMMENT ON TABLE available_voices IS 'Available ElevenLabs voices for content generation';
