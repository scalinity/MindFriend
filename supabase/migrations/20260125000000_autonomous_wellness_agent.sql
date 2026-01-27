-- Migration: Autonomous Wellness Agent (F025)
-- Creates tables for proactive AI agent monitoring user patterns and taking autonomous actions

-- ============================================
-- Agent Settings (user preferences)
-- ============================================
CREATE TABLE IF NOT EXISTS agent_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    autonomy_level TEXT DEFAULT 'balanced' CHECK (autonomy_level IN (
        'minimal', 'balanced', 'proactive', 'guardian'
    )),
    enabled_signals TEXT[] DEFAULT ARRAY['mood_decline', 'activity_drop', 'streak_risk', 'inactivity', 'positive_momentum'],
    quiet_hours_start TIME DEFAULT '22:00',
    quiet_hours_end TIME DEFAULT '08:00',
    max_daily_outreach INTEGER DEFAULT 3 CHECK (max_daily_outreach >= 1 AND max_daily_outreach <= 10),
    preferred_channels TEXT[] DEFAULT ARRAY['push', 'in_app'],
    explain_reasoning BOOLEAN DEFAULT TRUE,
    is_enabled BOOLEAN DEFAULT FALSE,
    timezone TEXT DEFAULT 'UTC',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Agent Signals (detected patterns)
-- ============================================
CREATE TABLE IF NOT EXISTS agent_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    signal_type TEXT NOT NULL CHECK (signal_type IN (
        'mood_decline', 'mood_improvement', 'activity_drop',
        'streak_risk', 'inactivity', 'stress_spike', 'positive_momentum'
    )),
    severity TEXT DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    evidence JSONB NOT NULL DEFAULT '{}',
    detected_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    resolution_type TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Agent Actions (planned and executed)
-- ============================================
CREATE TABLE IF NOT EXISTS agent_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    signal_id UUID REFERENCES agent_signals(id) ON DELETE SET NULL,
    action_type TEXT NOT NULL CHECK (action_type IN (
        'check_in', 'suggest_exercise', 'morning_briefing',
        'encouragement', 'streak_reminder', 'mood_prompt',
        'content_recommendation', 'concern_alert'
    )),
    status TEXT DEFAULT 'planned' CHECK (status IN (
        'planned', 'scheduled', 'delivered', 'opened', 'responded', 'dismissed', 'cancelled'
    )),
    scheduled_for TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    content JSONB NOT NULL DEFAULT '{}',
    channel TEXT DEFAULT 'push' CHECK (channel IN ('push', 'in_app', 'sms', 'email')),
    reasoning TEXT,
    user_response JSONB,
    effectiveness_score DECIMAL(3,2) CHECK (effectiveness_score IS NULL OR (effectiveness_score >= 0 AND effectiveness_score <= 2)),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Agent Learnings (ML insights)
-- ============================================
CREATE TABLE IF NOT EXISTS agent_learnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    learning_type TEXT NOT NULL CHECK (learning_type IN (
        'optimal_time', 'response_preference', 'content_preference',
        'signal_sensitivity', 'channel_preference', 'frequency_tolerance'
    )),
    learned_value JSONB NOT NULL,
    confidence DECIMAL(3,2) DEFAULT 0.5 CHECK (confidence >= 0 AND confidence <= 1),
    sample_count INTEGER DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, learning_type)
);

-- ============================================
-- Agent Decisions (audit log)
-- ============================================
CREATE TABLE IF NOT EXISTS agent_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    decision_type TEXT NOT NULL,
    inputs JSONB NOT NULL DEFAULT '{}',
    reasoning TEXT NOT NULL,
    outcome TEXT NOT NULL,
    action_taken UUID REFERENCES agent_actions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Enable Row Level Security
-- ============================================
ALTER TABLE agent_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_learnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_decisions ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS Policies
-- ============================================

-- Agent Settings: Users manage own settings
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own agent settings') THEN
    CREATE POLICY "Users manage own agent settings"
        ON agent_settings FOR ALL
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
END IF;
END $$;

-- Agent Signals: Users view own signals
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own agent signals') THEN
    CREATE POLICY "Users view own agent signals"
        ON agent_signals FOR SELECT
        USING (auth.uid() = user_id);
END IF;
END $$;

-- Agent Signals: Service role can insert (for Edge Functions)
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role inserts agent signals') THEN
    CREATE POLICY "Service role inserts agent signals"
        ON agent_signals FOR INSERT
        WITH CHECK (true);
END IF;
END $$;

-- Agent Actions: Users view and update own actions
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own agent actions') THEN
    CREATE POLICY "Users view own agent actions"
        ON agent_actions FOR SELECT
        USING (auth.uid() = user_id);
END IF;
END $$;

DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users update own agent actions') THEN
    CREATE POLICY "Users update own agent actions"
        ON agent_actions FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
END IF;
END $$;

-- Agent Actions: Service role can insert/update
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages agent actions') THEN
    CREATE POLICY "Service role manages agent actions"
        ON agent_actions FOR ALL
        WITH CHECK (true);
END IF;
END $$;

-- Agent Learnings: Users view own learnings
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own agent learnings') THEN
    CREATE POLICY "Users view own agent learnings"
        ON agent_learnings FOR SELECT
        USING (auth.uid() = user_id);
END IF;
END $$;

-- Agent Learnings: Service role can manage
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages agent learnings') THEN
    CREATE POLICY "Service role manages agent learnings"
        ON agent_learnings FOR ALL
        WITH CHECK (true);
END IF;
END $$;

-- Agent Decisions: Users view own decisions
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own agent decisions') THEN
    CREATE POLICY "Users view own agent decisions"
        ON agent_decisions FOR SELECT
        USING (auth.uid() = user_id);
END IF;
END $$;

-- Agent Decisions: Service role can insert
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role inserts agent decisions') THEN
    CREATE POLICY "Service role inserts agent decisions"
        ON agent_decisions FOR INSERT
        WITH CHECK (true);
END IF;
END $$;

-- ============================================
-- Indexes
-- ============================================
CREATE INDEX IF NOT EXISTS idx_agent_settings_user ON agent_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_agent_signals_user ON agent_signals(user_id);
CREATE INDEX IF NOT EXISTS idx_agent_signals_active ON agent_signals(user_id) WHERE is_resolved = FALSE;
CREATE INDEX IF NOT EXISTS idx_agent_signals_type ON agent_signals(user_id, signal_type, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_actions_user ON agent_actions(user_id);
CREATE INDEX IF NOT EXISTS idx_agent_actions_scheduled ON agent_actions(scheduled_for) WHERE status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_agent_actions_status ON agent_actions(user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_learnings_user ON agent_learnings(user_id);
CREATE INDEX IF NOT EXISTS idx_agent_decisions_user ON agent_decisions(user_id, created_at DESC);

-- ============================================
-- Updated_at Triggers
-- ============================================
CREATE OR REPLACE FUNCTION update_agent_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS agent_settings_updated_at ON agent_settings;
CREATE TRIGGER agent_settings_updated_at
    BEFORE UPDATE ON agent_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_agent_updated_at();

DROP TRIGGER IF EXISTS agent_actions_updated_at ON agent_actions;
CREATE TRIGGER agent_actions_updated_at
    BEFORE UPDATE ON agent_actions
    FOR EACH ROW
    EXECUTE FUNCTION update_agent_updated_at();

-- ============================================
-- Function to initialize agent settings for new users
-- ============================================
CREATE OR REPLACE FUNCTION initialize_agent_settings()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO agent_settings (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to auto-create agent settings when profile is created
DROP TRIGGER IF EXISTS create_agent_settings_on_profile ON profiles;
CREATE TRIGGER create_agent_settings_on_profile
    AFTER INSERT ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION initialize_agent_settings();

COMMENT ON TABLE agent_settings IS 'User preferences for the autonomous wellness agent';
COMMENT ON TABLE agent_signals IS 'Detected behavioral patterns and wellness signals';
COMMENT ON TABLE agent_actions IS 'Planned and executed agent interventions';
COMMENT ON TABLE agent_learnings IS 'Machine learning insights from user responses';
COMMENT ON TABLE agent_decisions IS 'Audit log of agent decision-making process';
