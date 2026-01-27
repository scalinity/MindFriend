-- Repair migration: Re-create AR grounding function
-- The original migration (20260125080000) was recorded as applied but the function
-- is missing from the schema cache. This re-creates it using CREATE OR REPLACE.

-- Ensure tables exist first (idempotent)
CREATE TABLE IF NOT EXISTS ar_exercise_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_name TEXT NOT NULL UNIQUE,
    ar_type TEXT NOT NULL CHECK (ar_type IN ('breathing_orb', 'grounding_541', 'safe_space', 'nature_immersion')),
    description TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL CHECK (duration_seconds > 0),
    instructions JSONB NOT NULL DEFAULT '[]'::jsonb,
    required_capabilities JSONB NOT NULL DEFAULT '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
    voice_guidance_script JSONB NOT NULL DEFAULT '[]'::jsonb,
    scene_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_premium BOOLEAN NOT NULL DEFAULT false,
    asset_urls JSONB DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ar_exercise_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_type_id UUID NOT NULL REFERENCES ar_exercise_types(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ DEFAULT NULL,
    effectiveness_rating INTEGER CHECK (effectiveness_rating IS NULL OR (effectiveness_rating BETWEEN 1 AND 5)),
    tracking_quality_avg REAL CHECK (tracking_quality_avg IS NULL OR (tracking_quality_avg BETWEEN 0 AND 1)),
    interruptions_count INTEGER NOT NULL DEFAULT 0,
    device_capability TEXT CHECK (device_capability IN ('full_ar', 'limited_ar', 'fallback')),
    used_voice_guidance BOOLEAN DEFAULT false,
    completed_steps INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ar_scene_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scene_name TEXT NOT NULL,
    scene_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Re-create the function
CREATE OR REPLACE FUNCTION get_ar_exercises_for_user(
    p_user_id UUID,
    p_device_capability TEXT DEFAULT 'full_ar'
)
RETURNS TABLE (
    id UUID,
    exercise_name TEXT,
    ar_type TEXT,
    description TEXT,
    duration_seconds INTEGER,
    instructions JSONB,
    voice_guidance_script JSONB,
    scene_config JSONB,
    is_premium BOOLEAN,
    is_available BOOLEAN,
    unavailable_reason TEXT
) AS $$
DECLARE
    v_is_premium_user BOOLEAN;
BEGIN
    -- Check if user has premium subscription
    SELECT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE user_id = p_user_id
        AND status = 'active'
    ) INTO v_is_premium_user;

    RETURN QUERY
    SELECT
        e.id,
        e.exercise_name,
        e.ar_type,
        e.description,
        e.duration_seconds,
        e.instructions,
        e.voice_guidance_script,
        e.scene_config,
        e.is_premium,
        CASE
            WHEN e.is_premium AND NOT v_is_premium_user THEN false
            WHEN e.ar_type = 'nature_immersion' AND p_device_capability != 'full_ar' THEN false
            WHEN p_device_capability = 'fallback' AND e.ar_type != 'breathing_orb' THEN false
            ELSE true
        END AS is_available,
        CASE
            WHEN e.is_premium AND NOT v_is_premium_user THEN 'requires_premium'
            WHEN e.ar_type = 'nature_immersion' AND p_device_capability != 'full_ar' THEN 'requires_lidar'
            WHEN p_device_capability = 'fallback' AND e.ar_type != 'breathing_orb' THEN 'requires_ar'
            ELSE NULL
        END AS unavailable_reason
    FROM ar_exercise_types e
    ORDER BY e.is_premium ASC, e.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_ar_exercises_for_user(UUID, TEXT) TO authenticated;

-- Re-insert seed data (idempotent via ON CONFLICT)
INSERT INTO ar_exercise_types (
    exercise_name, ar_type, description, duration_seconds, instructions,
    required_capabilities, voice_guidance_script, scene_config, is_premium
)
VALUES
    (
        'Breathing Orb', 'breathing_orb',
        'Follow a 3D orb''s expansion and contraction to guide your breathing rhythm. The orb breathes with you, creating a calming visual anchor.',
        300,
        '["Point your camera at an open space", "A calming orb will appear in front of you", "Breathe in as the orb expands", "Hold your breath as the orb pauses", "Breathe out as the orb contracts", "Continue following the rhythm"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
        '["Welcome to the Breathing Orb exercise", "Point your camera at an open space in front of you", "The orb will guide your breathing", "Breathe in", "Hold", "Breathe out", "You are doing great", "Continue breathing with the orb", "Session complete. Well done."]'::jsonb,
        '{"breathPattern": {"inhale": 4, "hold": 2, "exhale": 6}, "orbColor": "#6366F1", "particleCount": 50}'::jsonb,
        false
    ),
    (
        '5-4-3-2-1 Grounding', 'grounding_541',
        'Ground yourself by identifying things around you. Tap to mark 5 things you see, 4 you can touch, 3 you hear, 2 you smell, and 1 you taste.',
        600,
        '["Look around your space", "Tap to mark 5 things you can SEE", "Mark 4 things you could TOUCH", "Mark 3 things you can HEAR", "Mark 2 things you can SMELL", "Mark 1 thing you can TASTE", "Review your grounding markers"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
        '["Welcome to 5-4-3-2-1 grounding", "Let us ground you in the present moment", "Look around and tap 5 things you can see", "Good. Now mark 4 things you could touch", "Excellent. Identify 3 things you can hear", "Almost there. Find 2 things you can smell", "Finally, mark 1 thing you can taste", "You have grounded yourself in the present. Well done."]'::jsonb,
        '{"markerColors": {"see": "#3B82F6", "touch": "#10B981", "hear": "#F59E0B", "smell": "#F97316", "taste": "#8B5CF6"}}'::jsonb,
        false
    ),
    (
        'Safe Space Creator', 'safe_space',
        'Build your personalized virtual sanctuary by placing calming objects around you. Create a space that feels safe and peaceful.',
        900,
        '["Scan your floor by moving the camera", "Choose calming objects from the palette", "Tap to place objects in your space", "Customize the size and position", "Save your safe space for future visits"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
        '["Welcome to Safe Space Creator", "Let us build your personal sanctuary", "Move your camera to scan the floor", "Great. Now choose objects to place", "Tap anywhere to place your object", "You can resize and move objects", "Take your time creating your space", "Your safe space has been saved"]'::jsonb,
        '{"availableObjects": ["plant", "candle", "crystal", "cushion", "light_orb", "water_fountain"], "ambientLight": 0.7}'::jsonb,
        true
    ),
    (
        'Nature Immersion', 'nature_immersion',
        'Immerse yourself in a virtual forest environment with spatial audio. Trees, gentle light, and nature sounds surround you.',
        600,
        '["Find a comfortable position", "Allow the nature scene to fade in", "Look around and explore the environment", "Listen to the spatial nature sounds", "Breathe deeply and relax"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": true}'::jsonb,
        '["Welcome to Nature Immersion", "Find a comfortable position", "The forest is appearing around you", "Take a moment to look around", "Listen to the sounds of nature", "Feel the peaceful atmosphere", "Breathe deeply", "Session complete. Return refreshed."]'::jsonb,
        '{"sceneType": "forest", "ambientAudio": "forest_ambience", "particleEffects": ["falling_leaves", "fireflies"]}'::jsonb,
        true
    )
ON CONFLICT (exercise_name) DO NOTHING;
