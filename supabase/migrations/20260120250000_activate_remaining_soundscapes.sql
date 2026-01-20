-- Activate Remaining Soundscapes
-- ============================================================================
-- Marks the final 4 soundscapes as active now that audio files exist in storage.
-- These are: White Noise (free), Thunderstorm, Campfire, and Binaural Sleep Waves (all premium).
-- ============================================================================

-- Update White Noise (Free Tier)
-- ============================================================================
UPDATE sleep_content
SET
    is_active = true,
    audio_url = 'https://***REMOVED***/storage/v1/object/public/sleep-content/soundscapes/white-noise.m4a',
    duration_seconds = 1800 -- 30 minutes
WHERE title = 'White Noise' AND content_type = 'soundscape';

-- Update Thunderstorm (Premium)
-- ============================================================================
UPDATE sleep_content
SET
    is_active = true,
    audio_url = 'https://***REMOVED***/storage/v1/object/public/sleep-content/soundscapes/thunderstorm.m4a',
    duration_seconds = 1800 -- 30 minutes
WHERE title = 'Thunderstorm' AND content_type = 'soundscape' AND is_premium = true;

-- Update Campfire (Premium)
-- ============================================================================
UPDATE sleep_content
SET
    is_active = true,
    audio_url = 'https://***REMOVED***/storage/v1/object/public/sleep-content/soundscapes/campfire.m4a',
    duration_seconds = 1800 -- 30 minutes
WHERE title = 'Campfire' AND content_type = 'soundscape' AND is_premium = true;

-- Update Binaural Sleep Waves (Premium)
-- ============================================================================
UPDATE sleep_content
SET
    is_active = true,
    audio_url = 'https://***REMOVED***/storage/v1/object/public/sleep-content/soundscapes/binaural.m4a',
    duration_seconds = 1800 -- 30 minutes
WHERE title = 'Binaural Sleep Waves' AND content_type = 'soundscape' AND is_premium = true;

-- Verify the updates
-- ============================================================================
DO $$
DECLARE
    active_soundscape_count INTEGER;
    free_soundscape_count INTEGER;
    premium_soundscape_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO active_soundscape_count
    FROM sleep_content
    WHERE is_active = true AND content_type = 'soundscape';

    SELECT COUNT(*) INTO free_soundscape_count
    FROM sleep_content
    WHERE is_active = true AND content_type = 'soundscape' AND is_premium = false;

    SELECT COUNT(*) INTO premium_soundscape_count
    FROM sleep_content
    WHERE is_active = true AND content_type = 'soundscape' AND is_premium = true;

    RAISE NOTICE 'Activated % total soundscapes (% free, % premium)',
        active_soundscape_count, free_soundscape_count, premium_soundscape_count;
END $$;
