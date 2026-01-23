-- Replace Custom Stories with LibriVox Public Domain Narrations
-- ============================================================================
-- This migration updates the sleep_content table to replace custom story titles
-- with actual LibriVox public domain narrated fairy tales.
-- All stories are from LibriVox (librivox.org) under public domain license.
-- Note: Table is created in later migration (20260326000000_sleep_winddown_feature.sql)
-- ============================================================================

DO $$
BEGIN
    -- Only proceed if table exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'sleep_content'
    ) THEN
        -- Update Free Tier Stories
        -- ============================================================================

        -- Replace "Rainy Night in the Forest" with "Jack and His Golden Snuff-Box"
        UPDATE sleep_content
SET
    title = 'Jack and His Golden Snuff-Box',
    description = 'A classic English fairy tale about a young man who inherits a magical snuff-box from his father. Join Jack on an enchanting adventure filled with wonder and magic. Narrated by Joy Chan.',
    narrator = 'Joy Chan',
    duration_seconds = 1162, -- 19:22
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/jack-golden-snuff-box.m4a',
    is_active = true
WHERE title = 'Rainy Night in the Forest' AND content_type = 'story';

-- Replace "The Sleepy Village" with "Whittington and His Cat"
UPDATE sleep_content
SET
    title = 'Whittington and His Cat',
    description = 'The beloved tale of Dick Whittington and his remarkable cat, a classic English folklore story of fortune and friendship. Narrated by Joy Chan.',
    narrator = 'Joy Chan',
    duration_seconds = 1092, -- 18:12
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/whittington-and-his-cat.m4a',
    is_active = true
WHERE title = 'The Sleepy Village' AND content_type = 'story';

-- Replace "The Midnight Train" with "Jack the Giant-Killer"
UPDATE sleep_content
SET
    title = 'Jack the Giant-Killer',
    description = 'The legendary tale of brave Jack who outwits fearsome giants with his courage and cleverness. A classic English fairy tale perfect for drifting off to sleep. Narrated by Joy Chan.',
    narrator = 'Joy Chan',
    duration_seconds = 1375, -- 22:55
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/jack-the-giant-killer.m4a',
    is_active = true
WHERE title = 'The Midnight Train' AND content_type = 'story';

-- Note: "Mountain Lake at Dusk" - keeping as placeholder since "The Daisy" is only 2 minutes
-- Can be updated later or combined with other short tales

-- Update Premium Stories
-- ============================================================================

-- Replace "The Lighthouse Keeper" with "The Brave Tin Soldier"
UPDATE sleep_content
SET
    title = 'The Brave Tin Soldier',
    description = 'Hans Christian Andersen''s touching tale of a one-legged tin soldier and his love for a beautiful paper ballerina. A timeless story of courage and devotion.',
    narrator = 'LibriVox Volunteer',
    duration_seconds = 305, -- 5:05
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/the-brave-tin-soldier.m4a',
    is_active = true
WHERE title = 'The Lighthouse Keeper' AND content_type = 'story' AND is_premium = true;

-- Replace "Autumn in the Orchard" with "The Ugly Duckling"
UPDATE sleep_content
SET
    title = 'The Ugly Duckling',
    description = 'Hans Christian Andersen''s beloved story of transformation and finding where you belong. A heartwarming tale of an outcast who becomes a beautiful swan.',
    narrator = 'LibriVox Volunteer',
    duration_seconds = 387, -- 6:27
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/the-ugly-duckling.m4a',
    is_active = true
WHERE title = 'Autumn in the Orchard' AND content_type = 'story' AND is_premium = true;

-- Update Kids Stories
-- ============================================================================

-- Replace "The Sleepy Bear" with "Thumbelina"
UPDATE sleep_content
SET
    title = 'Thumbelina',
    description = 'The magical adventure of a tiny girl no bigger than a thumb. Join Thumbelina on her journey through gardens, fields, and forests in this enchanting bedtime tale.',
    narrator = 'LibriVox Volunteer',
    duration_seconds = 406, -- 6:46
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/thumbelina.m4a',
    is_active = true
WHERE title = 'The Sleepy Bear' AND content_type = 'story' AND is_kids = true;

-- Replace "Starlight Dreams" with another copy of "The Ugly Duckling"
-- Note: Using the same file for both, which is acceptable for different audiences
UPDATE sleep_content
SET
    title = 'The Ugly Duckling',
    description = 'A wonderful bedtime story about being different and finding your true self. Perfect for little ones learning about kindness and acceptance.',
    narrator = 'LibriVox Volunteer',
    duration_seconds = 387, -- 6:27
    audio_url = 'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/sleep-content/stories/the-ugly-duckling.m4a',
    is_active = true
WHERE title = 'Starlight Dreams' AND content_type = 'story' AND is_kids = true;

        -- Verify the updates
        DECLARE
            active_story_count INTEGER;
            free_story_count INTEGER;
            premium_story_count INTEGER;
            kids_story_count INTEGER;
        BEGIN
            SELECT COUNT(*) INTO active_story_count
            FROM sleep_content
            WHERE is_active = true AND content_type = 'story';

            SELECT COUNT(*) INTO free_story_count
            FROM sleep_content
            WHERE is_active = true AND content_type = 'story' AND is_premium = false AND is_kids = false;

            SELECT COUNT(*) INTO premium_story_count
            FROM sleep_content
            WHERE is_active = true AND content_type = 'story' AND is_premium = true;

            SELECT COUNT(*) INTO kids_story_count
            FROM sleep_content
            WHERE is_active = true AND content_type = 'story' AND is_kids = true;

            RAISE NOTICE 'Activated % total stories (% free, % premium, % kids)',
                active_story_count, free_story_count, premium_story_count, kids_story_count;
        END;

        -- Add attribution comment
        COMMENT ON TABLE sleep_content IS
        'Sleep content library with audio files from public domain sources.
        Stories: LibriVox (librivox.org) - Public Domain narrated fairy tales
        Soundscapes: Internet Archive (archive.org) - CC0/Public Domain ambient sounds
        All content is legally licensed for commercial use without attribution requirements.';
    ELSE
        RAISE NOTICE 'sleep_content table does not exist yet, skipping story updates';
    END IF;
END $$;
