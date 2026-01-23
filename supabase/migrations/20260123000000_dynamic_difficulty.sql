-- =====================================================
-- Dynamic Difficulty Adjustment (F005) - MVP Schema
-- Created: 2026-01-23
-- Purpose: User capacity scoring, manual overrides, quest difficulty mapping
-- =====================================================

-- 1. User capacity scores (calculation results)
CREATE TABLE IF NOT EXISTS user_capacity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Capacity metrics
    score INT NOT NULL CHECK (score BETWEEN 0 AND 100),
    level TEXT NOT NULL CHECK (level IN ('low', 'moderate', 'high')),

    -- Component breakdown (JSONB for flexibility)
    components JSONB NOT NULL,
    -- Structure: {
    --   "sleep": {"score": 75, "weight": 0.35, "contribution": 26.25},
    --   "mood": {"score": 60, "weight": 0.40, "contribution": 24.00},
    --   "streak": {"score": 80, "weight": 0.25, "contribution": 20.00}
    -- }

    -- Metadata
    local_date DATE NOT NULL, -- User's local date when calculated
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL, -- Midnight in user's timezone
    has_override BOOLEAN NOT NULL DEFAULT false,

    -- Smoothing state (for next calculation)
    previous_score INT CHECK (previous_score BETWEEN 0 AND 100),

    UNIQUE(user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_user_capacity_user_date ON user_capacity(user_id, local_date DESC);
CREATE INDEX IF NOT EXISTS idx_user_capacity_expires ON user_capacity(expires_at);

COMMENT ON TABLE user_capacity IS 'Daily capacity scores for dynamic difficulty adjustment (F005)';
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

-- user_capacity: Users read own, service role writes
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_capacity'
          AND policyname = 'Users read own capacity'
    ) THEN
        CREATE POLICY "Users read own capacity" ON user_capacity
            FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
        RAISE NOTICE 'Created RLS policy: Users read own capacity';
    ELSE
        RAISE NOTICE 'RLS policy already exists: Users read own capacity';
    END IF;
END $$;

-- Service role writes via Edge Function (no INSERT/UPDATE policy for users)
-- Edge Function uses service_role key to bypass RLS for writes

-- capacity_overrides: Users manage own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'capacity_overrides'
          AND policyname = 'Users manage own overrides'
    ) THEN
        CREATE POLICY "Users manage own overrides" ON capacity_overrides
            FOR ALL
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
        RAISE NOTICE 'Created RLS policy: Users manage own overrides';
    ELSE
        RAISE NOTICE 'RLS policy already exists: Users manage own overrides';
    END IF;
END $$;

-- quest_difficulty_mapping: Public read, admin write
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'quest_difficulty_mapping'
          AND policyname = 'Public read difficulty mapping'
    ) THEN
        CREATE POLICY "Public read difficulty mapping" ON quest_difficulty_mapping
            FOR SELECT
            TO authenticated
            USING (true);
        RAISE NOTICE 'Created RLS policy: Public read difficulty mapping';
    ELSE
        RAISE NOTICE 'RLS policy already exists: Public read difficulty mapping';
    END IF;
END $$;

-- =====================================================
-- Maintenance Functions
-- =====================================================

CREATE OR REPLACE FUNCTION cleanup_expired_capacity()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Delete capacity records older than 30 days (archival)
    DELETE FROM user_capacity
    WHERE calculated_at < now() - INTERVAL '30 days';

    -- Deactivate expired overrides
    UPDATE capacity_overrides
    SET is_active = false
    WHERE is_active = true AND expires_at < now();

    RAISE NOTICE 'Cleaned up expired capacity data';
END;
$$;

COMMENT ON FUNCTION cleanup_expired_capacity() IS 'Cleanup old capacity data and expire overrides (run daily via cron)';

-- Schedule cleanup (if pg_cron extension is enabled)
-- Example: SELECT cron.schedule('cleanup-capacity', '0 2 * * *', 'SELECT cleanup_expired_capacity()');

-- =====================================================
-- Grants (ensure service role can write)
-- =====================================================

GRANT USAGE ON SCHEMA public TO service_role;
GRANT ALL ON user_capacity TO service_role;
GRANT ALL ON capacity_overrides TO service_role;
GRANT SELECT ON quest_difficulty_mapping TO service_role;
