-- Add Calendar Triggers and ML Optimal Timing Support
-- Created: 2026-01-24
-- Extends intervention_preferences and intervention_triggers for calendar-based
-- preemptive interventions and learned optimal timing patterns

-- Only add columns if intervention_preferences table exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'intervention_preferences') THEN
        RAISE NOTICE 'intervention_preferences table does not exist, skipping calendar timing features';
        RETURN;
    END IF;

    -- Add preferred_times JSONB field to intervention_preferences
    -- Stores ML-learned timing preferences (hour -> confidence boost)
    ALTER TABLE intervention_preferences
    ADD COLUMN IF NOT EXISTS preferred_times JSONB DEFAULT '{}'::jsonb;

    COMMENT ON COLUMN intervention_preferences.preferred_times IS
      'ML-learned timing preferences. Maps hour (0-23) to confidence boost (-0.5 to +0.5).
       Example: {"7": {"completionRate": 0.8, "avgRating": 4.5, "dismissRate": 0.1, "confidence": 0.4}}
       Updated weekly by analyze-intervention-patterns Edge Function.';

    -- Create index for fast preferred_times queries
    CREATE INDEX IF NOT EXISTS idx_intervention_preferences_preferred_times
    ON intervention_preferences USING GIN (preferred_times);

    -- Add helpful comment
    COMMENT ON TABLE intervention_preferences IS
      'User preferences for intervention delivery (quiet hours, daily limits, calendar settings, learned timing patterns)';

    RAISE NOTICE 'Calendar triggers and ML timing support added to intervention_preferences';
END $$;

-- Add comment on intervention_triggers if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'intervention_triggers') THEN
        COMMENT ON COLUMN intervention_triggers.trigger_type IS
          'Trigger type: time_based (morning/evening), biometric (HR/HRV), pattern (mood), calendar (upcoming events), manual';
    END IF;
END $$;
