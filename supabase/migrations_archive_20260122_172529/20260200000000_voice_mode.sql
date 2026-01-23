-- Voice Mode Migration
-- Adds voice settings, usage tracking, and session analytics

-- ============================================
-- VOICE MODE TABLES
-- ============================================

-- Voice settings per user
CREATE TABLE IF NOT EXISTS voice_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
    voice_enabled BOOLEAN DEFAULT TRUE,
    preferred_voice TEXT DEFAULT 'ara' CHECK (preferred_voice IN ('ara', 'rex', 'sal', 'eve', 'leo')),
    auto_play_responses BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Voice usage tracking for quota enforcement
CREATE TABLE IF NOT EXISTS voice_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    period_start DATE NOT NULL,
    minutes_used FLOAT DEFAULT 0,
    last_session_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, period_start)
);

-- Voice sessions for analytics
CREATE TABLE IF NOT EXISTS voice_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_seconds INT DEFAULT 0,
    voice_used TEXT DEFAULT 'ara',
    messages_count INT DEFAULT 0,
    was_quota_limited BOOLEAN DEFAULT FALSE
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_voice_settings_user_id ON voice_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_voice_usage_user_period ON voice_usage(user_id, period_start);
CREATE INDEX IF NOT EXISTS idx_voice_sessions_user_id ON voice_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_voice_sessions_started_at ON voice_sessions(started_at DESC);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE voice_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_sessions ENABLE ROW LEVEL SECURITY;

-- Voice settings policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own voice settings') THEN
        CREATE POLICY "Users manage own voice settings" ON voice_settings
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Voice usage policies (read-only for users, service role updates)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own voice usage') THEN
        CREATE POLICY "Users view own voice usage" ON voice_usage
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Voice sessions policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own voice sessions') THEN
        CREATE POLICY "Users view own voice sessions" ON voice_sessions
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================
-- FUNCTIONS
-- ============================================

-- Get remaining voice minutes for a user
CREATE OR REPLACE FUNCTION get_voice_minutes_remaining(p_user_id UUID)
RETURNS FLOAT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_premium BOOLEAN;
    v_minutes_used FLOAT;
    v_limit FLOAT;
BEGIN
    -- Check premium status
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE user_id = p_user_id
        AND status = 'active'
        AND expires_at > NOW()
    ) INTO v_is_premium;

    -- Premium users have unlimited (return large number)
    IF v_is_premium THEN
        RETURN 999999.0;
    END IF;

    -- Get current period usage (month start)
    SELECT COALESCE(minutes_used, 0) INTO v_minutes_used
    FROM voice_usage
    WHERE user_id = p_user_id
    AND period_start = DATE_TRUNC('month', NOW())::DATE;

    -- Free tier limit: 3 minutes per month
    v_limit := 3.0;

    RETURN GREATEST(0, v_limit - COALESCE(v_minutes_used, 0));
END;
$$;

-- Increment voice usage after a session
CREATE OR REPLACE FUNCTION increment_voice_usage(
    p_user_id UUID,
    p_minutes FLOAT,
    p_period_start DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO voice_usage (user_id, period_start, minutes_used, last_session_at)
    VALUES (p_user_id, p_period_start, p_minutes, NOW())
    ON CONFLICT (user_id, period_start)
    DO UPDATE SET
        minutes_used = voice_usage.minutes_used + p_minutes,
        last_session_at = NOW(),
        updated_at = NOW();
END;
$$;

-- Create voice session and return ID
CREATE OR REPLACE FUNCTION create_voice_session(
    p_user_id UUID,
    p_voice TEXT DEFAULT 'ara'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_id UUID;
BEGIN
    INSERT INTO voice_sessions (user_id, voice_used, started_at)
    VALUES (p_user_id, p_voice, NOW())
    RETURNING id INTO v_session_id;

    RETURN v_session_id;
END;
$$;

-- End voice session and update usage
CREATE OR REPLACE FUNCTION end_voice_session(
    p_session_id UUID,
    p_duration_seconds INT,
    p_messages_count INT DEFAULT 0,
    p_was_quota_limited BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_duration_minutes FLOAT;
    v_period_start DATE;
BEGIN
    -- Get user ID from session
    SELECT user_id INTO v_user_id
    FROM voice_sessions
    WHERE id = p_session_id;

    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Calculate minutes
    v_duration_minutes := p_duration_seconds / 60.0;
    v_period_start := DATE_TRUNC('month', NOW())::DATE;

    -- Update session record
    UPDATE voice_sessions
    SET
        ended_at = NOW(),
        duration_seconds = p_duration_seconds,
        messages_count = p_messages_count,
        was_quota_limited = p_was_quota_limited
    WHERE id = p_session_id;

    -- Increment usage
    PERFORM increment_voice_usage(v_user_id, v_duration_minutes, v_period_start);
END;
$$;

-- ============================================
-- GRANTS
-- ============================================

GRANT EXECUTE ON FUNCTION get_voice_minutes_remaining(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION increment_voice_usage(UUID, FLOAT, DATE) TO service_role;
GRANT EXECUTE ON FUNCTION create_voice_session(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION end_voice_session(UUID, INT, INT, BOOLEAN) TO service_role;
