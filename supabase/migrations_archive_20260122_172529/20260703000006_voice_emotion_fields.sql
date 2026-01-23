-- Voice Mode Emotion Analysis Fields
-- Adds emotion history and settings to support voice emotion detection

-- =====================================================
-- Add emotion fields to journal_entries table
-- =====================================================

-- Add emotion_history column (JSONB array of EmotionSnapshot)
ALTER TABLE journal_entries
ADD COLUMN IF NOT EXISTS emotion_history JSONB DEFAULT '[]'::jsonb;

-- Add emotion_summary column (aggregated emotion data)
ALTER TABLE journal_entries
ADD COLUMN IF NOT EXISTS emotion_summary JSONB DEFAULT '{}'::jsonb;

-- Add index for efficient emotion-based queries
CREATE INDEX IF NOT EXISTS idx_journal_entries_emotion_summary
ON journal_entries USING GIN (emotion_summary);

-- Add index for emotion_history queries
CREATE INDEX IF NOT EXISTS idx_journal_entries_emotion_history
ON journal_entries USING GIN (emotion_history);

-- =====================================================
-- Add emotion settings to voice_settings table
-- =====================================================

-- Check if voice_settings table exists before altering
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'voice_settings') THEN
        -- Add emotion analysis enabled flag
        IF NOT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = 'voice_settings'
            AND column_name = 'emotion_analysis_enabled'
        ) THEN
            ALTER TABLE voice_settings
            ADD COLUMN emotion_analysis_enabled BOOLEAN DEFAULT FALSE;
        END IF;

        -- Add emotion sensitivity threshold (0.4 - 0.8)
        IF NOT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = 'voice_settings'
            AND column_name = 'emotion_sensitivity'
        ) THEN
            ALTER TABLE voice_settings
            ADD COLUMN emotion_sensitivity DECIMAL(3,2) DEFAULT 0.60;
        END IF;

        -- Add show emotion badges preference
        IF NOT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = 'voice_settings'
            AND column_name = 'show_emotion_badges'
        ) THEN
            ALTER TABLE voice_settings
            ADD COLUMN show_emotion_badges BOOLEAN DEFAULT TRUE;
        END IF;

        -- Add include emotion in prompts preference
        IF NOT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = 'voice_settings'
            AND column_name = 'include_emotion_in_prompts'
        ) THEN
            ALTER TABLE voice_settings
            ADD COLUMN include_emotion_in_prompts BOOLEAN DEFAULT TRUE;
        END IF;

        -- Add save emotion history preference
        IF NOT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = 'voice_settings'
            AND column_name = 'save_emotion_history'
        ) THEN
            ALTER TABLE voice_settings
            ADD COLUMN save_emotion_history BOOLEAN DEFAULT TRUE;
        END IF;
    END IF;
END $$;

-- =====================================================
-- Add constraint for emotion sensitivity range
-- =====================================================

DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'voice_settings') THEN
        -- Check if constraint doesn't exist before adding
        IF NOT EXISTS (
            SELECT FROM pg_constraint
            WHERE conname = 'voice_settings_emotion_sensitivity_range'
        ) THEN
            ALTER TABLE voice_settings
            ADD CONSTRAINT voice_settings_emotion_sensitivity_range
            CHECK (emotion_sensitivity >= 0.4 AND emotion_sensitivity <= 0.8);
        END IF;
    END IF;
END $$;

-- =====================================================
-- RLS Policies for emotion data (already covered by
-- existing journal_entries and voice_settings policies)
-- =====================================================

-- Add comment explaining emotion_history structure
COMMENT ON COLUMN journal_entries.emotion_history IS
'Array of emotion snapshots detected during voice session: [{id, emotion, confidence, all_probabilities, timestamp, transcript_segment}]';

COMMENT ON COLUMN journal_entries.emotion_summary IS
'Aggregated emotion data: {dominant_emotion, average_confidence, emotion_distribution, total_detections}';

-- =====================================================
-- Migration complete
-- =====================================================
