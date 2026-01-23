-- Add unique constraint to moods table for (user_id, local_date)
-- This enables upsert operations to work correctly when logging moods
-- Without this constraint, the iOS app's upsert with onConflict: "user_id,local_date" fails silently

-- First, remove any duplicate entries keeping only the most recent one per user per day
WITH duplicates AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY user_id, local_date
               ORDER BY created_at DESC, id DESC
           ) as rn
    FROM moods
)
DELETE FROM moods
WHERE id IN (
    SELECT id FROM duplicates WHERE rn > 1
);

-- Now add the unique constraint
ALTER TABLE moods
ADD CONSTRAINT moods_user_date_unique UNIQUE (user_id, local_date);

-- Add a comment explaining the constraint
COMMENT ON CONSTRAINT moods_user_date_unique ON moods IS
    'Ensures one mood entry per user per day. Required for upsert operations from iOS app.';
