-- Activate Uploaded Soundscapes
-- ============================================================================
-- Mark the uploaded soundscapes as active now that audio files exist in storage
-- ============================================================================

UPDATE sleep_content
SET is_active = true
WHERE title IN ('Ocean Waves', 'Gentle Rain', 'Forest Night')
  AND content_type = 'soundscape';

-- Verify the update
DO $$
DECLARE
    active_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO active_count
    FROM sleep_content
    WHERE is_active = true AND content_type = 'soundscape';

    RAISE NOTICE 'Activated % soundscapes', active_count;
END $$;
