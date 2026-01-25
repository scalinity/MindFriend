-- Migration: Stress Signature Fingerprint (F026)
-- Creates personalized early warning system for pre-crisis pattern detection

-- ============================================================
-- 1. Extend crisis_events table for learning
-- ============================================================

ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS crisis_type TEXT DEFAULT 'general';
ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS severity TEXT DEFAULT 'moderate';
ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS user_reported BOOLEAN DEFAULT FALSE;
ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS analyzed BOOLEAN DEFAULT FALSE;
ALTER TABLE crisis_events ADD COLUMN IF NOT EXISTS occurred_at TIMESTAMPTZ;

-- Update occurred_at from detected_at for existing records
UPDATE crisis_events
SET occurred_at = detected_at
WHERE occurred_at IS NULL;

-- Add constraint for crisis_type values
ALTER TABLE crisis_events DROP CONSTRAINT IF EXISTS valid_crisis_type;
ALTER TABLE crisis_events ADD CONSTRAINT valid_crisis_type
  CHECK (crisis_type IN ('anxiety', 'depression', 'burnout', 'panic', 'general'));

-- Add constraint for severity values
ALTER TABLE crisis_events DROP CONSTRAINT IF EXISTS valid_crisis_severity;
ALTER TABLE crisis_events ADD CONSTRAINT valid_crisis_severity
  CHECK (severity IN ('mild', 'moderate', 'severe'));

-- ============================================================
-- 2. Signature Component Library (15 predefined components)
-- ============================================================

CREATE TABLE IF NOT EXISTS signature_component_library (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    signal_type TEXT UNIQUE NOT NULL,
    category TEXT NOT NULL,
    display_name TEXT NOT NULL,
    description TEXT,
    default_threshold FLOAT NOT NULL DEFAULT 0.6,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_category CHECK (category IN ('sleep', 'social', 'cognitive', 'emotional', 'behavioral', 'physical')),
    CONSTRAINT valid_threshold CHECK (default_threshold BETWEEN 0.0 AND 1.0)
);

-- Seed the 15 predefined components
INSERT INTO signature_component_library (signal_type, category, display_name, description, default_threshold) VALUES
-- Sleep (3)
('insomnia_wired', 'sleep', 'Can''t sleep but feel wired', 'Difficulty sleeping despite feeling mentally active or anxious', 0.6),
('oversleeping', 'sleep', 'Sleeping too much', 'Wanting to sleep 10+ hours or stay in bed all day', 0.6),
('early_waking', 'sleep', 'Waking up too early', 'Waking at 3-4am and unable to fall back asleep', 0.6),
-- Social (2)
('isolation', 'social', 'Withdrawing from people', 'Avoiding friends, ignoring messages, canceling plans', 0.6),
('irritability', 'social', 'Snapping at loved ones', 'Getting unusually irritated with people close to you', 0.6),
-- Cognitive (3)
('rumination', 'cognitive', 'Can''t stop thinking about problems', 'Obsessive thoughts about work, relationships, or mistakes', 0.6),
('indecision', 'cognitive', 'Can''t make decisions', 'Even small decisions feel overwhelming', 0.6),
('catastrophizing', 'cognitive', 'Worst-case thinking', 'Everything feels like it will lead to disaster', 0.6),
-- Emotional (2)
('numbness', 'emotional', 'Feeling numb or empty', 'Unable to feel emotions, going through the motions', 0.6),
('tearfulness', 'emotional', 'Crying easily', 'Tears come unexpectedly or at small triggers', 0.6),
-- Behavioral (2)
('procrastination', 'behavioral', 'Avoiding responsibilities', 'Putting off work, chores, or important tasks', 0.6),
('compulsions', 'behavioral', 'Stress behaviors', 'Nail biting, skin picking, or other nervous habits', 0.6),
-- Physical (3)
('appetite_change', 'physical', 'Appetite changes', 'Eating much more or much less than usual', 0.6),
('tension', 'physical', 'Physical tension', 'Headaches, jaw clenching, shoulder tightness', 0.6),
('low_energy', 'physical', 'Low energy', 'Feeling exhausted even after rest, no motivation', 0.6)
ON CONFLICT (signal_type) DO NOTHING;

-- ============================================================
-- 3. Stress Signatures table
-- ============================================================

CREATE TABLE IF NOT EXISTS stress_signatures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    crisis_type TEXT NOT NULL DEFAULT 'general',
    components JSONB NOT NULL DEFAULT '[]'::jsonb,
    source TEXT NOT NULL DEFAULT 'user_reported',
    confidence FLOAT NOT NULL DEFAULT 0.5,
    detection_sensitivity FLOAT NOT NULL DEFAULT 0.5,
    last_learned_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_crisis_type_sig CHECK (crisis_type IN ('anxiety', 'depression', 'burnout', 'panic', 'general')),
    CONSTRAINT valid_source CHECK (source IN ('user_reported', 'historical_learned', 'hybrid_refined')),
    CONSTRAINT valid_confidence CHECK (confidence BETWEEN 0.0 AND 1.0),
    CONSTRAINT valid_sensitivity CHECK (detection_sensitivity BETWEEN 0.0 AND 1.0),
    UNIQUE(user_id, crisis_type)
);

-- Index for fast user signature lookup
CREATE INDEX IF NOT EXISTS idx_stress_signatures_user ON stress_signatures(user_id);

-- Update trigger for updated_at
CREATE OR REPLACE FUNCTION update_stress_signature_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS stress_signature_updated_at_trigger ON stress_signatures;
CREATE TRIGGER stress_signature_updated_at_trigger
    BEFORE UPDATE ON stress_signatures
    FOR EACH ROW
    EXECUTE FUNCTION update_stress_signature_updated_at();

-- ============================================================
-- 4. Signature Signals table (real-time signal log)
-- ============================================================

CREATE TABLE IF NOT EXISTS signature_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    signal_type TEXT NOT NULL,
    value FLOAT NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    source TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_signal_value CHECK (value BETWEEN 0.0 AND 1.0),
    CONSTRAINT valid_signal_source CHECK (source IN ('healthkit', 'app_activity', 'cognitive_detection', 'nervous_system', 'social_vitality', 'wellbeing_debt', 'user_input')),
    UNIQUE(user_id, signal_type, date)
);

-- Index for signal queries
CREATE INDEX IF NOT EXISTS idx_signature_signals_user_date ON signature_signals(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_signature_signals_user_signal ON signature_signals(user_id, signal_type);

-- ============================================================
-- 5. Pattern Alerts table
-- ============================================================

CREATE TABLE IF NOT EXISTS pattern_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    signature_id UUID NOT NULL REFERENCES stress_signatures(id) ON DELETE CASCADE,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active_components JSONB NOT NULL DEFAULT '[]'::jsonb,
    emergence_score FLOAT NOT NULL,
    severity TEXT NOT NULL,
    predicted_time_to_event INTEGER, -- seconds
    intervention_tier TEXT NOT NULL DEFAULT 'gentle',
    intervention_delivered BOOLEAN DEFAULT FALSE,
    intervention_delivered_at TIMESTAMPTZ,
    user_feedback TEXT,
    feedback_notes TEXT,
    feedback_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_emergence_score CHECK (emergence_score BETWEEN 0.0 AND 1.0),
    CONSTRAINT valid_severity CHECK (severity IN ('mild', 'moderate', 'severe')),
    CONSTRAINT valid_intervention_tier CHECK (intervention_tier IN ('gentle', 'moderate', 'immediate')),
    CONSTRAINT valid_user_feedback CHECK (user_feedback IS NULL OR user_feedback IN ('accurate_prediction', 'false_alarm', 'helped_prevent', 'missed_pattern'))
);

-- Indexes for alert queries
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_user ON pattern_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_user_time ON pattern_alerts(user_id, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_signature ON pattern_alerts(signature_id);
CREATE INDEX IF NOT EXISTS idx_pattern_alerts_active ON pattern_alerts(user_id) WHERE dismissed_at IS NULL;

-- ============================================================
-- 6. Row Level Security Policies
-- ============================================================

-- Enable RLS
ALTER TABLE signature_component_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE stress_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE signature_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE pattern_alerts ENABLE ROW LEVEL SECURITY;

-- Component library: read-only for all authenticated users
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'signature_component_library' AND policyname = 'Authenticated users can read component library'
    ) THEN
        CREATE POLICY "Authenticated users can read component library"
            ON signature_component_library FOR SELECT
            TO authenticated
            USING (true);
    END IF;
END $$;

-- Stress signatures: users can CRUD their own
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'stress_signatures' AND policyname = 'Users can read own signatures'
    ) THEN
        CREATE POLICY "Users can read own signatures"
            ON stress_signatures FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'stress_signatures' AND policyname = 'Users can insert own signatures'
    ) THEN
        CREATE POLICY "Users can insert own signatures"
            ON stress_signatures FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'stress_signatures' AND policyname = 'Users can update own signatures'
    ) THEN
        CREATE POLICY "Users can update own signatures"
            ON stress_signatures FOR UPDATE
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'stress_signatures' AND policyname = 'Users can delete own signatures'
    ) THEN
        CREATE POLICY "Users can delete own signatures"
            ON stress_signatures FOR DELETE
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Signature signals: users can CRUD their own
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'signature_signals' AND policyname = 'Users can read own signals'
    ) THEN
        CREATE POLICY "Users can read own signals"
            ON signature_signals FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'signature_signals' AND policyname = 'Users can insert own signals'
    ) THEN
        CREATE POLICY "Users can insert own signals"
            ON signature_signals FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'signature_signals' AND policyname = 'Users can update own signals'
    ) THEN
        CREATE POLICY "Users can update own signals"
            ON signature_signals FOR UPDATE
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Pattern alerts: users can CRUD their own
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'pattern_alerts' AND policyname = 'Users can read own alerts'
    ) THEN
        CREATE POLICY "Users can read own alerts"
            ON pattern_alerts FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'pattern_alerts' AND policyname = 'Users can insert own alerts'
    ) THEN
        CREATE POLICY "Users can insert own alerts"
            ON pattern_alerts FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'pattern_alerts' AND policyname = 'Users can update own alerts'
    ) THEN
        CREATE POLICY "Users can update own alerts"
            ON pattern_alerts FOR UPDATE
            TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- 7. Service role policies for edge functions
-- ============================================================

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'stress_signatures' AND policyname = 'Service role full access to signatures'
    ) THEN
        CREATE POLICY "Service role full access to signatures"
            ON stress_signatures FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'signature_signals' AND policyname = 'Service role full access to signals'
    ) THEN
        CREATE POLICY "Service role full access to signals"
            ON signature_signals FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'pattern_alerts' AND policyname = 'Service role full access to alerts'
    ) THEN
        CREATE POLICY "Service role full access to alerts"
            ON pattern_alerts FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

-- ============================================================
-- 8. Helper functions
-- ============================================================

-- Function to get user's current active alerts count
CREATE OR REPLACE FUNCTION get_active_alerts_count(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INTEGER
        FROM pattern_alerts
        WHERE user_id = p_user_id
        AND dismissed_at IS NULL
        AND created_at > NOW() - INTERVAL '24 hours'
    );
END;
$$;

-- Function to upsert a signal (for daily monitoring)
CREATE OR REPLACE FUNCTION upsert_signature_signal(
    p_user_id UUID,
    p_signal_type TEXT,
    p_value FLOAT,
    p_source TEXT,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO signature_signals (user_id, signal_type, value, source, date)
    VALUES (p_user_id, p_signal_type, LEAST(GREATEST(p_value, 0.0), 1.0), p_source, p_date)
    ON CONFLICT (user_id, signal_type, date)
    DO UPDATE SET
        value = GREATEST(signature_signals.value, EXCLUDED.value), -- Keep higher value
        source = EXCLUDED.source
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_active_alerts_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_signature_signal(UUID, TEXT, FLOAT, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_signature_signal(UUID, TEXT, FLOAT, TEXT, DATE) TO service_role;

-- ============================================================
-- 9. Signal retention cleanup (90 days)
-- ============================================================

-- Create cleanup function
CREATE OR REPLACE FUNCTION cleanup_old_signature_signals()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM signature_signals
    WHERE created_at < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- Schedule daily cleanup (if pg_cron is available)
DO $cron_block$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'cleanup-signature-signals',
            '0 3 * * *',
            'SELECT cleanup_old_signature_signals()'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available, skipping signal cleanup scheduling';
END
$cron_block$;

COMMENT ON TABLE stress_signatures IS 'User stress signatures containing personalized warning sign patterns';
COMMENT ON TABLE signature_signals IS 'Real-time signal measurements for pattern detection';
COMMENT ON TABLE pattern_alerts IS 'Alerts generated when pattern emergence is detected';
COMMENT ON TABLE signature_component_library IS 'Library of 15 predefined warning sign components';
