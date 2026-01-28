-- Fix mood scores from 1-10 scale to 1-5 scale
-- This scales down any values > 5 to fit the 1-5 range

-- Scale mood_score: values 1-2 -> 1, 3-4 -> 2, 5-6 -> 3, 7-8 -> 4, 9-10 -> 5
UPDATE moods
SET
  mood_score = LEAST(5, GREATEST(1, CEIL(mood_score::FLOAT / 2)::INT)),
  anxiety_score = CASE
    WHEN anxiety_score IS NOT NULL THEN LEAST(5, GREATEST(1, CEIL(anxiety_score::FLOAT / 2)::INT))
    ELSE NULL
  END,
  energy_score = CASE
    WHEN energy_score IS NOT NULL THEN LEAST(5, GREATEST(1, CEIL(energy_score::FLOAT / 2)::INT))
    ELSE NULL
  END
WHERE mood_score > 5 OR anxiety_score > 5 OR energy_score > 5;
