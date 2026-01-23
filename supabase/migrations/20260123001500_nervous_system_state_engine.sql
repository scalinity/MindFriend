-- Nervous System State Engine Migration
-- Implements Polyvagal Theory-based state classification
-- Date: 2026-01-23

-- nervous_system_states table
CREATE TABLE IF NOT EXISTS nervous_system_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    state TEXT NOT NULL CHECK (state IN ('ventral', 'sympathetic', 'dorsal', 'mixed', 'unknown')),
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),

    -- Feature contributions (JSONB for flexibility)
    voice_features JSONB,
    hrv_features JSONB,
    behavioral_features JSONB,

    -- Classification metadata
    latency_ms INTEGER,
    source TEXT NOT NULL CHECK (source IN ('voice_session', 'passive_foreground')),

    -- Timestamps
    classified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_nervous_system_states_user_time
    ON nervous_system_states(user_id, classified_at DESC);

CREATE INDEX IF NOT EXISTS idx_nervous_system_states_state
    ON nervous_system_states(state)
    WHERE state != 'unknown';

-- cascade_events table
CREATE TABLE IF NOT EXISTS cascade_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Event window
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,

    -- State sequence (array of states in order)
    state_sequence TEXT[] NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('mild', 'moderate', 'severe')),

    -- Metadata
    transition_count INTEGER NOT NULL,

    -- Timestamps
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_cascade_window CHECK (ended_at > started_at),
    CONSTRAINT valid_transition_count CHECK (transition_count >= 3)
);

CREATE INDEX IF NOT EXISTS idx_cascade_events_user_time
    ON cascade_events(user_id, detected_at DESC);

-- state_interventions table
CREATE TABLE IF NOT EXISTS state_interventions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    state_record_id UUID REFERENCES nervous_system_states(id) ON DELETE SET NULL,
    cascade_event_id UUID REFERENCES cascade_events(id) ON DELETE SET NULL,

    -- Intervention details
    intervention_type TEXT NOT NULL CHECK (intervention_type IN (
        'breathing', 'grounding', 'movement', 'social_connection', 'professional_support'
    )),
    title TEXT NOT NULL,
    description TEXT,
    urgency TEXT NOT NULL CHECK (urgency IN ('low', 'medium', 'high', 'critical')),

    -- Completion tracking
    recommended_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    -- Efficacy feedback
    efficacy_rating DECIMAL(3,2) CHECK (efficacy_rating >= 0 AND efficacy_rating <= 1),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT at_least_one_trigger CHECK (
        state_record_id IS NOT NULL OR cascade_event_id IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_state_interventions_user_time
    ON state_interventions(user_id, recommended_at DESC);

CREATE INDEX IF NOT EXISTS idx_state_interventions_completion
    ON state_interventions(user_id, completed_at)
    WHERE completed_at IS NOT NULL;

-- user_intervention_efficacy (aggregated efficacy scores per user)
CREATE TABLE IF NOT EXISTS user_intervention_efficacy (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    intervention_type TEXT NOT NULL,
    target_state TEXT NOT NULL,

    -- Aggregated metrics
    total_completed INTEGER NOT NULL DEFAULT 0,
    avg_efficacy DECIMAL(3,2) NOT NULL DEFAULT 0.5,

    -- Timestamps
    last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (user_id, intervention_type, target_state)
);

-- RLS Policies
ALTER TABLE nervous_system_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE cascade_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE state_interventions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_intervention_efficacy ENABLE ROW LEVEL SECURITY;

-- Users can only see their own data
DO $$
BEGIN
    -- Drop existing policies if they exist
    DROP POLICY IF EXISTS "Users read own nervous system states" ON nervous_system_states;
    DROP POLICY IF EXISTS "Users insert own nervous system states" ON nervous_system_states;
    DROP POLICY IF EXISTS "Users read own cascade events" ON cascade_events;
    DROP POLICY IF EXISTS "Users insert own cascade events" ON cascade_events;
    DROP POLICY IF EXISTS "Users read own interventions" ON state_interventions;
    DROP POLICY IF EXISTS "Users insert own interventions" ON state_interventions;
    DROP POLICY IF EXISTS "Users update own interventions" ON state_interventions;
    DROP POLICY IF EXISTS "Users read own efficacy data" ON user_intervention_efficacy;
    DROP POLICY IF EXISTS "Users upsert own efficacy data" ON user_intervention_efficacy;
END $$;

CREATE POLICY "Users read own nervous system states"
    ON nervous_system_states FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users insert own nervous system states"
    ON nervous_system_states FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own cascade events"
    ON cascade_events FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users insert own cascade events"
    ON cascade_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own interventions"
    ON state_interventions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users insert own interventions"
    ON state_interventions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own interventions"
    ON state_interventions FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own efficacy data"
    ON user_intervention_efficacy FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users upsert own efficacy data"
    ON user_intervention_efficacy FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 90-day retention policy function
CREATE OR REPLACE FUNCTION delete_old_nervous_system_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Delete states older than 90 days
    DELETE FROM nervous_system_states
    WHERE created_at < NOW() - INTERVAL '90 days';

    -- Delete cascade events older than 90 days
    DELETE FROM cascade_events
    WHERE created_at < NOW() - INTERVAL '90 days';

    -- Delete interventions older than 90 days
    DELETE FROM state_interventions
    WHERE created_at < NOW() - INTERVAL '90 days';
END;
$$;

-- Function to update intervention efficacy aggregates
CREATE OR REPLACE FUNCTION update_intervention_efficacy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    target_state_value TEXT;
BEGIN
    -- Get the state from the linked state_record
    IF NEW.state_record_id IS NOT NULL THEN
        SELECT state INTO target_state_value
        FROM nervous_system_states
        WHERE id = NEW.state_record_id;
    END IF;

    -- Only process if intervention was completed and has efficacy rating
    IF NEW.completed_at IS NOT NULL AND NEW.efficacy_rating IS NOT NULL AND target_state_value IS NOT NULL THEN
        INSERT INTO user_intervention_efficacy (
            user_id,
            intervention_type,
            target_state,
            total_completed,
            avg_efficacy
        )
        VALUES (
            NEW.user_id,
            NEW.intervention_type,
            target_state_value,
            1,
            NEW.efficacy_rating
        )
        ON CONFLICT (user_id, intervention_type, target_state)
        DO UPDATE SET
            total_completed = user_intervention_efficacy.total_completed + 1,
            avg_efficacy = (
                (user_intervention_efficacy.avg_efficacy * user_intervention_efficacy.total_completed)
                + NEW.efficacy_rating
            ) / (user_intervention_efficacy.total_completed + 1),
            last_updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS update_efficacy_on_intervention_completion ON state_interventions;
CREATE TRIGGER update_efficacy_on_intervention_completion
    AFTER UPDATE ON state_interventions
    FOR EACH ROW
    WHEN (NEW.completed_at IS NOT NULL AND OLD.completed_at IS NULL)
    EXECUTE FUNCTION update_intervention_efficacy();

-- Add nervous_system_retention_days to user_settings (if table exists)
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_settings') THEN
        ALTER TABLE user_settings
        ADD COLUMN IF NOT EXISTS nervous_system_retention_days INTEGER DEFAULT 90;
    END IF;
END $$;
