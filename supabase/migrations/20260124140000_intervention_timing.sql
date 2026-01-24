-- Contextual Micro-Interventions: Intelligent Timing and Context-Aware Selection
-- Migration created: 2026-01-24
-- Extends existing micro_moment_* tables with trigger evaluation and delivery tracking

-- Table 1: Intervention Preferences
-- User-configurable settings for intervention delivery behavior
CREATE TABLE IF NOT EXISTS intervention_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT true NOT NULL,
    max_daily INTEGER DEFAULT 5 NOT NULL CHECK (max_daily BETWEEN 1 AND 10),
    quiet_hours_start TIME,  -- e.g., '22:00:00' for 10 PM
    quiet_hours_end TIME,    -- e.g., '06:00:00' for 6 AM (handles midnight wraparound)
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT unique_preferences_per_user UNIQUE(user_id)
);

-- Table 2: Intervention Triggers
-- Tracks user-configured trigger rules (which triggers are active, priorities)
CREATE TABLE IF NOT EXISTS intervention_triggers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    trigger_type TEXT NOT NULL CHECK (trigger_type IN ('time_based', 'biometric', 'pattern', 'calendar')),
    trigger_config JSONB NOT NULL,  -- Flexible config per trigger type
    is_active BOOLEAN DEFAULT true NOT NULL,
    priority INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Table 3: Intervention Deliveries
-- Records every intervention delivery attempt, completion status, and effectiveness metrics
CREATE TABLE IF NOT EXISTS intervention_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    intervention_id UUID NOT NULL REFERENCES micro_moment_templates(id) ON DELETE CASCADE,
    trigger_id UUID REFERENCES intervention_triggers(id) ON DELETE SET NULL,
    trigger_type TEXT CHECK (trigger_type IN ('time_based', 'biometric', 'pattern', 'calendar', 'manual')),
    context_snapshot JSONB,  -- Store context at delivery time (HR, mood, etc.)
    delivered_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    completed BOOLEAN DEFAULT false NOT NULL,
    completed_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    feedback TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Helper function: Check if current time is in quiet hours (handles midnight wraparound)
CREATE OR REPLACE FUNCTION is_in_quiet_hours(
    check_time TIME,
    quiet_start TIME,
    quiet_end TIME
) RETURNS BOOLEAN AS $$
BEGIN
    IF quiet_start IS NULL OR quiet_end IS NULL THEN
        RETURN false;
    END IF;

    -- If quiet_end < quiet_start, it crosses midnight (e.g., 22:00 - 06:00)
    IF quiet_end < quiet_start THEN
        -- In quiet hours if check_time >= start OR check_time <= end
        RETURN check_time >= quiet_start OR check_time <= quiet_end;
    ELSE
        -- Normal case: in quiet hours if check_time BETWEEN start AND end
        RETURN check_time BETWEEN quiet_start AND quiet_end;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Indexes for intervention_preferences
CREATE INDEX IF NOT EXISTS idx_intervention_preferences_user_id
    ON intervention_preferences(user_id);

-- Indexes for intervention_triggers
CREATE INDEX IF NOT EXISTS idx_intervention_triggers_user_id
    ON intervention_triggers(user_id);
CREATE INDEX IF NOT EXISTS idx_intervention_triggers_active
    ON intervention_triggers(user_id, is_active) WHERE is_active = true;

-- Indexes for intervention_deliveries
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_user_id
    ON intervention_deliveries(user_id);
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_delivered_at
    ON intervention_deliveries(user_id, delivered_at DESC);
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_intervention_id
    ON intervention_deliveries(intervention_id);
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_rating
    ON intervention_deliveries(intervention_id, rating) WHERE rating IS NOT NULL;

-- Row Level Security Policies
ALTER TABLE intervention_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE intervention_triggers ENABLE ROW LEVEL SECURITY;
ALTER TABLE intervention_deliveries ENABLE ROW LEVEL SECURITY;

-- RLS Policies for intervention_preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_preferences'
    AND policyname = 'Users can read own preferences'
  ) THEN
    CREATE POLICY "Users can read own preferences"
        ON intervention_preferences FOR SELECT
        USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_preferences'
    AND policyname = 'Users can insert own preferences'
  ) THEN
    CREATE POLICY "Users can insert own preferences"
        ON intervention_preferences FOR INSERT
        WITH CHECK (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_preferences'
    AND policyname = 'Users can update own preferences'
  ) THEN
    CREATE POLICY "Users can update own preferences"
        ON intervention_preferences FOR UPDATE
        USING (auth.uid() = user_id);
  END IF;
END $$;

-- RLS Policies for intervention_triggers
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_triggers'
    AND policyname = 'Users can read own triggers'
  ) THEN
    CREATE POLICY "Users can read own triggers"
        ON intervention_triggers FOR SELECT
        USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_triggers'
    AND policyname = 'Service role can manage triggers'
  ) THEN
    CREATE POLICY "Service role can manage triggers"
        ON intervention_triggers FOR ALL
        USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- RLS Policies for intervention_deliveries
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_deliveries'
    AND policyname = 'Users can read own deliveries'
  ) THEN
    CREATE POLICY "Users can read own deliveries"
        ON intervention_deliveries FOR SELECT
        USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_deliveries'
    AND policyname = 'Users can insert own deliveries'
  ) THEN
    CREATE POLICY "Users can insert own deliveries"
        ON intervention_deliveries FOR INSERT
        WITH CHECK (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_deliveries'
    AND policyname = 'Users can update own deliveries'
  ) THEN
    CREATE POLICY "Users can update own deliveries"
        ON intervention_deliveries FOR UPDATE
        USING (auth.uid() = user_id);
  END IF;
END $$;

-- Add helpful comments
COMMENT ON TABLE intervention_preferences IS 'User-configurable settings for intervention delivery (quiet hours, daily limits)';
COMMENT ON TABLE intervention_triggers IS 'User trigger configurations (time-based, biometric, pattern, calendar)';
COMMENT ON TABLE intervention_deliveries IS 'Tracks intervention delivery, completion, and effectiveness (ratings)';
COMMENT ON FUNCTION is_in_quiet_hours(TIME, TIME, TIME) IS 'Checks if current time is in quiet hours (handles midnight wraparound)';

-- Log successful creation
DO $$
DECLARE
  prefs_count INTEGER;
  triggers_count INTEGER;
  deliveries_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO prefs_count FROM pg_tables WHERE tablename = 'intervention_preferences';
  SELECT COUNT(*) INTO triggers_count FROM pg_tables WHERE tablename = 'intervention_triggers';
  SELECT COUNT(*) INTO deliveries_count FROM pg_tables WHERE tablename = 'intervention_deliveries';

  IF prefs_count > 0 AND triggers_count > 0 AND deliveries_count > 0 THEN
    RAISE NOTICE 'Contextual Micro-Interventions timing tables created successfully';
  ELSE
    RAISE WARNING 'Some intervention timing tables may not have been created';
  END IF;
END $$;
