-- Coping Kits Schema Migration
-- Creates tables for coping kit templates, user preferences, progress tracking, and feedback

-- Drop existing tables if they exist (for clean re-creation)
DROP TABLE IF EXISTS kit_feedback CASCADE;
DROP TABLE IF EXISTS kit_progress CASCADE;
DROP TABLE IF EXISTS user_coping_kits CASCADE;
DROP TABLE IF EXISTS coping_kits CASCADE;

-- coping_kits: Template table for all available kits
CREATE TABLE IF NOT EXISTS coping_kits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    context_tag TEXT NOT NULL CHECK (context_tag IN ('anxiety', 'stress', 'sadness', 'sleep', 'focus', 'crisis')),
    steps JSONB NOT NULL,  -- Array of CopingKitStep
    estimated_minutes INT NOT NULL CHECK (estimated_minutes > 0),
    is_premium BOOLEAN NOT NULL DEFAULT false,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- user_coping_kits: User preferences (pinned kits, usage tracking)
CREATE TABLE IF NOT EXISTS user_coping_kits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    kit_id UUID NOT NULL REFERENCES coping_kits(id) ON DELETE CASCADE,
    pinned BOOLEAN NOT NULL DEFAULT false,
    pin_order INT NOT NULL DEFAULT 0,
    last_used_at TIMESTAMPTZ,
    total_uses INT NOT NULL DEFAULT 0,
    completed_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, kit_id)
);

-- kit_progress: Active session tracking (24-hour expiry)
CREATE TABLE IF NOT EXISTS kit_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    kit_id UUID NOT NULL REFERENCES coping_kits(id) ON DELETE CASCADE,
    current_step_index INT NOT NULL DEFAULT 0,
    step_results JSONB DEFAULT '[]'::jsonb,  -- Array of step completion data
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    UNIQUE(user_id, kit_id)
);

-- kit_feedback: Post-completion feedback
CREATE TABLE IF NOT EXISTS kit_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    kit_id UUID NOT NULL REFERENCES coping_kits(id) ON DELETE CASCADE,
    helpful BOOLEAN NOT NULL,
    comment TEXT,
    xp_granted INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_coping_kits_context ON coping_kits(context_tag, display_order);
CREATE INDEX IF NOT EXISTS idx_coping_kits_premium ON coping_kits(is_premium, display_order);
CREATE INDEX IF NOT EXISTS idx_user_coping_kits_user_pinned ON user_coping_kits(user_id, pinned DESC, pin_order);
CREATE INDEX IF NOT EXISTS idx_user_coping_kits_user_uses ON user_coping_kits(user_id, total_uses DESC);
CREATE INDEX IF NOT EXISTS idx_kit_progress_user_expiry ON kit_progress(user_id, expires_at);
CREATE INDEX IF NOT EXISTS idx_kit_feedback_user_kit ON kit_feedback(user_id, kit_id);

-- Row Level Security (RLS) Policies

-- coping_kits: Public read for authenticated users
ALTER TABLE coping_kits ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'coping_kits' AND policyname = 'Authenticated users can read coping kits'
    ) THEN
        CREATE POLICY "Authenticated users can read coping kits"
            ON coping_kits FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- user_coping_kits: User-only access
ALTER TABLE user_coping_kits ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'user_coping_kits' AND policyname = 'Users can view own preferences'
    ) THEN
        CREATE POLICY "Users can view own preferences"
            ON user_coping_kits FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'user_coping_kits' AND policyname = 'Users can insert own preferences'
    ) THEN
        CREATE POLICY "Users can insert own preferences"
            ON user_coping_kits FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'user_coping_kits' AND policyname = 'Users can update own preferences'
    ) THEN
        CREATE POLICY "Users can update own preferences"
            ON user_coping_kits FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- kit_progress: User-only access
ALTER TABLE kit_progress ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'kit_progress' AND policyname = 'Users can view own progress'
    ) THEN
        CREATE POLICY "Users can view own progress"
            ON kit_progress FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'kit_progress' AND policyname = 'Users can manage own progress'
    ) THEN
        CREATE POLICY "Users can manage own progress"
            ON kit_progress FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- kit_feedback: User-only access
ALTER TABLE kit_feedback ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'kit_feedback' AND policyname = 'Users can manage own feedback'
    ) THEN
        CREATE POLICY "Users can manage own feedback"
            ON kit_feedback FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;
