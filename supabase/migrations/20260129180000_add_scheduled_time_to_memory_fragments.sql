-- Add scheduled_time column to memory_fragments for temporal event awareness
-- This allows the system to track when events are scheduled to occur,
-- so the AI can ask "How did your meeting go?" instead of "your meeting is coming up"

ALTER TABLE memory_fragments ADD COLUMN IF NOT EXISTS scheduled_time TIMESTAMPTZ;

COMMENT ON COLUMN memory_fragments.scheduled_time IS 'Parsed absolute timestamp for when an event is scheduled. Used for time-aware memory recall (upcoming vs past events).';
