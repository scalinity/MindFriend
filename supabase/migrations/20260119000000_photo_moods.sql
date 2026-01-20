-- Photo Moods Feature Migration
-- Created: 2026-01-19
-- Purpose: Enable photo-based mood logging with privacy controls

-- ============================================================================
-- TABLE: photo_moods
-- ============================================================================

CREATE TABLE IF NOT EXISTS photo_moods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Mood data (required)
    mood_score INTEGER NOT NULL CHECK (mood_score BETWEEN 1 AND 5),

    -- Optional metadata
    caption TEXT CHECK (caption IS NULL OR LENGTH(caption) <= 500),
    emotion_tags TEXT[], -- Max 5 emotions (client-side validation)
    location_name TEXT CHECK (location_name IS NULL OR LENGTH(location_name) <= 100),

    -- Photo storage references
    photo_storage_path TEXT NOT NULL, -- {user_id}/{timestamp}.jpg
    photo_thumbnail_path TEXT, -- {user_id}/thumb_{timestamp}.jpg

    -- AI analysis (future, nullable)
    ai_mood_suggestion INTEGER CHECK (ai_mood_suggestion IS NULL OR ai_mood_suggestion BETWEEN 1 AND 5),
    ai_emotions_detected TEXT[],
    ai_analyzed_at TIMESTAMPTZ,

    -- Sharing (future, nullable)
    shared_to_circle_id UUID REFERENCES circles(id) ON DELETE SET NULL,

    -- Timestamps
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Primary query pattern: user's photos sorted by date
CREATE INDEX IF NOT EXISTS idx_photo_moods_user_date
    ON photo_moods(user_id, logged_at DESC);

-- Composite index for filtered pagination (covers both filtered and unfiltered queries)
CREATE INDEX IF NOT EXISTS idx_photo_moods_user_mood_date
    ON photo_moods(user_id, mood_score, logged_at DESC);

-- Circle sharing (future)
CREATE INDEX IF NOT EXISTS idx_photo_moods_shared
    ON photo_moods(shared_to_circle_id)
    WHERE shared_to_circle_id IS NOT NULL;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE photo_moods ENABLE ROW LEVEL SECURITY;

-- Users can manage their own photo moods (SELECT, INSERT, UPDATE, DELETE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'photo_moods'
        AND policyname = 'Users manage own photo moods'
    ) THEN
        CREATE POLICY "Users manage own photo moods"
            ON photo_moods FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Circle members can view shared photo moods (future feature)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'photo_moods'
        AND policyname = 'Circle members can view shared'
    ) THEN
        CREATE POLICY "Circle members can view shared"
            ON photo_moods FOR SELECT
            USING (
                shared_to_circle_id IS NOT NULL AND
                shared_to_circle_id IN (
                    SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- ============================================================================
-- STORAGE BUCKET: mood-photos
-- ============================================================================

-- Create bucket for mood photos (private, user-owned folders)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'mood-photos',
    'mood-photos',
    false, -- Private bucket (signed URLs only)
    5242880, -- 5MB file size limit
    ARRAY['image/jpeg', 'image/png', 'image/heic']
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STORAGE RLS POLICIES
-- ============================================================================

-- Users can upload photos to their own folder ({user_id}/*)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Users can upload own photos'
    ) THEN
        CREATE POLICY "Users can upload own photos"
            ON storage.objects FOR INSERT
            WITH CHECK (
                bucket_id = 'mood-photos' AND
                auth.uid()::text = (storage.foldername(name))[1]
            );
    END IF;
END $$;

-- Users can view their own photos
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Users can view own photos'
    ) THEN
        CREATE POLICY "Users can view own photos"
            ON storage.objects FOR SELECT
            USING (
                bucket_id = 'mood-photos' AND
                auth.uid()::text = (storage.foldername(name))[1]
            );
    END IF;
END $$;

-- Users can delete their own photos
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Users can delete own photos'
    ) THEN
        CREATE POLICY "Users can delete own photos"
            ON storage.objects FOR DELETE
            USING (
                bucket_id = 'mood-photos' AND
                auth.uid()::text = (storage.foldername(name))[1]
            );
    END IF;
END $$;

-- ============================================================================
-- TRIGGER: updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_photo_moods_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_photo_moods_updated_at ON photo_moods;

CREATE TRIGGER trigger_photo_moods_updated_at
    BEFORE UPDATE ON photo_moods
    FOR EACH ROW
    EXECUTE FUNCTION update_photo_moods_updated_at();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE photo_moods IS 'Photo-based mood logging entries with privacy controls';
COMMENT ON COLUMN photo_moods.mood_score IS 'Mood rating 1-5 (1=worst, 5=best)';
COMMENT ON COLUMN photo_moods.caption IS 'Optional user caption (max 500 chars)';
COMMENT ON COLUMN photo_moods.emotion_tags IS 'Array of emotion keywords (max 5)';
COMMENT ON COLUMN photo_moods.photo_storage_path IS 'Supabase Storage path: {user_id}/{timestamp}.jpg';
COMMENT ON COLUMN photo_moods.photo_thumbnail_path IS 'Thumbnail path: {user_id}/thumb_{timestamp}.jpg';
COMMENT ON COLUMN photo_moods.ai_mood_suggestion IS 'Future: AI-suggested mood score';
COMMENT ON COLUMN photo_moods.shared_to_circle_id IS 'Future: Circle ID if shared';
