-- Values Compass & Decision Coach Database Schema
-- Created: 2026-01-20
-- Implements 6 tables with RLS policies for values discovery, decision analysis, and journaling

-- =============================================================================
-- Table 1: values_cards (predefined value library - 32 cards across 4 categories)
-- =============================================================================
CREATE TABLE IF NOT EXISTS values_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    value_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('personal', 'relationships', 'work', 'growth')),
    icon TEXT, -- SF Symbol name for iOS
    questions TEXT[], -- Reflection questions for this value
    examples TEXT[], -- Real-life examples
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Table 2: user_values (user's discovered values with rankings)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    values_data JSONB NOT NULL DEFAULT '{}'::jsonb, -- Full assessment results (see decisions.md for schema)
    top_values TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[], -- Top 5-8 value_keys
    custom_values TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[], -- User-defined values
    values_categories JSONB NOT NULL DEFAULT '{}'::jsonb, -- Category mapping (see decisions.md)
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Constraints
    CONSTRAINT top_values_max_length CHECK (array_length(top_values, 1) <= 8)
);

-- Index for fast user lookups
CREATE INDEX IF NOT EXISTS idx_user_values_user_id ON user_values(user_id);

-- =============================================================================
-- Table 3: user_decisions (decision analysis with values alignment)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    question TEXT NOT NULL CHECK (char_length(question) BETWEEN 10 AND 500), -- Decision question
    options JSONB NOT NULL DEFAULT '[]'::jsonb, -- Array of option objects (see decisions.md)
    relevant_values TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[], -- Which values relate to this decision
    analysis JSONB, -- AI-generated analysis (see decisions.md for schema)
    decision_made TEXT, -- Which option user chose (option ID or null if undecided)
    confidence_score FLOAT CHECK (confidence_score BETWEEN -1.0 AND 1.0), -- -1 (all conflict) to +1 (all align)
    outcome TEXT, -- How did it turn out? (user reflection after decision)
    reflection TEXT, -- User's thoughts on the decision
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ -- When user made final choice
);

-- Indexes for user queries and date filtering
CREATE INDEX IF NOT EXISTS idx_user_decisions_user_id ON user_decisions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_decisions_created_at ON user_decisions(created_at DESC);

-- =============================================================================
-- Table 4: values_journal (track values in action with gap analysis)
-- =============================================================================
CREATE TABLE IF NOT EXISTS values_journal (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    value_key TEXT NOT NULL, -- Which value was lived/conflicted
    entry_type TEXT NOT NULL CHECK (entry_type IN ('action', 'conflict', 'alignment', 'growth')),
    description TEXT NOT NULL CHECK (char_length(description) BETWEEN 1 AND 5000),
    impact_level INTEGER CHECK (impact_level BETWEEN 1 AND 5), -- Significance (1=small, 5=major)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for user queries and date-based analytics
CREATE INDEX IF NOT EXISTS idx_values_journal_user_id ON values_journal(user_id);
CREATE INDEX IF NOT EXISTS idx_values_journal_created_at ON values_journal(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_values_journal_value_key ON values_journal(value_key);

-- =============================================================================
-- Table 5: trade_off_scenarios (pre-defined conflict exercises)
-- =============================================================================
CREATE TABLE IF NOT EXISTS trade_off_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scenario_type TEXT NOT NULL, -- 'work_life', 'honesty_kindness', etc.
    scenario_text TEXT NOT NULL CHECK (char_length(scenario_text) BETWEEN 50 AND 1000),
    value_a TEXT NOT NULL, -- First conflicting value (value_key)
    value_b TEXT NOT NULL, -- Second conflicting value (value_key)
    questions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[], -- Reflection prompts
    example_resolution TEXT, -- Sample reasoning for learning
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================================================
-- Table 6: user_trade_offs (user's trade-off exercise history)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_trade_offs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    scenario_id UUID REFERENCES trade_off_scenarios(id) ON DELETE CASCADE NOT NULL,
    user_choice TEXT NOT NULL CHECK (user_choice IN ('value_a', 'value_b', 'both')), -- Which value they prioritized
    reasoning TEXT CHECK (char_length(reasoning) <= 2000), -- User's explanation
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for user lookups
CREATE INDEX IF NOT EXISTS idx_user_trade_offs_user_id ON user_trade_offs(user_id);

-- =============================================================================
-- Row Level Security (RLS) Policies
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE values_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE values_journal ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_off_scenarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_trade_offs ENABLE ROW LEVEL SECURITY;

-- values_cards: Read-only for all authenticated users (shared library)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'values_cards'
        AND policyname = 'values_cards_select_all'
    ) THEN
        CREATE POLICY values_cards_select_all ON values_cards
            FOR SELECT TO authenticated
            USING (true);
    END IF;
END $$;

-- user_values: Users can read/write only their own values
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_values'
        AND policyname = 'user_values_select_own'
    ) THEN
        CREATE POLICY user_values_select_own ON user_values
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_values'
        AND policyname = 'user_values_insert_own'
    ) THEN
        CREATE POLICY user_values_insert_own ON user_values
            FOR INSERT TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_values'
        AND policyname = 'user_values_update_own'
    ) THEN
        CREATE POLICY user_values_update_own ON user_values
            FOR UPDATE TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_values'
        AND policyname = 'user_values_delete_own'
    ) THEN
        CREATE POLICY user_values_delete_own ON user_values
            FOR DELETE TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- user_decisions: Users can read/write only their own decisions
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_decisions'
        AND policyname = 'user_decisions_select_own'
    ) THEN
        CREATE POLICY user_decisions_select_own ON user_decisions
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_decisions'
        AND policyname = 'user_decisions_insert_own'
    ) THEN
        CREATE POLICY user_decisions_insert_own ON user_decisions
            FOR INSERT TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_decisions'
        AND policyname = 'user_decisions_update_own'
    ) THEN
        CREATE POLICY user_decisions_update_own ON user_decisions
            FOR UPDATE TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_decisions'
        AND policyname = 'user_decisions_delete_own'
    ) THEN
        CREATE POLICY user_decisions_delete_own ON user_decisions
            FOR DELETE TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- values_journal: Users can read/write only their own journal entries
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'values_journal'
        AND policyname = 'values_journal_select_own'
    ) THEN
        CREATE POLICY values_journal_select_own ON values_journal
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'values_journal'
        AND policyname = 'values_journal_insert_own'
    ) THEN
        CREATE POLICY values_journal_insert_own ON values_journal
            FOR INSERT TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'values_journal'
        AND policyname = 'values_journal_update_own'
    ) THEN
        CREATE POLICY values_journal_update_own ON values_journal
            FOR UPDATE TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'values_journal'
        AND policyname = 'values_journal_delete_own'
    ) THEN
        CREATE POLICY values_journal_delete_own ON values_journal
            FOR DELETE TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- trade_off_scenarios: Read-only for all authenticated users (shared library)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'trade_off_scenarios'
        AND policyname = 'trade_off_scenarios_select_all'
    ) THEN
        CREATE POLICY trade_off_scenarios_select_all ON trade_off_scenarios
            FOR SELECT TO authenticated
            USING (true);
    END IF;
END $$;

-- user_trade_offs: Users can read/write only their own trade-off history
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_trade_offs'
        AND policyname = 'user_trade_offs_select_own'
    ) THEN
        CREATE POLICY user_trade_offs_select_own ON user_trade_offs
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_trade_offs'
        AND policyname = 'user_trade_offs_insert_own'
    ) THEN
        CREATE POLICY user_trade_offs_insert_own ON user_trade_offs
            FOR INSERT TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_trade_offs'
        AND policyname = 'user_trade_offs_update_own'
    ) THEN
        CREATE POLICY user_trade_offs_update_own ON user_trade_offs
            FOR UPDATE TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_trade_offs'
        AND policyname = 'user_trade_offs_delete_own'
    ) THEN
        CREATE POLICY user_trade_offs_delete_own ON user_trade_offs
            FOR DELETE TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- Comments for documentation
-- =============================================================================

COMMENT ON TABLE values_cards IS 'Predefined library of 32 values across 4 categories (personal, relationships, work, growth)';
COMMENT ON TABLE user_values IS 'User''s discovered values from 3-phase assessment with top 5-8 rankings';
COMMENT ON TABLE user_decisions IS 'User decisions with AI-powered values alignment analysis';
COMMENT ON TABLE values_journal IS 'User journal tracking values in action with gap analysis';
COMMENT ON TABLE trade_off_scenarios IS 'Pre-defined scenarios for practicing values conflict resolution';
COMMENT ON TABLE user_trade_offs IS 'User''s trade-off exercise history with reasoning';

COMMENT ON COLUMN user_values.values_data IS 'JSONB schema: {phase1_selections, phase2_rankings, phase3_confirmed, scores, custom_definitions} - see docs/decisions.md';
COMMENT ON COLUMN user_values.values_categories IS 'JSONB schema: {personal: [...], relationships: [...], work: [...], growth: [...]} - see docs/decisions.md';
COMMENT ON COLUMN user_decisions.options IS 'JSONB schema: [{id, label, user_notes}, ...] - see docs/decisions.md';
COMMENT ON COLUMN user_decisions.analysis IS 'JSONB schema: {opt1: {aligned_values, conflicting_values}, confidence_score, recommendation} - see docs/decisions.md';
