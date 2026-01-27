-- Fix level in user_stats table (this is where iOS reads from)
-- The user_experience migration fixed the wrong table

-- Recalculate all user levels in user_stats based on xp_total
UPDATE user_stats
SET level = calculate_level_from_xp(COALESCE(xp_total, 0))
WHERE xp_total IS NOT NULL AND xp_total > 0;

-- Log the fix
DO $$
DECLARE
  affected_count INTEGER;
BEGIN
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RAISE NOTICE 'Fixed level calculation for % users in user_stats', affected_count;
END $$;
