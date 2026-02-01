-- Add audio_url column to exercises table for meditation audio files
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS audio_url TEXT;

-- Add comment for documentation
COMMENT ON COLUMN exercises.audio_url IS 'URL to audio file for guided exercises (meditation, breathing, etc.)';
