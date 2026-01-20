-- AI Coaching Modes Feature Migration
-- Feature: Reflect / Plan / Reframe coaching modes
-- Created: 2026-01-20

-- ============================================
-- Conversation Modes Table
-- ============================================
CREATE TABLE IF NOT EXISTS conversation_modes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    mode TEXT NOT NULL DEFAULT 'reflect',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(conversation_id)
);

-- RLS: User can only modify their own conversation modes
ALTER TABLE conversation_modes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own conversation modes"
    ON conversation_modes FOR ALL
    USING (auth.uid() IN (
        SELECT user_id FROM conversations WHERE id = conversation_id
    ));

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_conversation_modes_conversation_id ON conversation_modes(conversation_id);

-- ============================================
-- Thought Records Table (for Reframe mode)
-- Check if table exists, if not create it
-- ============================================
DO $body$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'thought_records') THEN
        CREATE TABLE thought_records (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            situation TEXT,
            automatic_thought TEXT,
            emotions JSONB NOT NULL DEFAULT '[]'::jsonb,
            evidence_for TEXT[] NOT NULL DEFAULT '{}',
            evidence_against TEXT[] NOT NULL DEFAULT '{}',
            alternative_thought TEXT,
            experiment_hypothesis TEXT,
            experiment_action TEXT,
            experiment_predicted_outcome TEXT,
            completed_fields TEXT[] NOT NULL DEFAULT '{}',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        -- RLS for thought records
        ALTER TABLE thought_records ENABLE ROW LEVEL SECURITY;

        CREATE POLICY "Users manage own thought records"
            ON thought_records FOR ALL
            USING (auth.uid() = user_id);

        -- Index for user's thought records
        CREATE INDEX IF NOT EXISTS idx_thought_records_user_id ON thought_records(user_id);
        CREATE INDEX IF NOT EXISTS idx_thought_records_created_at ON thought_records(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_thought_records_conversation_id ON thought_records(conversation_id);

        -- Updated_at trigger
        CREATE OR REPLACE FUNCTION update_thought_record_updated_at()
        RETURNS TRIGGER LANGUAGE plpgsql
        AS $$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        $$;

        CREATE TRIGGER trigger_thought_record_updated_at
            BEFORE UPDATE ON thought_records
            FOR EACH ROW
            EXECUTE FUNCTION update_thought_record_updated_at();
    END IF;
END;
$body$;

-- If table already exists, ensure required columns exist
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'thought_records') THEN
        -- Add columns if they don't exist
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thought_records' AND column_name = 'conversation_id') THEN
            ALTER TABLE thought_records ADD COLUMN conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thought_records' AND column_name = 'experiment_hypothesis') THEN
            ALTER TABLE thought_records ADD COLUMN experiment_hypothesis TEXT;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thought_records' AND column_name = 'experiment_action') THEN
            ALTER TABLE thought_records ADD COLUMN experiment_action TEXT;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thought_records' AND column_name = 'experiment_predicted_outcome') THEN
            ALTER TABLE thought_records ADD COLUMN experiment_predicted_outcome TEXT;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'thought_records' AND column_name = 'completed_fields') THEN
            ALTER TABLE thought_records ADD COLUMN completed_fields TEXT[] NOT NULL DEFAULT '{}';
        END IF;

        -- Ensure indexes exist
        CREATE INDEX IF NOT EXISTS idx_thought_records_user_id ON thought_records(user_id);
        CREATE INDEX IF NOT EXISTS idx_thought_records_created_at ON thought_records(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_thought_records_conversation_id ON thought_records(conversation_id);

        -- Ensure trigger exists
        IF NOT EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trigger_thought_record_updated_at') THEN
            CREATE OR REPLACE FUNCTION update_thought_record_updated_at()
            RETURNS TRIGGER LANGUAGE plpgsql
            AS $$
            BEGIN
                NEW.updated_at = NOW();
                RETURN NEW;
            END;
            $$;

            CREATE TRIGGER trigger_thought_record_updated_at
                BEFORE UPDATE ON thought_records
                FOR EACH ROW
                EXECUTE FUNCTION update_thought_record_updated_at();
        END IF;
    END IF;
END;
$body$;

-- ============================================
-- AI Suggested Quest Templates Table (for Plan mode)
-- ============================================
CREATE TABLE IF NOT EXISTS ai_suggested_quests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    step_id TEXT NOT NULL,
    step_title TEXT NOT NULL,
    step_description TEXT,
    duration_min INTEGER NOT NULL,
    category TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'medium',
    was_selected BOOLEAN NOT NULL DEFAULT FALSE,
    was_scheduled BOOLEAN NOT NULL DEFAULT FALSE,
    scheduled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS for AI suggested quests
ALTER TABLE ai_suggested_quests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own AI suggested quests"
    ON ai_suggested_quests FOR ALL
    USING (auth.uid() = user_id);

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_ai_suggested_quests_user_id ON ai_suggested_quests(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_suggested_quests_conversation_id ON ai_suggested_quests(conversation_id);
CREATE INDEX IF NOT EXISTS idx_ai_suggested_quests_created_at ON ai_suggested_quests(created_at DESC);
