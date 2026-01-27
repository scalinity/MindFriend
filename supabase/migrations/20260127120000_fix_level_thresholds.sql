-- Fix XP level thresholds to match iOS array
-- The backend was using sqrt(xp/50)+1 formula which differs from iOS hardcoded thresholds
-- This migration creates a function and recalculates all user levels

-- Create helper function to calculate level from XP using correct thresholds
CREATE OR REPLACE FUNCTION calculate_level_from_xp(xp INTEGER)
RETURNS INTEGER AS $$
DECLARE
  thresholds INTEGER[] := ARRAY[
    0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700,
    3250, 3850, 4500, 5200, 5950, 6750, 7600, 8500, 9450, 10450,
    11500, 12600, 13750, 14950, 16200, 17500, 18850, 20250, 21700, 23200,
    24750, 26350, 28000, 29700, 31450, 33250, 35100, 37000, 38950, 40950,
    43000, 45100, 47250, 49450, 51700, 54000, 56350, 58750, 61200, 63700
  ];
  i INTEGER;
BEGIN
  FOR i IN REVERSE 50..1 LOOP
    IF xp >= thresholds[i] THEN
      RETURN i;
    END IF;
  END LOOP;
  RETURN 1;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Create helper function to get XP needed for next level
CREATE OR REPLACE FUNCTION xp_to_next_level(xp INTEGER)
RETURNS INTEGER AS $$
DECLARE
  next_thresholds INTEGER[] := ARRAY[
    100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700, 3250,
    3850, 4500, 5200, 5950, 6750, 7600, 8500, 9450, 10450, 11500,
    12600, 13750, 14950, 16200, 17500, 18850, 20250, 21700, 23200, 24750,
    26350, 28000, 29700, 31450, 33250, 35100, 37000, 38950, 40950, 43000,
    45100, 47250, 49450, 51700, 54000, 56350, 58750, 61200, 63700, 63700
  ];
  current_level INTEGER;
BEGIN
  current_level := calculate_level_from_xp(xp);
  IF current_level >= 50 THEN
    RETURN 0;
  END IF;
  RETURN next_thresholds[current_level] - xp;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Recalculate all user levels based on their total XP
UPDATE user_experience
SET
  current_level = calculate_level_from_xp(COALESCE(total_xp, 0)),
  xp_to_next_level = xp_to_next_level(COALESCE(total_xp, 0))
WHERE total_xp IS NOT NULL;

-- Log the fix
DO $$
DECLARE
  affected_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO affected_count FROM user_experience WHERE total_xp IS NOT NULL;
  RAISE NOTICE 'Fixed level calculation for % users', affected_count;
END $$;
