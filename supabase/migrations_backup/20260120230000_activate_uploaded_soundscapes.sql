-- Activate Uploaded Soundscapes
-- ============================================================================
-- Mark the uploaded soundscapes as active now that audio files exist in storage
-- Note: Table is created in later migration (20260326000000_sleep_winddown_feature.sql)
-- ============================================================================

DO $$
DECLARE
    active_count INTEGER;
BEGIN
    -- Only update if table exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'sleep_content'
    ) THEN
        UPDATE sleep_content
        SET is_active = true
        WHERE title IN ('Ocean Waves', 'Gentle Rain', 'Forest Night')
          AND content_type = 'soundscape';

        -- Verify the update
        SELECT COUNT(*) INTO active_count
        FROM sleep_content
        WHERE is_active = true AND content_type = 'soundscape';

        RAISE NOTICE 'Activated % soundscapes', active_count;
    ELSE
        RAISE NOTICE 'sleep_content table does not exist yet, skipping activation';
    END IF;
END $$;
