-- Update soundscapes to make all but Rain premium
-- Rain and Silence are free, everything else requires premium

UPDATE sleep_content
SET is_premium = true, updated_at = NOW()
WHERE content_type = 'soundscape'
  AND title IN ('Forest Ambience', 'Calm Ocean', 'Ocean Waves', 'Forest Night');

-- Also update any white noise variants that might exist
UPDATE sleep_content
SET is_premium = true, updated_at = NOW()
WHERE content_type = 'soundscape'
  AND (
    LOWER(title) LIKE '%ocean%'
    OR LOWER(title) LIKE '%forest%'
    OR LOWER(title) LIKE '%white noise%'
  )
  AND LOWER(title) NOT LIKE '%rain%';
