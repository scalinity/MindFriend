-- Remove additional duplicate soundscape entries from sleep_content
-- Keep originals from 06:39:43, delete duplicates from 06:42:01

DELETE FROM sleep_content 
WHERE id IN (
  '15737347-d69a-4f13-b8ea-8cbba5eee205',  -- Duplicate White Noise
  '0b4097f1-57a2-41f8-ac8b-dd6ea74c1dbd',  -- Duplicate Thunderstorm
  '217fde88-b27e-4d60-b184-9545131b5172',  -- Duplicate Campfire
  'e57f0ce2-94fa-4a95-9b88-875da64ff6e4'   -- Duplicate Binaural Sleep Waves
);
