-- Fix double-encoded trigger_config JSONB values
-- The updateTriggerConfig Swift code was encoding JSON as a string then storing
-- that string in JSONB, resulting in '"{ ... }"' instead of '{ ... }'
-- This extracts the string content and re-parses as proper JSONB

UPDATE intervention_triggers
SET trigger_config = (trigger_config #>> '{}')::jsonb,
    updated_at = NOW()
WHERE jsonb_typeof(trigger_config) = 'string';
