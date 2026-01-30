-- Remove duplicate soundscape entries from sleep_content
-- These were accidentally inserted twice on 2026-01-19

DELETE FROM sleep_content 
WHERE id IN (
  'baba4be5-364e-40b8-b0f2-449a41a66245',  -- Duplicate Ocean Waves (06:42:01)
  '806f9965-2be0-49d0-ad85-935a67b86bf4',  -- Duplicate Gentle Rain (06:42:01)
  'd10ff642-af84-4a06-b65f-92e541d64100'   -- Duplicate Forest Night (06:42:01)
);

-- Keep the original entries:
-- 9d81372b-d0ac-45c8-9e0b-171fc34205b8 - Ocean Waves (06:39:43)
-- 5632950b-8d93-42d7-a8b8-fd41f7cfda84 - Gentle Rain (06:39:43)
-- 17c5af4a-30dd-408c-8531-82ab4c42ab8f - Forest Night (06:39:43)
