BEGIN;
ALTER TABLE public.time_capsules
  ADD COLUMN IF NOT EXISTS delivery_notification_queued_at timestamptz;

-- Do not notify again about capsules delivered before this workflow existed.
UPDATE public.time_capsules
SET delivery_notification_queued_at = coalesce(delivered_at, now())
WHERE status IN ('delivered', 'opened') AND delivery_notification_queued_at IS NULL;

-- Preserve every previously admitted category while adding the capsule event.
DO $$
DECLARE previous_check text;
BEGIN
  SELECT pg_get_expr(conbin, conrelid) INTO previous_check
  FROM pg_constraint
  WHERE conrelid = 'public.notification_history'::regclass
    AND conname = 'notification_history_notification_type_check' AND contype = 'c';
  IF previous_check IS NULL THEN
    RAISE EXCEPTION 'Notification category constraint is missing';
  END IF;
  ALTER TABLE public.notification_history DROP CONSTRAINT notification_history_notification_type_check;
  EXECUTE format(
    'ALTER TABLE public.notification_history ADD CONSTRAINT notification_history_notification_type_check CHECK ((%s) OR notification_type = %L)',
    previous_check, 'capsule_ready'
  );
END $$;
COMMIT;
