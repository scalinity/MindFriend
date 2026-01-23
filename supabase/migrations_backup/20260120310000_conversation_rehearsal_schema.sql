-- ================================================
-- Migration: Conversation Rehearsal Studio Schema
-- Created: 2026-01-20
-- Description: Tables, indexes, and RLS policies for conversation rehearsal feature
-- ================================================

-- ================================================
-- 1. Core Tables
-- ================================================

-- Pre-built scenario templates (managed by content team)
CREATE TABLE IF NOT EXISTS conversation_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN ('work', 'relationships', 'social', 'family', 'health', 'financial')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    situation_context TEXT NOT NULL,
    other_party_role TEXT NOT NULL,  -- e.g., "manager", "partner", "friend"
    other_party_personality TEXT,    -- e.g., "defensive", "supportive", "neutral"
    key_points_to_convey TEXT[] NOT NULL,
    desired_outcome TEXT NOT NULL,
    difficulty_level TEXT DEFAULT 'medium' CHECK (difficulty_level IN ('easy', 'medium', 'advanced')),
    estimated_minutes INTEGER DEFAULT 10 CHECK (estimated_minutes BETWEEN 5 AND 30),
    tips_for_user TEXT[],
    tags TEXT[] DEFAULT '{}',
    is_premium BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Custom scenarios created by users
CREATE TABLE IF NOT EXISTS custom_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (length(trim(title)) >= 3 AND length(trim(title)) <= 100),
    other_party_role TEXT NOT NULL CHECK (length(trim(other_party_role)) >= 3),
    situation_summary TEXT NOT NULL CHECK (length(trim(situation_summary)) BETWEEN 10 AND 500),
    key_points TEXT[] NOT NULL CHECK (array_length(key_points, 1) BETWEEN 1 AND 5),
    desired_outcome TEXT NOT NULL CHECK (length(trim(desired_outcome)) BETWEEN 10 AND 240),
    situation_type TEXT DEFAULT 'other' CHECK (situation_type IN ('conflict', 'feedback', 'boundary', 'request', 'other')),
    context_details JSONB,
    is_public BOOLEAN DEFAULT FALSE,  -- Future: allow sharing
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ
);

-- User rehearsal sessions
CREATE TABLE IF NOT EXISTS rehearsal_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scenario_id UUID REFERENCES conversation_scenarios(id) ON DELETE SET NULL,
    custom_scenario_id UUID REFERENCES custom_scenarios(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned', 'crisis_ended')),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    confidence_rating INTEGER CHECK (confidence_rating BETWEEN 1 AND 5),
    notes TEXT CHECK (length(notes) <= 500),
    transcript TEXT NOT NULL DEFAULT '',  -- Encrypted at rest via Supabase config
    feedback_summary TEXT,
    communication_style TEXT CHECK (communication_style IN ('defensive', 'aggressive', 'passive', 'assertive', 'empathetic', 'collaborative')),
    key_points_covered INTEGER DEFAULT 0,
    total_exchanges INTEGER DEFAULT 0,
    total_duration_seconds INTEGER,
    is_bookmarked BOOLEAN DEFAULT FALSE,
    is_saved BOOLEAN DEFAULT FALSE,  -- Opt-in for history
    auto_save_key TEXT,  -- For recovery
    crisis_detected BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT scenario_or_custom CHECK (
        (scenario_id IS NOT NULL AND custom_scenario_id IS NULL) OR
        (scenario_id IS NULL AND custom_scenario_id IS NOT NULL)
    )
);

-- Bookmarked messages from rehearsals
CREATE TABLE IF NOT EXISTS rehearsal_bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES rehearsal_sessions(id) ON DELETE CASCADE,
    original_message TEXT NOT NULL,
    rewritten_message TEXT,  -- If tone rewrite was used
    tone_type TEXT CHECK (tone_type IN ('more_direct', 'more_gentle', 'more_assertive', 'more_collaborative')),
    scenario_context TEXT NOT NULL,  -- Denormalized for quick reference
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(session_id, original_message)  -- Prevent duplicate bookmarks
);

-- Rehearsal feedback (per-message and session summary)
CREATE TABLE IF NOT EXISTS rehearsal_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES rehearsal_sessions(id) ON DELETE CASCADE,
    message_id UUID,  -- References messages table if message-level feedback
    feedback_type TEXT NOT NULL CHECK (feedback_type IN ('per_message', 'session_summary')),
    overall_score DECIMAL(3,1) CHECK (overall_score BETWEEN 1.0 AND 10.0),
    tone TEXT CHECK (tone IN ('defensive', 'aggressive', 'passive', 'assertive', 'empathetic', 'collaborative')),
    clarity_score DECIMAL(3,1) CHECK (clarity_score BETWEEN 1.0 AND 10.0),
    empathy_score DECIMAL(3,1) CHECK (empathy_score BETWEEN 1.0 AND 10.0),
    assertiveness_score DECIMAL(3,1) CHECK (assertiveness_score BETWEEN 1.0 AND 10.0),
    strengths TEXT[],  -- Array of positive observations
    improvements TEXT[],  -- Array of suggestions
    suggested_rephrase TEXT,  -- AI-generated alternative (premium)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Communication style patterns (for feedback generation)
CREATE TABLE IF NOT EXISTS communication_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_type TEXT NOT NULL UNIQUE,  -- e.g., "passive", "aggressive", "assertive"
    keywords TEXT[] NOT NULL,
    example_phrases TEXT[],
    feedback_message TEXT NOT NULL,
    improvement_suggestion TEXT NOT NULL,
    positive_indicators TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================
-- 2. Indexes for Performance
-- ================================================

-- conversation_scenarios indexes
CREATE INDEX IF NOT EXISTS idx_scenarios_category ON conversation_scenarios(category) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_scenarios_premium ON conversation_scenarios(is_premium) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_scenarios_tags ON conversation_scenarios USING GIN(tags);

-- custom_scenarios indexes
CREATE INDEX IF NOT EXISTS idx_custom_scenarios_user ON custom_scenarios(user_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_custom_scenarios_cleanup ON custom_scenarios(deleted_at, archived_at);

-- rehearsal_sessions indexes
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_user ON rehearsal_sessions(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_scenario ON rehearsal_sessions(scenario_id);
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_custom_scenario ON rehearsal_sessions(custom_scenario_id);
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_saved ON rehearsal_sessions(user_id, is_saved) WHERE is_saved = TRUE;
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_auto_save ON rehearsal_sessions(auto_save_key) WHERE completed_at IS NULL;

-- rehearsal_bookmarks indexes
CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON rehearsal_bookmarks(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_session ON rehearsal_bookmarks(session_id);

-- rehearsal_feedback indexes
CREATE INDEX IF NOT EXISTS idx_rehearsal_feedback_session ON rehearsal_feedback(session_id);
CREATE INDEX IF NOT EXISTS idx_rehearsal_feedback_message ON rehearsal_feedback(message_id);

-- ================================================
-- 3. Extend Existing Tables
-- ================================================

-- Add rehearsal support to messages table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'messages' AND column_name = 'rehearsal_session_id'
    ) THEN
        ALTER TABLE messages ADD COLUMN rehearsal_session_id UUID REFERENCES rehearsal_sessions(id) ON DELETE CASCADE;
        ALTER TABLE messages ADD COLUMN is_ai_role_simulation BOOLEAN DEFAULT false;
        CREATE INDEX idx_messages_rehearsal_session ON messages(rehearsal_session_id);
    END IF;
END $$;

-- Add rehearsal quota tracking to user_settings
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_settings' AND column_name = 'rehearsals_used_this_week'
    ) THEN
        ALTER TABLE user_settings ADD COLUMN rehearsals_used_this_week INT DEFAULT 0;
        ALTER TABLE user_settings ADD COLUMN rehearsals_quota_reset_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Add rehearsal achievement tracking to user_badges
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'user_badges' AND column_name = 'rehearsal_scenario_id'
    ) THEN
        ALTER TABLE user_badges ADD COLUMN rehearsal_scenario_id UUID REFERENCES conversation_scenarios(id);
    END IF;
END $$;

-- ================================================
-- 4. Row Level Security Policies
-- ================================================

-- conversation_scenarios RLS
ALTER TABLE conversation_scenarios ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'conversation_scenarios' AND policyname = 'Authenticated users can read active scenarios'
    ) THEN
        CREATE POLICY "Authenticated users can read active scenarios"
            ON conversation_scenarios FOR SELECT
            TO authenticated
            USING (is_active = TRUE);
    END IF;
END $$;

-- custom_scenarios RLS
ALTER TABLE custom_scenarios ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'custom_scenarios' AND policyname = 'Users manage own custom scenarios'
    ) THEN
        CREATE POLICY "Users manage own custom scenarios"
            ON custom_scenarios FOR ALL
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- rehearsal_sessions RLS
ALTER TABLE rehearsal_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'rehearsal_sessions' AND policyname = 'Users manage own rehearsal sessions'
    ) THEN
        CREATE POLICY "Users manage own rehearsal sessions"
            ON rehearsal_sessions FOR ALL
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- rehearsal_bookmarks RLS
ALTER TABLE rehearsal_bookmarks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'rehearsal_bookmarks' AND policyname = 'Users manage own bookmarks'
    ) THEN
        CREATE POLICY "Users manage own bookmarks"
            ON rehearsal_bookmarks FOR ALL
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- rehearsal_feedback RLS
ALTER TABLE rehearsal_feedback ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'rehearsal_feedback' AND policyname = 'Users read feedback for own sessions'
    ) THEN
        CREATE POLICY "Users read feedback for own sessions"
            ON rehearsal_feedback FOR SELECT
            TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM rehearsal_sessions rs
                    WHERE rs.id = rehearsal_feedback.session_id
                    AND rs.user_id = auth.uid()
                )
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'rehearsal_feedback' AND policyname = 'Service role inserts feedback'
    ) THEN
        CREATE POLICY "Service role inserts feedback"
            ON rehearsal_feedback FOR INSERT
            WITH CHECK (true);  -- Edge Function uses service role
    END IF;
END $$;

-- communication_patterns RLS (read-only for authenticated users)
ALTER TABLE communication_patterns ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'communication_patterns' AND policyname = 'Authenticated users can read patterns'
    ) THEN
        CREATE POLICY "Authenticated users can read patterns"
            ON communication_patterns FOR SELECT
            TO authenticated
            USING (TRUE);
    END IF;
END $$;

-- ================================================
-- 5. Seed Data: Communication Patterns
-- ================================================

INSERT INTO communication_patterns (pattern_type, keywords, example_phrases, feedback_message, improvement_suggestion, positive_indicators)
VALUES
('assertive',
 ARRAY['I think', 'I feel', 'I would like', 'I need', 'I want', 'I believe'],
 ARRAY['I feel uncomfortable when...', 'I would like to discuss...', 'I need your support with...'],
 'Your communication is clear and direct while remaining respectful.',
 'Keep using "I" statements to express your needs clearly.',
 ARRAY['specific', 'direct', 'respectful', 'clear']),

('passive',
 ARRAY['maybe', 'sort of', 'if that''s okay', 'I guess', 'whatever you think', 'I don''t mind'],
 ARRAY['Maybe we could...', 'If that''s okay with you...', 'I guess that works...'],
 'Your tone is considerate, but you might not be getting your needs across clearly.',
 'Try stating what you want more directly: "I would like..." instead of "Maybe we could..."',
 ARRAY['polite', 'considerate', 'accommodating']),

('aggressive',
 ARRAY['you always', 'you never', 'you should', 'you have to', 'you must', 'you need to'],
 ARRAY['You always do this!', 'You never listen!', 'You should have known...'],
 'This phrasing might come across as accusatory or confrontational.',
 'Try reframing with "I" statements: "I feel frustrated when..." instead of "You always..."',
 ARRAY[]::TEXT[]),

('collaborative',
 ARRAY['we could', 'what if we', 'let''s try', 'together', 'our', 'how can we'],
 ARRAY['What if we tried...', 'Let''s work together on...', 'How can we both...'],
 'Your approach invites cooperation and shared problem-solving.',
 'Continue fostering partnership with inclusive language.',
 ARRAY['inclusive', 'solution-focused', 'respectful', 'team-oriented']),

('empathetic',
 ARRAY['I understand', 'I hear you', 'that must be', 'I can see', 'I appreciate'],
 ARRAY['I understand how that feels...', 'I hear what you''re saying...', 'That must be difficult...'],
 'You''re showing good emotional awareness and validation.',
 'Keep acknowledging the other person''s feelings while also expressing your needs.',
 ARRAY['validating', 'understanding', 'compassionate', 'listening']),

('defensive',
 ARRAY['but I', 'that''s not fair', 'I didn''t', 'it''s not my fault', 'you don''t understand'],
 ARRAY['But I was just...', 'That''s not fair because...', 'You don''t understand what I meant...'],
 'Your response might come across as defensive rather than open to feedback.',
 'Try pausing before responding. Acknowledge their concern first, then explain your perspective.',
 ARRAY[]::TEXT[])
ON CONFLICT (pattern_type) DO NOTHING;

-- ================================================
-- 6. Triggers and Functions
-- ================================================

-- Update updated_at timestamp on record changes
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_conversation_scenarios_updated_at') THEN
        CREATE TRIGGER update_conversation_scenarios_updated_at
            BEFORE UPDATE ON conversation_scenarios
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_custom_scenarios_updated_at') THEN
        CREATE TRIGGER update_custom_scenarios_updated_at
            BEFORE UPDATE ON custom_scenarios
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_rehearsal_sessions_updated_at') THEN
        CREATE TRIGGER update_rehearsal_sessions_updated_at
            BEFORE UPDATE ON rehearsal_sessions
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- ================================================
-- 7. Comments for Documentation
-- ================================================

COMMENT ON TABLE conversation_scenarios IS 'Pre-built rehearsal scenario templates managed by content team';
COMMENT ON TABLE custom_scenarios IS 'User-created custom rehearsal scenarios';
COMMENT ON TABLE rehearsal_sessions IS 'Individual rehearsal practice sessions with AI simulation';
COMMENT ON TABLE rehearsal_bookmarks IS 'Effective messages bookmarked by users for future reference';
COMMENT ON TABLE rehearsal_feedback IS 'Communication feedback for rehearsal messages and sessions';
COMMENT ON TABLE communication_patterns IS 'Pattern definitions for NLP-based feedback classification';

COMMENT ON COLUMN conversation_scenarios.other_party_personality IS 'AI personality traits for role simulation (defensive, supportive, neutral, etc.)';
COMMENT ON COLUMN rehearsal_sessions.transcript IS 'Full conversation transcript (encrypted at rest)';
COMMENT ON COLUMN rehearsal_sessions.auto_save_key IS 'Recovery key for resuming interrupted sessions';
COMMENT ON COLUMN rehearsal_feedback.suggested_rephrase IS 'AI-generated tone rewrite (premium feature)';
