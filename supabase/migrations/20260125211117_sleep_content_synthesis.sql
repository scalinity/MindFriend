-- =====================================================
-- Migration: Sleep Content Synthesis Support
-- Description: Add columns for AI script generation and
--              ElevenLabs voice synthesis tracking
-- Date: 2026-01-25
-- =====================================================

-- Add columns for script storage and synthesis tracking
ALTER TABLE sleep_content
ADD COLUMN IF NOT EXISTS script TEXT,
ADD COLUMN IF NOT EXISTS voice_id TEXT,
ADD COLUMN IF NOT EXISTS synthesis_status TEXT DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS original_audio_url TEXT,
ADD COLUMN IF NOT EXISTS synthesis_error TEXT,
ADD COLUMN IF NOT EXISTS synthesized_at TIMESTAMPTZ;

-- Add constraint for synthesis_status values
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sleep_content_synthesis_status_check'
    ) THEN
        ALTER TABLE sleep_content
        ADD CONSTRAINT sleep_content_synthesis_status_check
        CHECK (synthesis_status IN ('pending', 'generating_script', 'synthesizing', 'completed', 'failed'));
    END IF;
END $$;

-- Index for efficient batch processing queries
CREATE INDEX IF NOT EXISTS idx_sleep_content_synthesis_status
ON sleep_content(synthesis_status)
WHERE synthesis_status != 'completed';

-- Index for voice-based queries
CREATE INDEX IF NOT EXISTS idx_sleep_content_voice_id
ON sleep_content(voice_id)
WHERE voice_id IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN sleep_content.script IS
'Full text script for the story, used for AI voice synthesis via ElevenLabs';

COMMENT ON COLUMN sleep_content.voice_id IS
'ElevenLabs voice ID for synthesis. Defaults by tier: Free=Sarah (EXAVITQu4vr4xnSDxMaL), Premium=Rachel (21m00Tcm4TlvDq8ikWAM), Kids=Elli (MF3mGyEYCl7XYWbV9V6O)';

COMMENT ON COLUMN sleep_content.synthesis_status IS
'Status of audio synthesis: pending, generating_script, synthesizing, completed, failed';

COMMENT ON COLUMN sleep_content.original_audio_url IS
'Backup of the original audio_url before synthesis replacement';

COMMENT ON COLUMN sleep_content.synthesis_error IS
'Error message if synthesis failed, cleared on retry';

COMMENT ON COLUMN sleep_content.synthesized_at IS
'Timestamp when audio was last successfully synthesized';

-- Set default voice_id based on tier for existing stories
UPDATE sleep_content
SET voice_id = CASE
    WHEN is_kids = true THEN 'MF3mGyEYCl7XYWbV9V6O'  -- Elli (gentle whisper)
    WHEN is_premium = true THEN '21m00Tcm4TlvDq8ikWAM'  -- Rachel (soothing)
    ELSE 'EXAVITQu4vr4xnSDxMaL'  -- Sarah (calm)
END
WHERE voice_id IS NULL AND content_type = 'story';

-- Backup existing audio URLs before any synthesis
UPDATE sleep_content
SET original_audio_url = audio_url
WHERE original_audio_url IS NULL
  AND audio_url IS NOT NULL
  AND content_type = 'story';

-- Log migration completion
DO $$
DECLARE
    story_count INTEGER;
    pending_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO story_count
    FROM sleep_content
    WHERE content_type = 'story';

    SELECT COUNT(*) INTO pending_count
    FROM sleep_content
    WHERE content_type = 'story' AND synthesis_status = 'pending';

    RAISE NOTICE 'Sleep content synthesis migration complete: % total stories, % pending synthesis',
        story_count, pending_count;
END $$;
