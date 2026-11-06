BEGIN;
DO $$
DECLARE definition text; accepted boolean; category text;
BEGIN
  SELECT pg_get_expr(conbin, conrelid) INTO definition FROM pg_constraint
  WHERE conrelid = 'public.notification_history'::regclass
    AND conname = 'notification_history_notification_type_check';
  FOREACH category IN ARRAY ARRAY['capsule_ready', 'hug'] LOOP
    EXECUTE format('SELECT %s FROM (SELECT $1::text notification_type) input', definition)
      INTO accepted USING category;
    IF accepted IS DISTINCT FROM true THEN RAISE EXCEPTION 'Notification category rejected: %', category; END IF;
  END LOOP;
  EXECUTE format('SELECT %s FROM (SELECT $1::text notification_type) input', definition)
    INTO accepted USING 'capsule_ready_invented';
  IF accepted IS DISTINCT FROM false THEN RAISE EXCEPTION 'Unknown capsule category accepted'; END IF;
  IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_schema='public' AND table_name='time_capsules' AND column_name='delivery_notification_queued_at' AND data_type='timestamp with time zone') THEN
    RAISE EXCEPTION 'Capsule notification admission marker missing';
  END IF;
END $$;
ROLLBACK;
