-- Sensory Regulation Toolkit: Row Level Security Policies
-- Purpose: Enforce user-level data isolation for all sensory tables

-- Enable RLS on all tables
ALTER TABLE sensory_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensory_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensory_settings ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- sensory_sessions policies
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sensory_sessions'
        AND policyname = 'Users read own sessions'
    ) THEN
        CREATE POLICY "Users read own sessions" ON sensory_sessions
            FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sensory_sessions'
        AND policyname = 'Users insert own sessions'
    ) THEN
        CREATE POLICY "Users insert own sessions" ON sensory_sessions
            FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sensory_sessions'
        AND policyname = 'Users update own sessions'
    ) THEN
        CREATE POLICY "Users update own sessions" ON sensory_sessions
            FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sensory_sessions'
        AND policyname = 'Service role full access'
    ) THEN
        CREATE POLICY "Service role full access" ON sensory_sessions
            FOR ALL
            USING (auth.jwt()->>'role' = 'service_role');
    END IF;
END $$;

-- =============================================================================
-- sensory_favorites policies
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sensory_favorites'
        AND policyname = 'Users manage own favorites'
    ) THEN
        CREATE POLICY "Users manage own favorites" ON sensory_favorites
            FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- sensory_settings policies
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'sensory_settings'
        AND policyname = 'Users manage own settings'
    ) THEN
        CREATE POLICY "Users manage own settings" ON sensory_settings
            FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Comments for documentation
COMMENT ON POLICY "Users read own sessions" ON sensory_sessions IS 'Allow users to read their own sensory session records';
COMMENT ON POLICY "Users insert own sessions" ON sensory_sessions IS 'Allow users to create sensory sessions for themselves';
COMMENT ON POLICY "Users update own sessions" ON sensory_sessions IS 'Allow users to update their own session status (pause/complete)';
COMMENT ON POLICY "Users manage own favorites" ON sensory_favorites IS 'Allow users to add/remove their favorite patterns';
COMMENT ON POLICY "Users manage own settings" ON sensory_settings IS 'Allow users to modify their sensory toolkit preferences';
