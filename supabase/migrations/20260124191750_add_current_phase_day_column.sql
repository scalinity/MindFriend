-- Add current_phase_day column to user_pathways table
-- This tracks the day number within the current phase (resets when phase advances)

ALTER TABLE user_pathways
ADD COLUMN IF NOT EXISTS current_phase_day INTEGER NOT NULL DEFAULT 1;

-- Add comment for documentation
COMMENT ON COLUMN user_pathways.current_phase_day IS 'Day number within the current phase (1-based, resets when phase advances)';

-- Create index for common query patterns
CREATE INDEX IF NOT EXISTS idx_user_pathways_current_phase_day
ON user_pathways(current_phase_day);
