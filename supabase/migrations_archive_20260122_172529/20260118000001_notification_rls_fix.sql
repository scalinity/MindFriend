-- Fix: Add missing RLS policy for notification_history UPDATE
-- Users need to be able to mark their own notifications as opened

-- Allow users to update their own notification status (opened only)
CREATE POLICY "Users can mark own notifications as opened"
  ON notification_history FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND status = 'opened'  -- Can only update to 'opened' status
  );

-- Add index for rate limiting queries
CREATE INDEX IF NOT EXISTS idx_notification_sender
  ON notification_history ((metadata->>'senderId'), created_at DESC)
  WHERE metadata->>'senderId' IS NOT NULL;

COMMENT ON POLICY "Users can mark own notifications as opened" ON notification_history
  IS 'Allow users to update status to opened for tracking notification engagement';
