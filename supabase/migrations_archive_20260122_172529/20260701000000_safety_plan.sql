-- Safety Plan Feature Migration
-- Feature: Personal Safety Plan (user-authored, offline-friendly)
-- Created: 2026-01-20

-- ============================================
-- Safety Plans Table (JSONB payload for MVP flexibility)
-- ============================================
CREATE TABLE IF NOT EXISTS safety_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    version INTEGER NOT NULL DEFAULT 1,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    allow_ai_reference BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT one_plan_per_user UNIQUE (user_id)
);

-- Enable RLS
ALTER TABLE safety_plans ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'safety_plans'
          AND policyname = 'Users can select own safety plan'
    ) THEN
        CREATE POLICY "Users can select own safety plan"
            ON safety_plans FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'safety_plans'
          AND policyname = 'Users can insert own safety plan'
    ) THEN
        CREATE POLICY "Users can insert own safety plan"
            ON safety_plans FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'safety_plans'
          AND policyname = 'Users can update own safety plan'
    ) THEN
        CREATE POLICY "Users can update own safety plan"
            ON safety_plans FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'safety_plans'
          AND policyname = 'Users can delete own safety plan'
    ) THEN
        CREATE POLICY "Users can delete own safety plan"
            ON safety_plans FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Index for fast user lookup
CREATE INDEX IF NOT EXISTS idx_safety_plans_user_id ON safety_plans(user_id);

-- Updated_at trigger for versioning
CREATE OR REPLACE FUNCTION update_safety_plan_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version = OLD.version + 1;
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_safety_plan_version
    BEFORE UPDATE ON safety_plans
    FOR EACH ROW
    EXECUTE FUNCTION update_safety_plan_version();

-- ============================================
-- Safety Plan Cache Table (for offline access)
-- Note: This is client-side cached, server just stores for sync
-- ============================================
CREATE TABLE IF NOT EXISTS safety_plan_cache (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    cached_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days')
);

-- RLS for cache
ALTER TABLE safety_plan_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'safety_plan_cache'
          AND policyname = 'Users can manage own safety plan cache'
    ) THEN
        CREATE POLICY "Users can manage own safety plan cache"
            ON safety_plan_cache FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Index for cache expiration queries
CREATE INDEX IF NOT EXISTS idx_safety_plan_cache_expires ON safety_plan_cache(expires_at);
