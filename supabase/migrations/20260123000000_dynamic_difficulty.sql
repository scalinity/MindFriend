-- =====================================================
-- Migration: Dynamic Difficulty Adjustment (F005)
-- Description: Capacity calculation, manual overrides, difficulty mapping
-- Author: MindFriend Dev Team
-- Date: 2026-01-23
-- =====================================================

-- Table: user_capacity
-- Stores calculated capacity scores with expiration
CREATE TABLE IF NOT EXISTS user_capacity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    score INT NOT NULL CHECK (score BETWEEN 0 AND 100),
    level TEXT NOT NULL CHECK (level IN ('low', 'moderate', 'high')),
    components JSONB NOT NULL,
    local_date DATE NOT NULL,
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    has_override BOOLEAN NOT NULL DEFAULT false,
    previous_score INT CHECK (previous_score BETWEEN 0 AND 100),
    UNIQUE(user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_user_capacity_expires ON user_capacity(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_capacity_user_date ON user_capacity(user_id, local_date);
CREATE INDEX IF NOT EXISTS idx_capacity_overrides_user_active ON capacity_overrides(user_id, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_capacity_rate_limits_user ON capacity_rate_limits(user_id);

-- SECURITY: Add rate limiting table for capacity calculation endpoint
CREATE TABLE IF NOT EXISTS capacity_rate_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    request_count INT NOT NULL DEFAULT 0,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

COMMENT ON TABLE user_capacity IS 'Stores user capacity scores with midnight expiration';
COMMENT ON COLUMN user_capacity.components IS 'JSON breakdown of sleep/mood/streak component scores';
COMMENT ON COLUMN user_capacity.expires_at IS 'Cache expiration timestamp (midnight in user timezone)';

-- 2. Manual capacity overrides
CREATE TABLE IF NOT EXISTS capacity_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    override_level TEXT NOT NULL CHECK (override_level IN ('rest', 'normal', 'challenge')),
    -- Maps to: rest=25, normal=50, challenge=75

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,

    -- Only one active override per user (enforced by partial unique index)
    CONSTRAINT chk_expires_future CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_capacity_overrides_active_user
    ON capacity_overrides(user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_capacity_overrides_expires
    ON capacity_overrides(expires_at) WHERE is_active = true;

COMMENT ON TABLE capacity_overrides IS 'User-initiated manual difficulty overrides (F005)';
COMMENT ON CONSTRAINT chk_expires_future ON capacity_overrides IS 'Ensure expiration is in the future';

-- 3. Quest difficulty mapping (optional, for future customization)
CREATE TABLE IF NOT EXISTS quest_difficulty_mapping (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capacity_level TEXT NOT NULL CHECK (capacity_level IN ('low', 'moderate', 'high')),
    quest_type TEXT NOT NULL, -- e.g., 'gratitude', 'movement', 'mindfulness', 'default'

    difficulty_multiplier NUMERIC(3,2) NOT NULL CHECK (difficulty_multiplier > 0 AND difficulty_multiplier <= 2.0),
    -- Examples: 0.5 (easier), 1.0 (normal), 1.25 (harder)

    recommended BOOLEAN NOT NULL DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(capacity_level, quest_type)
);

-- Seed default multipliers (MVP: simple 3-tier system)
INSERT INTO quest_difficulty_mapping (capacity_level, quest_type, difficulty_multiplier, recommended) VALUES
    ('low', 'default', 0.5, true),
    ('moderate', 'default', 1.0, true),
    ('high', 'default', 1.25, true)
ON CONFLICT (capacity_level, quest_type) DO NOTHING;

COMMENT ON TABLE quest_difficulty_mapping IS 'Quest difficulty multipliers by capacity level (F005)';
COMMENT ON COLUMN quest_difficulty_mapping.difficulty_multiplier IS 'Duration/intensity scaling factor';

-- 4. Add difficulty_level to exercises table (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'exercises'
          AND column_name = 'difficulty_level'
    ) THEN
        ALTER TABLE exercises
        ADD COLUMN difficulty_level TEXT CHECK (difficulty_level IN ('beginner', 'intermediate', 'advanced'));

        -- Default all existing exercises to 'intermediate'
        UPDATE exercises SET difficulty_level = 'intermediate' WHERE difficulty_level IS NULL;

        RAISE NOTICE 'Added difficulty_level column to exercises table';
    ELSE
        RAISE NOTICE 'difficulty_level column already exists on exercises table';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_exercises_difficulty ON exercises(difficulty_level) WHERE difficulty_level IS NOT NULL;

-- =====================================================
-- Row Level Security Policies
-- =====================================================

ALTER TABLE user_capacity ENABLE ROW LEVEL SECURITY;
ALTER TABLE capacity_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_difficulty_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE capacity_rate_limits ENABLE ROW LEVEL SECURITY;

-- Conditional policy creation (idempotent)
DO $$
BEGIN
    -- user_capacity policies
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'user_capacity' AND policyname = 'Users can read own capacity'
    ) THEN
        CREATE POLICY "Users can read own capacity"
            ON user_capacity FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'user_capacity' AND policyname = 'Service role can write capacity'
    ) THEN
        CREATE POLICY "Service role can write capacity"
            ON user_capacity FOR ALL
            USING (auth.jwt()->>'role' = 'service_role');
    END IF;

    -- capacity_overrides policies
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capacity_overrides' AND policyname = 'Users can manage own overrides'
    ) THEN
        CREATE POLICY "Users can manage own overrides"
            ON capacity_overrides FOR ALL
            USING (auth.uid() = user_id);
    END IF;

    -- quest_difficulty_mapping policies (read-only for users)
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'quest_difficulty_mapping' AND policyname = 'Anyone can read difficulty mappings'
    ) THEN
        CREATE POLICY "Anyone can read difficulty mappings"
            ON quest_difficulty_mapping FOR SELECT
            USING (true);
    END IF;

    -- capacity_rate_limits policies
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capacity_rate_limits' AND policyname = 'Users can read own rate limits'
    ) THEN
        CREATE POLICY "Users can read own rate limits"
            ON capacity_rate_limits FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capacity_rate_limits' AND policyname = 'Service role can manage rate limits'
    ) THEN
        CREATE POLICY "Service role can manage rate limits"
            ON capacity_rate_limits FOR ALL
            USING (auth.jwt()->>'role' = 'service_role');
    END IF;
END $$;

-- =====================================================
-- Maintenance Functions
-- =====================================================

-- Cleanup Function: Delete capacity records older than 30 days
-- SECURITY FIX: Added search_path protection to prevent SQL injection
CREATE OR REPLACE FUNCTION cleanup_old_capacity()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM user_capacity
    WHERE calculated_at < now() - INTERVAL '30 days';
END;
$$;

COMMENT ON FUNCTION cleanup_old_capacity() IS 'Deletes capacity records older than 30 days (runs daily at 3 AM UTC)';

-- Schedule cleanup via pg_cron (requires pg_cron extension)
-- Run daily at 3 AM UTC
-- Note: Ensure pg_cron is enabled in your Supabase project
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'cleanup-old-capacity',
            '0 3 * * *',
            'SELECT cleanup_old_capacity()'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Ignore if pg_cron not available
        NULL;
END $$;

-- Grant necessary permissions
GRANT SELECT ON user_capacity TO authenticated;
GRANT SELECT, INSERT, UPDATE ON capacity_overrides TO authenticated;
GRANT SELECT ON quest_difficulty_mapping TO authenticated;
GRANT SELECT ON capacity_rate_limits TO authenticated;

-- =====================================================
-- Grants (ensure service role can write)
-- =====================================================

GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON user_capacity TO service_role;
GRANT ALL ON capacity_overrides TO service_role;
GRANT SELECT ON quest_difficulty_mapping TO service_role;
GRANT SELECT ON capacity_rate_limits TO service_role;
