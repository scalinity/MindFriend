-- Creative Expression Feature Migration
-- Enables AI art generation, voice journaling, drawing canvas, and creative gallery

-- ============================================================================
-- TABLES
-- ============================================================================

-- Creative works gallery (stores all user creations)
CREATE TABLE IF NOT EXISTS creative_works (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    work_type TEXT NOT NULL CHECK (work_type IN ('ai_art', 'drawing', 'voice_journal', 'collage')),

    -- Content references
    title TEXT,
    description TEXT,
    storage_path TEXT, -- Supabase storage path for media

    -- AI Art specific
    generation_prompt TEXT,
    art_style TEXT,
    generation_model TEXT,
    generation_params JSONB,

    -- Voice Journal specific
    duration_seconds INTEGER,
    transcription TEXT,
    transcription_status TEXT CHECK (transcription_status IN ('pending', 'processing', 'completed', 'failed')),

    -- Drawing specific
    canvas_data JSONB, -- Serialized drawing data for replay

    -- Emotional context
    mood_score INTEGER CHECK (mood_score BETWEEN 1 AND 10),
    mood_tags TEXT[],
    emotions_detected JSONB, -- AI-detected emotions

    -- Metadata
    is_favorite BOOLEAN NOT NULL DEFAULT false,
    is_shared_to_circle BOOLEAN NOT NULL DEFAULT false,
    circle_post_id UUID REFERENCES circle_posts(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Voice journal analysis
CREATE TABLE IF NOT EXISTS voice_journal_analysis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creative_work_id UUID NOT NULL REFERENCES creative_works(id) ON DELETE CASCADE,

    -- Transcription
    full_transcription TEXT,
    word_timestamps JSONB, -- [{word, start_ms, end_ms}]

    -- Emotion analysis
    overall_sentiment DECIMAL(3,2) CHECK (overall_sentiment BETWEEN -1 AND 1),
    emotions JSONB, -- {joy: 0.3, sadness: 0.1, ...}
    tone_analysis JSONB, -- {energy: 'low', pace: 'slow', ...}

    -- Content analysis
    key_themes TEXT[],
    key_quotes TEXT[],
    ai_summary TEXT,
    reflection_prompts TEXT[],

    -- Processing metadata
    analysis_model TEXT,
    processed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- AI art generation history
CREATE TABLE IF NOT EXISTS ai_art_generations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    creative_work_id UUID REFERENCES creative_works(id) ON DELETE SET NULL,

    -- Request
    user_prompt TEXT NOT NULL,
    enhanced_prompt TEXT, -- AI-enhanced version
    style_preset TEXT,
    negative_prompt TEXT,

    -- Generation
    model_used TEXT NOT NULL,
    generation_params JSONB,
    seed INTEGER,

    -- Result
    image_url TEXT,
    storage_path TEXT,
    generation_status TEXT NOT NULL CHECK (generation_status IN ('pending', 'processing', 'completed', 'failed')),
    error_message TEXT,

    -- Quota tracking
    is_premium_generation BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Drawing sessions
CREATE TABLE IF NOT EXISTS drawing_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    creative_work_id UUID REFERENCES creative_works(id) ON DELETE SET NULL,

    -- Canvas settings
    canvas_width INTEGER NOT NULL,
    canvas_height INTEGER NOT NULL,
    background_color TEXT,

    -- Strokes data
    strokes JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Session metadata
    duration_seconds INTEGER,
    stroke_count INTEGER,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Creative exercises/prompts
CREATE TABLE IF NOT EXISTS creative_exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    title TEXT NOT NULL,
    description TEXT NOT NULL,
    instructions TEXT NOT NULL,
    exercise_type TEXT NOT NULL CHECK (exercise_type IN ('drawing', 'collage', 'voice', 'ai_art', 'mixed')),

    -- Categorization
    category TEXT NOT NULL CHECK (category IN ('emotion_processing', 'gratitude', 'self_discovery', 'stress_relief')),
    difficulty TEXT NOT NULL DEFAULT 'beginner' CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
    estimated_minutes INTEGER NOT NULL,

    -- Content
    prompt_image_url TEXT,
    example_works JSONB, -- Array of example work URLs

    -- Availability
    is_premium BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User exercise completions
CREATE TABLE IF NOT EXISTS creative_exercise_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES creative_exercises(id) ON DELETE CASCADE,
    creative_work_id UUID REFERENCES creative_works(id) ON DELETE SET NULL,

    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    -- Reflection
    user_reflection TEXT,
    mood_before INTEGER CHECK (mood_before BETWEEN 1 AND 10),
    mood_after INTEGER CHECK (mood_after BETWEEN 1 AND 10),

    CONSTRAINT unique_exercise_attempt UNIQUE (user_id, exercise_id, started_at)
);

-- Music mood connections (for future Spotify integration)
CREATE TABLE IF NOT EXISTS music_mood_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    mood_id UUID REFERENCES moods(id) ON DELETE SET NULL,
    creative_work_id UUID REFERENCES creative_works(id) ON DELETE SET NULL,

    -- Track info (stored locally, not Spotify data)
    track_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    album_name TEXT,
    spotify_uri TEXT,
    apple_music_id TEXT,

    -- User context
    reason TEXT, -- Why this song for this mood

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Daily creative quota tracking
CREATE TABLE IF NOT EXISTS creative_quota_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,

    ai_art_count INTEGER NOT NULL DEFAULT 0,
    voice_minutes_used INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT unique_daily_quota UNIQUE (user_id, date)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_creative_works_user ON creative_works(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_creative_works_type ON creative_works(user_id, work_type);
CREATE INDEX IF NOT EXISTS idx_creative_works_mood ON creative_works(user_id, mood_score);
CREATE INDEX IF NOT EXISTS idx_creative_works_favorite ON creative_works(user_id) WHERE is_favorite = true;
CREATE INDEX IF NOT EXISTS idx_ai_generations_user ON ai_art_generations(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_generations_status ON ai_art_generations(generation_status) WHERE generation_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_voice_analysis_work ON voice_journal_analysis(creative_work_id);
CREATE INDEX IF NOT EXISTS idx_exercise_completions_user ON creative_exercise_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_creative_exercises_category ON creative_exercises(category) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_music_mood_user ON music_mood_entries(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_creative_quota_lookup ON creative_quota_usage(user_id, date);
CREATE INDEX IF NOT EXISTS idx_drawing_sessions_user ON drawing_sessions(user_id, created_at DESC);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE creative_works ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_journal_analysis ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_art_generations ENABLE ROW LEVEL SECURITY;
ALTER TABLE drawing_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE creative_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE creative_exercise_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE music_mood_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE creative_quota_usage ENABLE ROW LEVEL SECURITY;

-- Creative works: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_manage_own_creative_works' AND tablename = 'creative_works') THEN
        CREATE POLICY users_manage_own_creative_works ON creative_works FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Voice analysis: users read their own via creative_works ownership
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_read_own_voice_analysis' AND tablename = 'voice_journal_analysis') THEN
        CREATE POLICY users_read_own_voice_analysis ON voice_journal_analysis FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM creative_works
                WHERE creative_works.id = voice_journal_analysis.creative_work_id
                AND creative_works.user_id = auth.uid()
            )
        );
    END IF;
END $$;

-- Service role can insert voice analysis
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'service_insert_voice_analysis' AND tablename = 'voice_journal_analysis') THEN
        CREATE POLICY service_insert_voice_analysis ON voice_journal_analysis FOR INSERT
        WITH CHECK (true); -- Service role bypasses RLS anyway
    END IF;
END $$;

-- AI generations: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_manage_own_ai_generations' AND tablename = 'ai_art_generations') THEN
        CREATE POLICY users_manage_own_ai_generations ON ai_art_generations FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Drawing sessions: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_manage_own_drawing_sessions' AND tablename = 'drawing_sessions') THEN
        CREATE POLICY users_manage_own_drawing_sessions ON drawing_sessions FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Exercises: all authenticated users can read active exercises
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'all_users_read_exercises' AND tablename = 'creative_exercises') THEN
        CREATE POLICY all_users_read_exercises ON creative_exercises FOR SELECT USING (is_active = true);
    END IF;
END $$;

-- Exercise completions: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_manage_own_exercise_completions' AND tablename = 'creative_exercise_completions') THEN
        CREATE POLICY users_manage_own_exercise_completions ON creative_exercise_completions FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Music entries: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_manage_own_music_entries' AND tablename = 'music_mood_entries') THEN
        CREATE POLICY users_manage_own_music_entries ON music_mood_entries FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Quota usage: users manage their own
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'users_manage_own_quota_usage' AND tablename = 'creative_quota_usage') THEN
        CREATE POLICY users_manage_own_quota_usage ON creative_quota_usage FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at for creative_works
CREATE OR REPLACE FUNCTION update_creative_works_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_creative_works_updated_at ON creative_works;
CREATE TRIGGER trigger_update_creative_works_updated_at
    BEFORE UPDATE ON creative_works
    FOR EACH ROW
    EXECUTE FUNCTION update_creative_works_updated_at();

-- Auto-update updated_at for drawing_sessions
DROP TRIGGER IF EXISTS trigger_update_drawing_sessions_updated_at ON drawing_sessions;
CREATE TRIGGER trigger_update_drawing_sessions_updated_at
    BEFORE UPDATE ON drawing_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_creative_works_updated_at();

-- ============================================================================
-- SEED DATA: Creative Exercises
-- ============================================================================

INSERT INTO creative_exercises (id, title, description, instructions, exercise_type, category, difficulty, estimated_minutes, is_premium)
VALUES
    -- Emotion Processing
    (gen_random_uuid(), 'Draw Your Emotion',
     'Express your current emotional state through freeform drawing',
     'Close your eyes and take three deep breaths. Think about how you''re feeling right now. Open your eyes and let your hand move freely across the canvas. Use colors and shapes that represent your emotions. Don''t worry about making it look "good" - just express yourself.',
     'drawing', 'emotion_processing', 'beginner', 10, false),

    (gen_random_uuid(), 'Before & After Sketch',
     'Draw how you feel now and how you want to feel',
     'Divide your canvas into two sections. On the left, draw a simple representation of your current emotional state. On the right, draw how you''d like to feel. Reflect on what might help you move from left to right.',
     'drawing', 'emotion_processing', 'beginner', 15, false),

    (gen_random_uuid(), 'Emotion Color Wheel',
     'Create a personalized color map of your emotions',
     'Draw a large circle and divide it into 8 sections. Label each section with an emotion (joy, sadness, anger, fear, surprise, disgust, anticipation, trust). Fill each section with colors that represent that emotion to you.',
     'drawing', 'emotion_processing', 'intermediate', 20, false),

    (gen_random_uuid(), 'AI Art Reflection',
     'Generate art that represents your feelings and reflect on it',
     'Describe your current emotional state to the AI art generator. Choose a style that resonates with you. Once generated, spend time looking at the artwork. What do you notice? What emotions does it evoke?',
     'ai_art', 'emotion_processing', 'beginner', 10, false),

    -- Gratitude
    (gen_random_uuid(), 'Gratitude Collage',
     'Create a visual collection of things you''re thankful for',
     'Think of 5-7 things you''re grateful for today. Draw simple representations of each one on your canvas. They can be objects, people, moments, or abstract concepts. Add colors that represent the positive feelings these bring you.',
     'drawing', 'gratitude', 'beginner', 15, false),

    (gen_random_uuid(), 'Voice Gratitude Journal',
     'Record your gratitude aloud and hear it back',
     'Find a quiet space. Press record and speak about three things you''re grateful for today. For each one, explain why it matters to you. Listen back to your recording and notice how it feels to hear your own gratitude.',
     'voice', 'gratitude', 'beginner', 5, false),

    (gen_random_uuid(), 'Beautiful Moment Art',
     'Generate AI art of a moment you''re grateful for',
     'Think of a beautiful moment from the past week. Describe this moment to the AI art generator, including the setting, colors, and feelings. Let the AI create a visual memory you can return to.',
     'ai_art', 'gratitude', 'beginner', 10, true),

    -- Self Discovery
    (gen_random_uuid(), 'Inner Landscape',
     'Draw your internal emotional landscape as a physical place',
     'Imagine your inner world as a landscape. What terrain does it have? Mountains of strength? Rivers of emotion? Forests of creativity? Draw this inner landscape, adding details that represent different aspects of yourself.',
     'drawing', 'self_discovery', 'intermediate', 20, false),

    (gen_random_uuid(), 'Voice Letter to Self',
     'Record a compassionate message to yourself',
     'Record a voice message to yourself as if you were talking to a dear friend. What would you want yourself to know? What encouragement would you give? Speak with kindness and understanding.',
     'voice', 'self_discovery', 'intermediate', 10, false),

    (gen_random_uuid(), 'Future Self Portrait',
     'Generate AI art of your aspirational self',
     'Describe the best version of yourself - the person you''re growing into. What qualities do they embody? What surrounds them? Generate AI art that represents this future you.',
     'ai_art', 'self_discovery', 'intermediate', 15, true),

    -- Stress Relief
    (gen_random_uuid(), 'Calming Doodles',
     'Let your hand wander freely to release tension',
     'Start drawing continuous lines without lifting your pencil. Let your hand move naturally - spirals, loops, zigzags, whatever feels good. Focus on the movement, not the result. Breathe deeply as you draw.',
     'drawing', 'stress_relief', 'beginner', 10, false),

    (gen_random_uuid(), 'Worry Jar Visualization',
     'Draw your worries being contained',
     'Draw a large jar in the center of your canvas. Write or draw your current worries as small objects going into the jar. Draw a lid on the jar. Notice how it feels to see your worries contained.',
     'drawing', 'stress_relief', 'beginner', 10, false),

    (gen_random_uuid(), 'Peaceful Place Art',
     'Generate AI art of your ideal peaceful place',
     'Describe your perfect calming environment to the AI art generator. Is it a beach at sunset? A cozy cabin? A floating cloud? Be specific about colors, lighting, and atmosphere. Save this image to return to when you need calm.',
     'ai_art', 'stress_relief', 'beginner', 10, false),

    (gen_random_uuid(), 'Voice Release',
     'Speak your stress out loud and let it go',
     'Press record and speak about what''s causing you stress. Don''t censor yourself - let it all out. Then take a deep breath and describe three things you''re in control of. End with a statement of self-compassion.',
     'voice', 'stress_relief', 'beginner', 5, false),

    (gen_random_uuid(), 'Mandala Meditation',
     'Draw a symmetrical pattern for mindful focus',
     'Start with a small circle in the center of your canvas. Add patterns around it in layers, keeping things roughly symmetrical. Focus on each small section as you draw it. The repetitive patterns help calm the mind.',
     'drawing', 'stress_relief', 'intermediate', 20, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- STORAGE BUCKET
-- ============================================================================

-- Create the creative-works storage bucket (if not exists, handled by Supabase)
-- This needs to be done via Supabase Dashboard or separate script:
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('creative-works', 'creative-works', true)
-- ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Get user's creative quota for today
CREATE OR REPLACE FUNCTION get_creative_quota()
RETURNS TABLE(
    ai_art_count INTEGER,
    ai_art_limit INTEGER,
    voice_minutes_used INTEGER,
    voice_minutes_limit INTEGER,
    is_premium BOOLEAN
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_premium BOOLEAN;
    v_today DATE := CURRENT_DATE;
BEGIN
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    -- Get or create today's quota
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 0, 0)
    ON CONFLICT (user_id, date) DO NOTHING;

    -- Return quota info
    RETURN QUERY
    SELECT
        cqu.ai_art_count,
        CASE WHEN v_is_premium THEN 20 ELSE 3 END AS ai_art_limit,
        cqu.voice_minutes_used,
        CASE WHEN v_is_premium THEN 60 ELSE 5 END AS voice_minutes_limit,
        v_is_premium
    FROM creative_quota_usage cqu
    WHERE cqu.user_id = v_user_id AND cqu.date = v_today;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment AI art quota
CREATE OR REPLACE FUNCTION increment_ai_art_quota()
RETURNS TABLE(
    new_count INTEGER,
    limit_reached BOOLEAN,
    ai_art_limit INTEGER
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_is_premium BOOLEAN;
    v_limit INTEGER;
    v_new_count INTEGER;
BEGIN
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    v_limit := CASE WHEN v_is_premium THEN 20 ELSE 3 END;

    -- Upsert and increment
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 1, 0)
    ON CONFLICT (user_id, date)
    DO UPDATE SET ai_art_count = creative_quota_usage.ai_art_count + 1
    RETURNING creative_quota_usage.ai_art_count INTO v_new_count;

    RETURN QUERY
    SELECT
        v_new_count,
        v_new_count >= v_limit,
        v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment voice minutes quota
CREATE OR REPLACE FUNCTION increment_voice_quota(p_minutes INTEGER)
RETURNS TABLE(
    new_minutes INTEGER,
    limit_reached BOOLEAN,
    voice_limit INTEGER
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_today DATE := CURRENT_DATE;
    v_is_premium BOOLEAN;
    v_limit INTEGER;
    v_new_minutes INTEGER;
BEGIN
    -- Check if user is premium
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = v_user_id
        AND status = 'active'
    ) INTO v_is_premium;

    v_limit := CASE WHEN v_is_premium THEN 60 ELSE 5 END;

    -- Upsert and increment
    INSERT INTO creative_quota_usage (user_id, date, ai_art_count, voice_minutes_used)
    VALUES (v_user_id, v_today, 0, p_minutes)
    ON CONFLICT (user_id, date)
    DO UPDATE SET voice_minutes_used = creative_quota_usage.voice_minutes_used + p_minutes
    RETURNING creative_quota_usage.voice_minutes_used INTO v_new_minutes;

    RETURN QUERY
    SELECT
        v_new_minutes,
        v_new_minutes >= v_limit,
        v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get creative gallery with pagination
CREATE OR REPLACE FUNCTION get_creative_gallery(
    p_work_type TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS SETOF creative_works AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM creative_works
    WHERE user_id = auth.uid()
    AND (p_work_type IS NULL OR work_type = p_work_type)
    ORDER BY created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Toggle favorite status
CREATE OR REPLACE FUNCTION toggle_creative_work_favorite(p_work_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_new_status BOOLEAN;
BEGIN
    UPDATE creative_works
    SET is_favorite = NOT is_favorite
    WHERE id = p_work_id AND user_id = auth.uid()
    RETURNING is_favorite INTO v_new_status;

    RETURN v_new_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Delete creative work and associated files
CREATE OR REPLACE FUNCTION delete_creative_work(p_work_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_storage_path TEXT;
BEGIN
    -- Get storage path before deletion
    SELECT storage_path INTO v_storage_path
    FROM creative_works
    WHERE id = p_work_id AND user_id = auth.uid();

    IF v_storage_path IS NULL THEN
        RETURN false;
    END IF;

    -- Delete from database (cascades to related tables)
    DELETE FROM creative_works WHERE id = p_work_id AND user_id = auth.uid();

    -- Note: Storage deletion should be handled by Edge Function or client

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_creative_quota() TO authenticated;
GRANT EXECUTE ON FUNCTION increment_ai_art_quota() TO authenticated;
GRANT EXECUTE ON FUNCTION increment_voice_quota(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_creative_gallery(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_creative_work_favorite(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_creative_work(UUID) TO authenticated;
