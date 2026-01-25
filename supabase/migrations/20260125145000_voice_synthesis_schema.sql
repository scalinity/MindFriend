-- Migration: Voice Synthesis Infrastructure
-- Purpose: Create storage bucket and add voice settings tracking
-- Author: dev-pipeline
-- Date: 2026-01-25

-- Add voice_settings_used column to generated_content if not exists
ALTER TABLE generated_content
  ADD COLUMN IF NOT EXISTS voice_settings_used JSONB;

COMMENT ON COLUMN generated_content.voice_settings_used IS
  'ElevenLabs voice settings used for synthesis: {voiceId, stability, similarityBoost, style, speed, modelId}';

-- Create index on voice_settings_used for analytics queries
CREATE INDEX IF NOT EXISTS idx_generated_content_voice_settings
  ON generated_content USING GIN (voice_settings_used);

-- Create generated-audio storage bucket (private, 50MB file limit)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'generated-audio',
  'generated-audio',
  false,
  52428800, -- 50MB in bytes
  ARRAY['audio/mpeg', 'audio/mp3', 'audio/wav']::text[]
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies for generated-audio bucket
-- Users can read their own audio files
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can read own generated audio'
  ) THEN
    CREATE POLICY "Users can read own generated audio"
    ON storage.objects FOR SELECT
    USING (
      bucket_id = 'generated-audio' AND
      auth.uid()::text = (storage.foldername(name))[1]
    );
  END IF;
END $$;

-- Users can upload to their own folder (for re-synthesis)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can upload own generated audio'
  ) THEN
    CREATE POLICY "Users can upload own generated audio"
    ON storage.objects FOR INSERT
    WITH CHECK (
      bucket_id = 'generated-audio' AND
      auth.uid()::text = (storage.foldername(name))[1]
    );
  END IF;
END $$;

-- Users can update their own audio files
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can update own generated audio'
  ) THEN
    CREATE POLICY "Users can update own generated audio"
    ON storage.objects FOR UPDATE
    USING (
      bucket_id = 'generated-audio' AND
      auth.uid()::text = (storage.foldername(name))[1]
    );
  END IF;
END $$;

-- Users can delete their own audio files
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can delete own generated audio'
  ) THEN
    CREATE POLICY "Users can delete own generated audio"
    ON storage.objects FOR DELETE
    USING (
      bucket_id = 'generated-audio' AND
      auth.uid()::text = (storage.foldername(name))[1]
    );
  END IF;
END $$;

-- Add rated_at column for tracking when content was rated
ALTER TABLE generated_content
  ADD COLUMN IF NOT EXISTS rated_at TIMESTAMPTZ;

COMMENT ON COLUMN generated_content.rated_at IS 'Timestamp when user rated this content';
