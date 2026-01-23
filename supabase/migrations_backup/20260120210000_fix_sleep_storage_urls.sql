-- Fix Sleep Content Storage URLs
-- ============================================================================
-- This migration:
-- 1. Creates the sleep-content storage bucket
-- 2. Sets up public read access policies
-- 3. Updates URLs to use correct project URL format
-- 4. Marks content as inactive until audio files are uploaded
-- ============================================================================

-- Create storage bucket for sleep content
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'sleep-content',
    'sleep-content',
    true,
    52428800, -- 50MB limit
    ARRAY['audio/mp4', 'audio/mpeg', 'audio/m4a', 'audio/wav', 'audio/aac']
)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to sleep content
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'sleep_content_public_read'
    ) THEN
        CREATE POLICY "sleep_content_public_read"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'sleep-content');
    END IF;
END $$;

-- Allow authenticated users to upload sleep content (for admin/content creators)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'sleep_content_authenticated_upload'
    ) THEN
        CREATE POLICY "sleep_content_authenticated_upload"
        ON storage.objects FOR INSERT
        WITH CHECK (bucket_id = 'sleep-content' AND auth.role() = 'authenticated');
    END IF;
END $$;

-- Update sleep_content URLs to use correct project URL format (if table exists)
-- Note: This table is created in a later migration (20260326000000_sleep_winddown_feature.sql)
-- This migration only sets up the storage bucket and policies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'sleep_content') THEN
        -- Mark all content as inactive until files are uploaded
        UPDATE sleep_content
        SET
            is_active = false,
            audio_url = REPLACE(
                audio_url,
                'https://storage.supabase.co/sleep/',
                'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/'
            )
        WHERE audio_url LIKE 'https://storage.supabase.co/sleep/%';

        -- Add a comment to document that audio files need to be uploaded
        COMMENT ON TABLE sleep_content IS
        'Sleep content library. Audio files must be uploaded to the sleep-content storage bucket before setting is_active=true.
        To upload: Use Supabase Dashboard or CLI to upload audio files matching the audio_url paths.';
    END IF;
END $$;
