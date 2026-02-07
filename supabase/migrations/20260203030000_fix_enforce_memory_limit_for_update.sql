-- Fix: "FOR UPDATE is not allowed with aggregate functions"
-- The enforce_memory_limit trigger uses COUNT(*) ... FOR UPDATE which PostgreSQL disallows.
-- Fix by locking rows first with a subquery, then counting.

CREATE OR REPLACE FUNCTION enforce_memory_limit() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  memory_count INT;
BEGIN
  -- Lock the user's active memory rows to prevent race conditions,
  -- then count them. FOR UPDATE cannot be used with aggregate functions directly.
  SELECT COUNT(*) INTO memory_count
  FROM (
    SELECT id
    FROM companion_memory
    WHERE user_id = NEW.user_id AND deleted_at IS NULL
    FOR UPDATE
  ) locked_rows;

  -- Block if limit reached
  IF memory_count >= 20 THEN
    RAISE EXCEPTION 'Memory limit reached (20/20). Delete a memory before adding a new one.';
  END IF;

  RETURN NEW;
END;
$$;
