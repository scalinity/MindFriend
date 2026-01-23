-- Fix P1 High: Prevent overlapping active vacation periods (TOCTOU race condition)
-- Uses PostgreSQL EXCLUDE constraint with daterange to atomically prevent conflicts

-- Enable btree_gist extension for EXCLUDE constraint with equality and range
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Add exclusion constraint to prevent overlapping active vacation periods
-- This ensures that for each user, active vacations cannot have overlapping date ranges
ALTER TABLE vacation_mode
ADD CONSTRAINT vacation_mode_no_overlap_active
  EXCLUDE USING gist (
    user_id WITH =,
    daterange(start_date, end_date, '[]') WITH &&
  )
  WHERE (is_active = true);

-- Add comment explaining the constraint
COMMENT ON CONSTRAINT vacation_mode_no_overlap_active ON vacation_mode IS
  'Prevents overlapping active vacation periods for the same user. Uses daterange with inclusive bounds [] to match date comparison logic. Only enforced when is_active=true.';
