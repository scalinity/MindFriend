-- Sanitize PHI in context_snapshot JSONB field
-- Issue: Biometric data (heart rate, HRV) stored in plaintext violates HIPAA/GDPR
-- Solution: Replace numeric biometric values with boolean/categorical flags
-- Created: 2026-01-24

-- Create function to sanitize biometric data in context snapshot
-- Removes actual numeric values, replaces with boolean flags or categories
CREATE OR REPLACE FUNCTION sanitize_context_snapshot(context JSONB)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    sanitized JSONB;
    hr NUMERIC;
    hrv NUMERIC;
    biometric_flags JSONB;
BEGIN
    -- Start with original context
    sanitized := context;

    -- If biometrics exist, sanitize them
    IF context ? 'biometrics' THEN
        hr := (context->'biometrics'->>'heartRate')::NUMERIC;
        hrv := (context->'biometrics'->>'hrv')::NUMERIC;

        -- Build sanitized biometric flags (no numeric PHI)
        biometric_flags := jsonb_build_object(
            'hasElevatedHR', CASE WHEN hr IS NOT NULL AND hr > 100 THEN true ELSE false END,
            'hasLowHRV', CASE WHEN hrv IS NOT NULL AND hrv < 30 THEN true ELSE false END,
            'hrCategory', CASE
                WHEN hr IS NULL THEN 'unknown'
                WHEN hr < 60 THEN 'low'
                WHEN hr BETWEEN 60 AND 100 THEN 'normal'
                WHEN hr BETWEEN 101 AND 120 THEN 'elevated'
                ELSE 'very_high'
            END,
            'hrvCategory', CASE
                WHEN hrv IS NULL THEN 'unknown'
                WHEN hrv < 20 THEN 'very_low'
                WHEN hrv BETWEEN 20 AND 50 THEN 'low'
                WHEN hrv BETWEEN 51 AND 100 THEN 'normal'
                ELSE 'high'
            END
        );

        -- Replace biometrics with sanitized version
        sanitized := jsonb_set(sanitized, '{biometrics}', biometric_flags);
    END IF;

    -- If calendar events exist, sanitize event titles (remove PII)
    IF context ? 'upcomingEvents' THEN
        -- Remove event titles entirely (may contain medical/personal info)
        sanitized := jsonb_set(
            sanitized,
            '{upcomingEvents}',
            (
                SELECT jsonb_agg(
                    event - 'title' || jsonb_build_object('hasTitle', true)
                )
                FROM jsonb_array_elements(context->'upcomingEvents') AS event
            )
        );
    END IF;

    RETURN sanitized;
END;
$$;

-- Add comment to document PHI sanitization policy
COMMENT ON COLUMN intervention_deliveries.context_snapshot IS
'Sanitized context at delivery time. NO RAW PHI ALLOWED.
Biometrics: Boolean flags (hasElevatedHR, hasLowHRV) and categories (hrCategory, hrvCategory) - NOT numeric values.
Calendar: Event metadata without titles (PII).
HealthKit raw data remains in Apple Health (encrypted at rest).';

-- Add comment on sanitization function
COMMENT ON FUNCTION sanitize_context_snapshot(JSONB) IS
'Sanitizes TriggerContext by removing PHI:
- Replaces numeric biometric values with boolean flags and categories
- Removes calendar event titles (may contain medical/personal PII)
- Returns HIPAA/GDPR-compliant context snapshot for delivery tracking';

-- Log successful creation
DO $$
BEGIN
    RAISE NOTICE 'PHI sanitization function created for context_snapshot';
    RAISE NOTICE 'IMPORTANT: Always use sanitize_context_snapshot() before INSERT into intervention_deliveries';
END $$;
