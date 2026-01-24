-- Add Sanitization Audit Trail
-- Issue: No verification log that PHI sanitization occurred
-- Solution: Audit table to track sanitization events for compliance
-- Created: 2026-01-24
-- Compliance: HIPAA §164.308(a)(1)(ii)(D) - Audit controls

-- Create audit table for intervention_deliveries sanitization
CREATE TABLE IF NOT EXISTS intervention_delivery_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id UUID REFERENCES intervention_deliveries(id) ON DELETE CASCADE,
    sanitization_applied BOOLEAN NOT NULL,
    raw_fields_detected TEXT[] DEFAULT ARRAY[]::TEXT[],
    sanitization_method TEXT NOT NULL,  -- 'trigger' | 'manual' | 'none'
    sanitized_at TIMESTAMPTZ DEFAULT now() NOT NULL,

    CONSTRAINT unique_audit_per_delivery UNIQUE(delivery_id)
);

-- Index for audit queries
CREATE INDEX IF NOT EXISTS idx_intervention_delivery_audit_delivery_id
    ON intervention_delivery_audit(delivery_id);

CREATE INDEX IF NOT EXISTS idx_intervention_delivery_audit_sanitized_at
    ON intervention_delivery_audit(sanitized_at DESC);

-- RLS for audit table (users can read their own audit logs)
ALTER TABLE intervention_delivery_audit ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_delivery_audit'
    AND policyname = 'Users can read own delivery audits'
  ) THEN
    CREATE POLICY "Users can read own delivery audits"
        ON intervention_delivery_audit FOR SELECT
        USING (
            delivery_id IN (
                SELECT id FROM intervention_deliveries
                WHERE user_id = auth.uid()
            )
        );
  END IF;
END $$;

-- Update sanitization trigger to log audit trail
CREATE OR REPLACE FUNCTION sanitize_delivery_context()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    raw_fields TEXT[];
    had_raw_biometrics BOOLEAN := FALSE;
    had_raw_events BOOLEAN := FALSE;
BEGIN
    -- If context_snapshot exists, check for raw PHI and sanitize
    IF NEW.context_snapshot IS NOT NULL THEN
        -- Check for raw biometric values
        IF NEW.context_snapshot ? 'biometrics' THEN
            IF (NEW.context_snapshot->'biometrics') ? 'heartRate' THEN
                raw_fields := array_append(raw_fields, 'biometrics.heartRate');
                had_raw_biometrics := TRUE;
            END IF;
            IF (NEW.context_snapshot->'biometrics') ? 'hrv' THEN
                raw_fields := array_append(raw_fields, 'biometrics.hrv');
                had_raw_biometrics := TRUE;
            END IF;
        END IF;

        -- Check for calendar event titles
        IF NEW.context_snapshot ? 'upcomingEvents' THEN
            -- Check if any event has a title field
            IF EXISTS (
                SELECT 1
                FROM jsonb_array_elements(NEW.context_snapshot->'upcomingEvents') AS event
                WHERE event ? 'title'
            ) THEN
                raw_fields := array_append(raw_fields, 'upcomingEvents[*].title');
                had_raw_events := TRUE;
            END IF;
        END IF;

        -- Sanitize if raw PHI detected
        IF had_raw_biometrics OR had_raw_events THEN
            NEW.context_snapshot := sanitize_context_snapshot(NEW.context_snapshot);

            -- Log sanitization event
            INSERT INTO intervention_delivery_audit (
                delivery_id,
                sanitization_applied,
                raw_fields_detected,
                sanitization_method
            ) VALUES (
                NEW.id,
                TRUE,
                raw_fields,
                'trigger'
            )
            ON CONFLICT (delivery_id) DO UPDATE SET
                sanitization_applied = TRUE,
                raw_fields_detected = EXCLUDED.raw_fields_detected,
                sanitization_method = 'trigger',
                sanitized_at = now();
        ELSE
            -- No raw PHI detected - log that sanitization was checked but not needed
            INSERT INTO intervention_delivery_audit (
                delivery_id,
                sanitization_applied,
                raw_fields_detected,
                sanitization_method
            ) VALUES (
                NEW.id,
                FALSE,
                ARRAY[]::TEXT[],
                'none'
            )
            ON CONFLICT (delivery_id) DO UPDATE SET
                sanitization_applied = FALSE,
                raw_fields_detected = ARRAY[]::TEXT[],
                sanitization_method = 'none',
                sanitized_at = now();
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Add helpful comments
COMMENT ON TABLE intervention_delivery_audit IS
'Audit trail for PHI sanitization events in intervention_deliveries.
Tracks when sanitization occurred, what fields were sanitized, and method used.
Required for HIPAA §164.308(a)(1)(ii)(D) - Audit controls.';

COMMENT ON COLUMN intervention_delivery_audit.sanitization_method IS
'Method used for sanitization:
- trigger: Automatic database trigger sanitization
- manual: Manual sanitization via application code
- none: No raw PHI detected, sanitization not needed';

-- Create view for sanitization monitoring dashboard
CREATE OR REPLACE VIEW sanitization_summary AS
WITH field_aggregates AS (
    SELECT
        date_trunc('day', sanitized_at) AS date,
        sanitization_method,
        array_agg(DISTINCT field) AS common_raw_fields
    FROM intervention_delivery_audit
    CROSS JOIN LATERAL unnest(raw_fields_detected) AS field
    WHERE cardinality(raw_fields_detected) > 0
    GROUP BY date_trunc('day', sanitized_at), sanitization_method
)
SELECT
    date_trunc('day', a.sanitized_at) AS date,
    a.sanitization_method,
    COUNT(*) AS total_deliveries,
    COUNT(CASE WHEN a.sanitization_applied THEN 1 END) AS sanitized_count,
    COUNT(CASE WHEN NOT a.sanitization_applied THEN 1 END) AS no_phi_count,
    f.common_raw_fields
FROM intervention_delivery_audit a
LEFT JOIN field_aggregates f ON
    date_trunc('day', a.sanitized_at) = f.date
    AND a.sanitization_method = f.sanitization_method
GROUP BY date_trunc('day', a.sanitized_at), a.sanitization_method, f.common_raw_fields
ORDER BY date DESC;

COMMENT ON VIEW sanitization_summary IS
'Daily summary of PHI sanitization events for monitoring dashboard.
Shows how many deliveries required sanitization and which fields were most commonly sanitized.';

-- Log successful creation
DO $$
BEGIN
    RAISE NOTICE 'Sanitization audit trail created for intervention_deliveries';
    RAISE NOTICE 'Use sanitization_summary view for daily compliance monitoring';
END $$;
