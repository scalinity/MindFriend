-- MindFriend: Drop Unencrypted PII from Crisis Events
-- Purpose: GDPR Art. 32 - Remove unencrypted sensitive data
-- Created: 2026-01-22

-- Drop unencrypted trigger_content column from crisis_events
-- This column contained user session content that should have been encrypted
ALTER TABLE crisis_events
  DROP COLUMN IF EXISTS trigger_content;

-- Add audit log for this data cleanup
INSERT INTO audit_logs (
  user_id,
  action,
  resource_type,
  resource_id,
  changes,
  created_at
) VALUES (
  NULL,
  'MIGRATION_COMPLETED',
  'CRISIS_EVENTS',
  NULL,
  jsonb_build_object('migration', '20260703000008', 'action', 'drop_unencrypted_pii'),
  NOW()
) ON CONFLICT DO NOTHING;

COMMENT ON MIGRATION '20260703000008' IS
'Removes unencrypted PII column from crisis_events table to comply with GDPR Art. 32';
