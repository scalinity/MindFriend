-- Spec 14: Accessibility & Inclusivity - Database Layer
-- Creates all tables, indexes, and RLS policies for accessibility features

-- Table: accessibility_preferences
-- User-specific accessibility settings synced across devices
CREATE TABLE IF NOT EXISTS accessibility_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Visual preferences
    preferred_font_size TEXT DEFAULT 'system', -- 'system' | 'small' | 'medium' | 'large' | 'xlarge'
    high_contrast_enabled BOOLEAN DEFAULT false,
    reduced_transparency_enabled BOOLEAN DEFAULT false,
    color_blind_mode TEXT, -- NULL | 'protanopia' | 'deuteranopia' | 'tritanopia'

    -- Motion preferences
    reduce_motion_enabled BOOLEAN DEFAULT false,
    auto_play_videos BOOLEAN DEFAULT true,
    animation_speed DECIMAL(3,2) DEFAULT 1.0 CHECK (animation_speed >= 0.5 AND animation_speed <= 2.0),

    -- Cognitive preferences
    simplified_mode_enabled BOOLEAN DEFAULT false,
    focus_mode_enabled BOOLEAN DEFAULT false,
    dyslexia_font_enabled BOOLEAN DEFAULT false,
    reading_guide_enabled BOOLEAN DEFAULT false,
    extended_time_limits BOOLEAN DEFAULT false,

    -- Audio preferences
    captions_enabled BOOLEAN DEFAULT true,
    audio_descriptions_enabled BOOLEAN DEFAULT false,
    haptic_feedback_enabled BOOLEAN DEFAULT true,
    visual_alerts_enabled BOOLEAN DEFAULT false,

    -- Localization
    preferred_language TEXT DEFAULT 'en',
    preferred_region TEXT, -- e.g., 'US', 'GB', 'MX'
    date_format TEXT DEFAULT 'system', -- 'system' | 'mdy' | 'dmy' | 'ymd'
    time_format TEXT DEFAULT 'system', -- 'system' | '12h' | '24h'

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: audio_captions
-- Captions and transcripts for audio content (exercises, meditations, etc.)
CREATE TABLE IF NOT EXISTS audio_captions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL CHECK (content_type IN ('exercise', 'meditation', 'story')),
    content_id UUID NOT NULL,
    language TEXT NOT NULL DEFAULT 'en',

    -- Caption data
    format TEXT NOT NULL DEFAULT 'vtt' CHECK (format IN ('vtt', 'srt')),
    captions_url TEXT, -- URL to caption file in storage
    captions_json JSONB, -- Inline captions: [{"id": 1, "start_time": 0, "end_time": 3.5, "text": "..."}]

    -- Transcript
    full_transcript TEXT,

    -- Metadata
    duration_seconds INTEGER,
    word_count INTEGER,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_content_language UNIQUE(content_type, content_id, language)
);

-- Table: localized_strings
-- Server-managed translations for all app strings
CREATE TABLE IF NOT EXISTS localized_strings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    string_key TEXT NOT NULL, -- e.g., 'home.greeting', 'quest.complete.title'
    language TEXT NOT NULL,
    region TEXT, -- NULL for default, or 'US', 'GB', etc.

    -- Content
    value TEXT NOT NULL,
    plural_forms JSONB, -- {"zero": "...", "one": "...", "other": "..."}

    -- Metadata
    context TEXT, -- Description for translators
    max_length INTEGER, -- UI constraint
    screenshot_url TEXT, -- Reference image for translators

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_string_locale UNIQUE(string_key, language, region)
);

-- Table: sign_language_videos
-- Sign language video alternatives for deaf/hard of hearing users
CREATE TABLE IF NOT EXISTS sign_language_videos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL CHECK (content_type IN ('exercise', 'meditation', 'story')),
    content_id UUID NOT NULL,
    sign_language TEXT NOT NULL CHECK (sign_language IN ('ASL', 'BSL', 'Auslan', 'LSF', 'DGS')),

    video_url TEXT NOT NULL,
    thumbnail_url TEXT,
    duration_seconds INTEGER,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_content_sign_language UNIQUE(content_type, content_id, sign_language)
);

-- Table: accessibility_feedback
-- User-submitted feedback about accessibility issues
CREATE TABLE IF NOT EXISTS accessibility_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Feedback details
    category TEXT NOT NULL CHECK (category IN ('voiceover', 'visual', 'motor', 'cognitive', 'audio', 'localization')),
    screen_name TEXT,
    element_identifier TEXT,

    issue_type TEXT NOT NULL CHECK (issue_type IN ('bug', 'improvement', 'missing_label', 'translation')),
    description TEXT NOT NULL,

    -- Context
    device_model TEXT,
    ios_version TEXT,
    app_version TEXT,
    assistive_tech_used TEXT[], -- ['voiceover', 'switch_control', etc.]

    -- Status
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'triaged', 'in_progress', 'resolved')),
    resolution_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: accessibility_audits
-- Internal accessibility compliance audit results
CREATE TABLE IF NOT EXISTS accessibility_audits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    audit_date DATE NOT NULL,
    app_version TEXT NOT NULL,

    -- WCAG compliance
    wcag_level TEXT NOT NULL CHECK (wcag_level IN ('A', 'AA', 'AAA')),
    overall_score DECIMAL(5,2),

    -- Category scores
    perceivable_score DECIMAL(5,2),
    operable_score DECIMAL(5,2),
    understandable_score DECIMAL(5,2),
    robust_score DECIMAL(5,2),

    -- Issues found
    issues JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Auditor
    auditor_type TEXT NOT NULL CHECK (auditor_type IN ('automated', 'manual', 'external')),
    auditor_name TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_accessibility_prefs_user ON accessibility_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_captions_content ON audio_captions(content_type, content_id);
CREATE INDEX IF NOT EXISTS idx_captions_language ON audio_captions(language);
CREATE INDEX IF NOT EXISTS idx_localized_strings_key ON localized_strings(string_key);
CREATE INDEX IF NOT EXISTS idx_localized_strings_language ON localized_strings(language);
CREATE INDEX IF NOT EXISTS idx_localized_strings_region ON localized_strings(region);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON accessibility_feedback(status);
CREATE INDEX IF NOT EXISTS idx_feedback_user ON accessibility_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_sign_language_content ON sign_language_videos(content_type, content_id);

-- Enable Row Level Security
ALTER TABLE accessibility_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_captions ENABLE ROW LEVEL SECURITY;
ALTER TABLE localized_strings ENABLE ROW LEVEL SECURITY;
ALTER TABLE sign_language_videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE accessibility_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE accessibility_audits ENABLE ROW LEVEL SECURITY;

-- RLS Policies: accessibility_preferences
-- Users can only read/write their own preferences
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'accessibility_preferences'
        AND policyname = 'Users manage own accessibility preferences'
    ) THEN
        CREATE POLICY "Users manage own accessibility preferences"
            ON accessibility_preferences FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies: audio_captions
-- Captions are publicly readable by authenticated users (read-only)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'audio_captions'
        AND policyname = 'Captions readable by authenticated users'
    ) THEN
        CREATE POLICY "Captions readable by authenticated users"
            ON audio_captions FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- RLS Policies: localized_strings
-- Strings are publicly readable (no authentication required)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'localized_strings'
        AND policyname = 'Localized strings readable by all'
    ) THEN
        CREATE POLICY "Localized strings readable by all"
            ON localized_strings FOR SELECT
            USING (true);
    END IF;
END $$;

-- RLS Policies: sign_language_videos
-- Videos are readable by authenticated users (public content)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sign_language_videos'
        AND policyname = 'Sign language videos readable by authenticated users'
    ) THEN
        CREATE POLICY "Sign language videos readable by authenticated users"
            ON sign_language_videos FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- RLS Policies: accessibility_feedback
-- Users can submit feedback (authenticated or anonymous)
-- Users can only view their own feedback
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'accessibility_feedback'
        AND policyname = 'Users can submit accessibility feedback'
    ) THEN
        CREATE POLICY "Users can submit accessibility feedback"
            ON accessibility_feedback FOR INSERT
            WITH CHECK (auth.uid() IS NULL OR auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'accessibility_feedback'
        AND policyname = 'Users can view own accessibility feedback'
    ) THEN
        CREATE POLICY "Users can view own accessibility feedback"
            ON accessibility_feedback FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies: accessibility_audits
-- Admin-only table (no public access)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'accessibility_audits'
        AND policyname = 'Accessibility audits - admin only'
    ) THEN
        CREATE POLICY "Accessibility audits - admin only"
            ON accessibility_audits FOR ALL
            USING (false); -- Completely deny public access; admins bypass RLS
    END IF;
END $$;
