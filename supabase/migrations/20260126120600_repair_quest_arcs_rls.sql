-- Repair migration: Ensure quest_arcs tables have proper RLS policies
-- These are idempotent (safe to run multiple times)

-- Ensure RLS is enabled
ALTER TABLE IF EXISTS quest_arcs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS quest_arc_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS user_quest_arcs ENABLE ROW LEVEL SECURITY;

-- Quest Arcs policies (read-only for authenticated users)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view active arcs' AND tablename = 'quest_arcs') THEN
        CREATE POLICY "Users can view active arcs" ON quest_arcs
            FOR SELECT TO authenticated
            USING (is_active = true);
    END IF;
END $$;

-- Quest Arc Steps policies (read-only for authenticated users)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view arc steps' AND tablename = 'quest_arc_steps') THEN
        CREATE POLICY "Users can view arc steps" ON quest_arc_steps
            FOR SELECT TO authenticated
            USING (true);
    END IF;
END $$;

-- User Quest Arcs policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own arc enrollments' AND tablename = 'user_quest_arcs') THEN
        CREATE POLICY "Users can view own arc enrollments" ON user_quest_arcs
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can start arcs' AND tablename = 'user_quest_arcs') THEN
        CREATE POLICY "Users can start arcs" ON user_quest_arcs
            FOR INSERT TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own arc enrollments' AND tablename = 'user_quest_arcs') THEN
        CREATE POLICY "Users can update own arc enrollments" ON user_quest_arcs
            FOR UPDATE TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;
