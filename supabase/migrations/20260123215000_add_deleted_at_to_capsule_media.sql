-- Add deleted_at column to capsule_media table
-- CRITICAL FIX: The cascade_capsule_soft_delete trigger references this column
-- but it was missing from the original schema, causing trigger failures

ALTER TABLE capsule_media
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Add index for cleanup queries (orphaned media older than 30 days)
CREATE INDEX IF NOT EXISTS idx_capsule_media_deleted_at
ON capsule_media(deleted_at)
WHERE deleted_at IS NOT NULL;

-- Update RLS policy to filter soft-deleted media
DROP POLICY IF EXISTS "Users can read own capsule media" ON capsule_media;

CREATE POLICY "Users can read own capsule media" ON capsule_media
  FOR SELECT USING (
    deleted_at IS NULL AND  -- Filter soft-deleted media
    capsule_id IN (
      SELECT id FROM time_capsules
      WHERE user_id = auth.uid() AND deleted_at IS NULL
    )
  );

COMMENT ON COLUMN capsule_media.deleted_at IS
'Soft-delete timestamp. Set by cascade_capsule_soft_delete trigger when parent capsule is deleted. Cleaned up by cleanup-deleted-capsule-media cron after 30 days.';
