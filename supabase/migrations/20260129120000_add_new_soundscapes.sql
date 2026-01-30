-- Add new soundscapes from the soundscapes storage bucket
-- These use the royalty-free audio files uploaded from BigSoundBank and Archive.org

-- Rain (free) - 1:20 duration
INSERT INTO sleep_content (
    id, title, description, content_type, category, duration_seconds,
    narrator, is_premium, is_kids, audio_url, thumbnail_url,
    is_loopable, is_active, is_featured, sort_order, created_at, updated_at
) VALUES (
    gen_random_uuid(),
    'Rain Sounds',
    'Gentle rain falling on concrete. A soothing ambient sound for relaxation and sleep.',
    'soundscape', 'nature', 80,
    NULL, false, false,
    'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/soundscapes/rain.mp3',
    NULL, true, true, false, 10, NOW(), NOW()
) ON CONFLICT DO NOTHING;

-- Forest (premium) - 54 seconds duration
INSERT INTO sleep_content (
    id, title, description, content_type, category, duration_seconds,
    narrator, is_premium, is_kids, audio_url, thumbnail_url,
    is_loopable, is_active, is_featured, sort_order, created_at, updated_at
) VALUES (
    gen_random_uuid(),
    'Forest Ambience',
    'Peaceful forest sounds with birdsong and gentle rustling leaves. Perfect for meditation.',
    'soundscape', 'nature', 54,
    NULL, true, false,
    'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/soundscapes/forest.mp3',
    NULL, true, true, false, 11, NOW(), NOW()
) ON CONFLICT DO NOTHING;

-- Fireplace (premium) - 45 seconds duration
INSERT INTO sleep_content (
    id, title, description, content_type, category, duration_seconds,
    narrator, is_premium, is_kids, audio_url, thumbnail_url,
    is_loopable, is_active, is_featured, sort_order, created_at, updated_at
) VALUES (
    gen_random_uuid(),
    'Crackling Fireplace',
    'Warm crackling fireplace sounds. Feel cozy and relaxed as you drift off to sleep.',
    'soundscape', 'ambient', 45,
    NULL, true, false,
    'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/soundscapes/fireplace.mp3',
    NULL, true, true, true, 12, NOW(), NOW()
) ON CONFLICT DO NOTHING;

-- Brown Noise (premium) - 10 minutes duration
INSERT INTO sleep_content (
    id, title, description, content_type, category, duration_seconds,
    narrator, is_premium, is_kids, audio_url, thumbnail_url,
    is_loopable, is_active, is_featured, sort_order, created_at, updated_at
) VALUES (
    gen_random_uuid(),
    'Brown Noise',
    'Deep, low-frequency brown noise. Excellent for blocking distractions and promoting deep sleep.',
    'soundscape', 'white_noise', 600,
    NULL, true, false,
    'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/soundscapes/brown_noise.mp3',
    NULL, true, true, true, 13, NOW(), NOW()
) ON CONFLICT DO NOTHING;

-- Pink Noise (premium) - 19 seconds duration (will loop)
INSERT INTO sleep_content (
    id, title, description, content_type, category, duration_seconds,
    narrator, is_premium, is_kids, audio_url, thumbnail_url,
    is_loopable, is_active, is_featured, sort_order, created_at, updated_at
) VALUES (
    gen_random_uuid(),
    'Pink Noise',
    'Balanced pink noise with equal energy per octave. Scientifically shown to improve sleep quality.',
    'soundscape', 'white_noise', 19,
    NULL, true, false,
    'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/soundscapes/pink_noise.mp3',
    NULL, true, true, false, 14, NOW(), NOW()
) ON CONFLICT DO NOTHING;

-- Ocean (premium) - 57 seconds
INSERT INTO sleep_content (
    id, title, description, content_type, category, duration_seconds,
    narrator, is_premium, is_kids, audio_url, thumbnail_url,
    is_loopable, is_active, is_featured, sort_order, created_at, updated_at
) VALUES (
    gen_random_uuid(),
    'Calm Ocean',
    'Gentle ocean waves washing onto shore. A classic soundscape for relaxation.',
    'soundscape', 'nature', 57,
    NULL, true, false,
    'https://zfaucivtzfwnrijsbfug.supabase.co/storage/v1/object/public/soundscapes/ocean.mp3',
    NULL, true, true, false, 15, NOW(), NOW()
) ON CONFLICT DO NOTHING;
