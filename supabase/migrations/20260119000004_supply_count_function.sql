-- Create atomic supply count decrement function
-- This ensures thread-safe updates when multiple requests try to decrement simultaneously

CREATE OR REPLACE FUNCTION decrement_supply_count(
  med_id UUID,
  user_id UUID
)
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  -- Atomically decrement supply count and return new value
  UPDATE medications
  SET
    supply_count = supply_count - 1,
    updated_at = now()
  WHERE id = med_id
    AND user_id = user_id
    AND supply_count > 0
    AND is_active = true
  RETURNING supply_count INTO updated_count;

  RETURN COALESCE(updated_count, 0);
END;
$$ LANGUAGE plpgsql;

-- Enable RLS to ensure user can only decrement their own medications
ALTER FUNCTION decrement_supply_count(UUID, UUID)
  SECURITY INVOKER;
