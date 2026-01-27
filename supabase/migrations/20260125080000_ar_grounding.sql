-- Migration: AR Grounding Exercises
-- Created: 2026-01-25
-- Description: Add tables for AR exercise types, sessions, and scene preferences

-- =============================================================================
-- TABLE: ar_exercise_types
-- Stores AR exercise definitions with capability requirements
-- =============================================================================

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

-- Index for filtering by type
CREATE INDEX IF NOT EXISTS idx_ar_exercise_types_ar_type ON ar_exercise_types(ar_type);
CREATE INDEX IF NOT EXISTS idx_ar_exercise_types_premium ON ar_exercise_types(is_premium);

-- Enable RLS
ALTER TABLE ar_exercise_types ENABLE ROW LEVEL SECURITY;

-- Policy: all authenticated users can read exercise types
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_types'
        AND policyname = 'Authenticated users read AR exercise types'
    ) THEN
        CREATE POLICY "Authenticated users read AR exercise types"
            ON ar_exercise_types FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- Policy: service role can manage exercise types
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_types'
        AND policyname = 'Service role manages AR exercise types'
    ) THEN
        CREATE POLICY "Service role manages AR exercise types"
            ON ar_exercise_types FOR ALL
            USING (auth.role() = 'service_role');
    END IF;
END $$;

-- =============================================================================
-- TABLE: ar_exercise_sessions
-- Tracks user AR exercise sessions with completion and effectiveness data
-- =============================================================================

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

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_ar_sessions_user_id ON ar_exercise_sessions(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_ar_sessions_exercise_type ON ar_exercise_sessions(exercise_type_id);
CREATE INDEX IF NOT EXISTS idx_ar_sessions_completed ON ar_exercise_sessions(user_id, completed_at) WHERE completed_at IS NOT NULL;

-- Enable RLS
ALTER TABLE ar_exercise_sessions ENABLE ROW LEVEL SECURITY;

-- Policy: users can read their own sessions
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_sessions'
        AND policyname = 'Users read own AR sessions'
    ) THEN
        CREATE POLICY "Users read own AR sessions"
            ON ar_exercise_sessions FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Policy: users can insert their own sessions
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_sessions'
        AND policyname = 'Users insert own AR sessions'
    ) THEN
        CREATE POLICY "Users insert own AR sessions"
            ON ar_exercise_sessions FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Policy: users can update their own sessions (for adding ratings)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_exercise_sessions'
        AND policyname = 'Users update own AR sessions'
    ) THEN
        CREATE POLICY "Users update own AR sessions"
            ON ar_exercise_sessions FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- TABLE: ar_scene_preferences
-- Stores user preferences for AR scenes (Safe Space customization)
-- =============================================================================

CREATE TABLE IF NOT EXISTS ar_scene_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scene_name TEXT NOT NULL,
    scene_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for user lookup
CREATE INDEX IF NOT EXISTS idx_ar_scene_prefs_user_id ON ar_scene_preferences(user_id);

-- Unique constraint: only one default scene per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_ar_scene_prefs_default
    ON ar_scene_preferences(user_id)
    WHERE is_default = true;

-- Enable RLS
ALTER TABLE ar_scene_preferences ENABLE ROW LEVEL SECURITY;

-- Policy: users manage their own scene preferences
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'ar_scene_preferences'
        AND policyname = 'Users manage own AR scene preferences'
    ) THEN
        CREATE POLICY "Users manage own AR scene preferences"
            ON ar_scene_preferences FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- SEED DATA: AR Exercise Types
-- =============================================================================

INSERT INTO ar_exercise_types (
    exercise_name,
    ar_type,
    description,
    duration_seconds,
    instructions,
    required_capabilities,
    voice_guidance_script,
    scene_config,
    is_premium
)
VALUES
    (
        'Breathing Orb',
        'breathing_orb',
        'Follow a 3D orb''s expansion and contraction to guide your breathing rhythm. The orb breathes with you, creating a calming visual anchor.',
        300, -- 5 minutes
        '["Point your camera at an open space", "A calming orb will appear in front of you", "Breathe in as the orb expands", "Hold your breath as the orb pauses", "Breathe out as the orb contracts", "Continue following the rhythm"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
        '["Welcome to the Breathing Orb exercise", "Point your camera at an open space in front of you", "The orb will guide your breathing", "Breathe in", "Hold", "Breathe out", "You are doing great", "Continue breathing with the orb", "Session complete. Well done."]'::jsonb,
        '{"breathPattern": {"inhale": 4, "hold": 2, "exhale": 6}, "orbColor": "#6366F1", "particleCount": 50}'::jsonb,
        false
    ),
    (
        '5-4-3-2-1 Grounding',
        'grounding_541',
        'Ground yourself by identifying things around you. Tap to mark 5 things you see, 4 you can touch, 3 you hear, 2 you smell, and 1 you taste.',
        600, -- 10 minutes
        '["Look around your space", "Tap to mark 5 things you can SEE", "Mark 4 things you could TOUCH", "Mark 3 things you can HEAR", "Mark 2 things you can SMELL", "Mark 1 thing you can TASTE", "Review your grounding markers"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
        '["Welcome to 5-4-3-2-1 grounding", "Let us ground you in the present moment", "Look around and tap 5 things you can see", "Good. Now mark 4 things you could touch", "Excellent. Identify 3 things you can hear", "Almost there. Find 2 things you can smell", "Finally, mark 1 thing you can taste", "You have grounded yourself in the present. Well done."]'::jsonb,
        '{"markerColors": {"see": "#3B82F6", "touch": "#10B981", "hear": "#F59E0B", "smell": "#F97316", "taste": "#8B5CF6"}}'::jsonb,
        false
    ),
    (
        'Safe Space Creator',
        'safe_space',
        'Build your personalized virtual sanctuary by placing calming objects around you. Create a space that feels safe and peaceful.',
        900, -- 15 minutes
        '["Scan your floor by moving the camera", "Choose calming objects from the palette", "Tap to place objects in your space", "Customize the size and position", "Save your safe space for future visits"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": false}'::jsonb,
        '["Welcome to Safe Space Creator", "Let us build your personal sanctuary", "Move your camera to scan the floor", "Great. Now choose objects to place", "Tap anywhere to place your object", "You can resize and move objects", "Take your time creating your space", "Your safe space has been saved"]'::jsonb,
        '{"availableObjects": ["plant", "candle", "crystal", "cushion", "light_orb", "water_fountain"], "ambientLight": 0.7}'::jsonb,
        true -- Premium feature
    ),
    (
        'Nature Immersion',
        'nature_immersion',
        'Immerse yourself in a virtual forest environment with spatial audio. Trees, gentle light, and nature sounds surround you.',
        600, -- 10 minutes
        '["Find a comfortable position", "Allow the nature scene to fade in", "Look around and explore the environment", "Listen to the spatial nature sounds", "Breathe deeply and relax"]'::jsonb,
        '{"arkit": true, "trueDepth": false, "lidar": true}'::jsonb,
        '["Welcome to Nature Immersion", "Find a comfortable position", "The forest is appearing around you", "Take a moment to look around", "Listen to the sounds of nature", "Feel the peaceful atmosphere", "Breathe deeply", "Session complete. Return refreshed."]'::jsonb,
        '{"sceneType": "forest", "ambientAudio": "forest_ambience", "particleEffects": ["falling_leaves", "fireflies"]}'::jsonb,
        true -- Premium feature, requires LiDAR
    )
ON CONFLICT (exercise_name) DO UPDATE SET
    description = EXCLUDED.description,
    duration_seconds = EXCLUDED.duration_seconds,
    instructions = EXCLUDED.instructions,
    required_capabilities = EXCLUDED.required_capabilities,
    voice_guidance_script = EXCLUDED.voice_guidance_script,
    scene_config = EXCLUDED.scene_config,
    is_premium = EXCLUDED.is_premium,
    updated_at = now();

-- =============================================================================
-- FUNCTION: Get AR exercises with availability info
-- =============================================================================

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
        -- Determine availability
        CASE
            WHEN e.is_premium AND NOT v_is_premium_user THEN false
            WHEN e.ar_type = 'nature_immersion' AND p_device_capability != 'full_ar' THEN false
            WHEN p_device_capability = 'fallback' AND e.ar_type != 'breathing_orb' THEN false
            ELSE true
        END AS is_available,
        -- Reason if unavailable
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
