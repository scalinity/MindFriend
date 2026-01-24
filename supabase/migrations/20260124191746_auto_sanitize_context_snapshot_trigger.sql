-- Automatic PHI Sanitization Trigger for context_snapshot
-- Issue: Prevents raw biometric PHI from being stored in intervention_deliveries
-- Solution: BEFORE INSERT/UPDATE trigger that calls sanitize_context_snapshot()
-- Created: 2026-01-24

-- Create trigger function
CREATE OR REPLACE FUNCTION sanitize_delivery_context()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- If context_snapshot exists, sanitize it
    IF NEW.context_snapshot IS NOT NULL THEN
        NEW.context_snapshot := sanitize_context_snapshot(NEW.context_snapshot);
    END IF;

    RETURN NEW;
END;
$$;

-- Create BEFORE INSERT trigger
DROP TRIGGER IF EXISTS sanitize_context_on_insert ON intervention_deliveries;
CREATE TRIGGER sanitize_context_on_insert
    BEFORE INSERT ON intervention_deliveries
    FOR EACH ROW
    EXECUTE FUNCTION sanitize_delivery_context();

-- Create BEFORE UPDATE trigger
DROP TRIGGER IF EXISTS sanitize_context_on_update ON intervention_deliveries;
CREATE TRIGGER sanitize_context_on_update
    BEFORE UPDATE ON intervention_deliveries
    FOR EACH ROW
    WHEN (OLD.context_snapshot IS DISTINCT FROM NEW.context_snapshot)
    EXECUTE FUNCTION sanitize_delivery_context();

-- Add comments
COMMENT ON FUNCTION sanitize_delivery_context() IS
'BEFORE INSERT/UPDATE trigger function that automatically sanitizes context_snapshot.
Prevents raw PHI (biometric values, calendar event titles) from being stored.
Calls sanitize_context_snapshot() to replace numeric values with categories/flags.';

-- Log successful creation
DO $$
BEGIN
    RAISE NOTICE 'Auto-sanitization triggers created for intervention_deliveries.context_snapshot';
    RAISE NOTICE 'PHI protection: All context data will be automatically sanitized before storage';
END $$;
