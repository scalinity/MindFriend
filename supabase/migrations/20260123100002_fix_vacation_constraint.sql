-- Fix P1 Critical: Correct vacation duration constraint
-- PostgreSQL date subtraction returns days BETWEEN dates (exclusive of start)
-- Example: '2026-01-15' - '2026-01-01' = 14, but represents 15 calendar days inclusive
-- To enforce max 14 calendar days, constraint must be <= 13

ALTER TABLE vacation_mode
DROP CONSTRAINT IF EXISTS max_vacation_duration;

ALTER TABLE vacation_mode
ADD CONSTRAINT max_vacation_duration
  CHECK (end_date - start_date <= 13);

COMMENT ON CONSTRAINT max_vacation_duration ON vacation_mode IS
  'Enforces maximum 14 calendar days for vacation periods. Uses <= 13 because PostgreSQL date subtraction returns days between (exclusive), so end_date - start_date = 13 means 14 calendar days inclusive.';
