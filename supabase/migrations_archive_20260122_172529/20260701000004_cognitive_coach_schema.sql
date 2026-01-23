-- Cognitive Bias Coach Schema
-- Creates tables for distortion detection, user settings, pattern tracking, and analytics

-- ============================================================================
-- 1. COGNITIVE DISTORTIONS TAXONOMY (read-only reference data)
-- ============================================================================

CREATE TABLE IF NOT EXISTS cognitive_distortions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,  -- e.g., 'AON', 'CAT', 'MIND'
    name TEXT NOT NULL,
    short_description TEXT NOT NULL,
    full_description TEXT NOT NULL,
    examples TEXT[] NOT NULL DEFAULT '{}',
    questions_to_challenge TEXT[] NOT NULL DEFAULT '{}',  -- Socratic questions
    reframe_templates TEXT[] NOT NULL DEFAULT '{}',  -- Template variations
    severity_weight INTEGER DEFAULT 1,  -- For sensitivity adjustment (future use)
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for lookups by code
CREATE INDEX IF NOT EXISTS idx_cognitive_distortions_code ON cognitive_distortions(code);
CREATE INDEX IF NOT EXISTS idx_cognitive_distortions_display_order ON cognitive_distortions(display_order);

-- RLS: Read-only for authenticated users
ALTER TABLE cognitive_distortions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'cognitive_distortions'
        AND policyname = 'Authenticated users can read distortions'
    ) THEN
        CREATE POLICY "Authenticated users can read distortions"
            ON cognitive_distortions FOR SELECT
            TO authenticated
            USING (true);
    END IF;
END $$;

-- ============================================================================
-- 2. DISTORTION EDUCATION (multi-language translations)
-- ============================================================================

CREATE TABLE IF NOT EXISTS distortion_education (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    distortion_id UUID NOT NULL REFERENCES cognitive_distortions(id) ON DELETE CASCADE,
    locale TEXT NOT NULL,  -- 'en', 'es', 'pt-BR'
    name_translated TEXT NOT NULL,
    short_description_translated TEXT NOT NULL,
    full_description_translated TEXT NOT NULL,
    examples_translated TEXT[] NOT NULL DEFAULT '{}',
    reframe_templates_translated TEXT[] NOT NULL DEFAULT '{}',
    questions_translated TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(distortion_id, locale)
);

-- Index for lookups by distortion + locale
CREATE INDEX IF NOT EXISTS idx_distortion_education_lookup ON distortion_education(distortion_id, locale);

-- RLS: Read-only for authenticated users
ALTER TABLE distortion_education ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_education'
        AND policyname = 'Authenticated users can read education content'
    ) THEN
        CREATE POLICY "Authenticated users can read education content"
            ON distortion_education FOR SELECT
            TO authenticated
            USING (true);
    END IF;
END $$;

-- ============================================================================
-- 3. DISTORTION ENCOUNTERS (user interaction logs)
-- ============================================================================

CREATE TABLE IF NOT EXISTS distortion_encounters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    distortion_code TEXT NOT NULL,
    conversation_id UUID,  -- Optional: link to specific conversation
    original_message_preview TEXT NOT NULL,  -- First 200 chars
    reframe_offered BOOLEAN DEFAULT TRUE,
    reframe_accepted BOOLEAN DEFAULT FALSE,
    reframe_text TEXT,  -- The actual reframe shown
    user_action TEXT,  -- 'helpful', 'dismissed', 'learn_more', null (ignored)
    encounter_type TEXT DEFAULT 'chat',  -- 'chat', 'journal', 'voice'
    confidence NUMERIC(3,2) NOT NULL,  -- 0.00 to 1.00
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_distortion_encounters_user_id ON distortion_encounters(user_id);
CREATE INDEX IF NOT EXISTS idx_distortion_encounters_occurred_at ON distortion_encounters(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_distortion_encounters_code ON distortion_encounters(user_id, distortion_code);

-- RLS: Users can only see their own encounters
ALTER TABLE distortion_encounters ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_encounters'
        AND policyname = 'Users can read own encounters'
    ) THEN
        CREATE POLICY "Users can read own encounters"
            ON distortion_encounters FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_encounters'
        AND policyname = 'Service role can insert encounters'
    ) THEN
        CREATE POLICY "Service role can insert encounters"
            ON distortion_encounters FOR INSERT
            TO service_role
            WITH CHECK (true);
    END IF;
END $$;

-- ============================================================================
-- 4. COACH SETTINGS (user preferences)
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    is_enabled BOOLEAN DEFAULT TRUE,
    sensitivity_level TEXT DEFAULT 'balanced' CHECK (sensitivity_level IN ('minimal', 'balanced', 'frequent')),
    silent_hours_start TIME,  -- UTC time
    silent_hours_end TIME,    -- UTC time
    disabled_distortions TEXT[] DEFAULT '{}',  -- Distortion codes to suppress
    show_patterns BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Users can manage their own settings
ALTER TABLE coach_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'coach_settings'
        AND policyname = 'Users can read own settings'
    ) THEN
        CREATE POLICY "Users can read own settings"
            ON coach_settings FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'coach_settings'
        AND policyname = 'Users can insert own settings'
    ) THEN
        CREATE POLICY "Users can insert own settings"
            ON coach_settings FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'coach_settings'
        AND policyname = 'Users can update own settings'
    ) THEN
        CREATE POLICY "Users can update own settings"
            ON coach_settings FOR UPDATE
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- 5. COACH INTERACTIONS (analytics without storing message content)
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    encounter_id UUID REFERENCES distortion_encounters(id) ON DELETE CASCADE,
    distortion_code TEXT NOT NULL,
    action TEXT NOT NULL,  -- 'shown', 'dismissed', 'helpful', 'learn_more'
    confidence NUMERIC(3,2),
    occurred_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for analytics queries
CREATE INDEX IF NOT EXISTS idx_coach_interactions_user_id ON coach_interactions(user_id);
CREATE INDEX IF NOT EXISTS idx_coach_interactions_occurred_at ON coach_interactions(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_coach_interactions_action ON coach_interactions(user_id, action);

-- RLS: Users can see their own interactions
ALTER TABLE coach_interactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'coach_interactions'
        AND policyname = 'Users can read own interactions'
    ) THEN
        CREATE POLICY "Users can read own interactions"
            ON coach_interactions FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'coach_interactions'
        AND policyname = 'Service role can insert interactions'
    ) THEN
        CREATE POLICY "Service role can insert interactions"
            ON coach_interactions FOR INSERT
            TO service_role
            WITH CHECK (true);
    END IF;
END $$;

-- ============================================================================
-- 6. WEEKLY PATTERN SUMMARIES (for trend tracking)
-- ============================================================================

CREATE TABLE IF NOT EXISTS weekly_pattern_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    week_end DATE NOT NULL,
    total_encounters INTEGER NOT NULL DEFAULT 0,
    distortion_counts JSONB NOT NULL DEFAULT '{}',  -- {code: count}
    new_patterns TEXT[] DEFAULT '{}',  -- First-time distortions this week
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, week_start)
);

-- Indexes for lookups
CREATE INDEX IF NOT EXISTS idx_weekly_summaries_user_week ON weekly_pattern_summaries(user_id, week_start DESC);

-- RLS: Users can see their own summaries
ALTER TABLE weekly_pattern_summaries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'weekly_pattern_summaries'
        AND policyname = 'Users can read own summaries'
    ) THEN
        CREATE POLICY "Users can read own summaries"
            ON weekly_pattern_summaries FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'weekly_pattern_summaries'
        AND policyname = 'Service role can manage summaries'
    ) THEN
        CREATE POLICY "Service role can manage summaries"
            ON weekly_pattern_summaries FOR ALL
            TO service_role
            USING (true);
    END IF;
END $$;

-- ============================================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION update_cognitive_coach_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers to tables with updated_at
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'set_cognitive_distortions_updated_at'
    ) THEN
        CREATE TRIGGER set_cognitive_distortions_updated_at
            BEFORE UPDATE ON cognitive_distortions
            FOR EACH ROW EXECUTE FUNCTION update_cognitive_coach_updated_at();
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'set_distortion_education_updated_at'
    ) THEN
        CREATE TRIGGER set_distortion_education_updated_at
            BEFORE UPDATE ON distortion_education
            FOR EACH ROW EXECUTE FUNCTION update_cognitive_coach_updated_at();
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'set_coach_settings_updated_at'
    ) THEN
        CREATE TRIGGER set_coach_settings_updated_at
            BEFORE UPDATE ON coach_settings
            FOR EACH ROW EXECUTE FUNCTION update_cognitive_coach_updated_at();
    END IF;
END $$;
