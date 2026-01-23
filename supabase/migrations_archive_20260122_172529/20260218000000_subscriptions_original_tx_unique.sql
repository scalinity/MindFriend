-- Enforce one subscription per Apple original transaction ID
-- This prevents duplicate subscriptions and cross-account binding issues
-- Issue #004: Missing uniqueness on subscriptions.original_transaction_id

DO $$
BEGIN
  -- Check for existing duplicates first
  IF EXISTS (
    SELECT 1
    FROM public.subscriptions
    GROUP BY original_transaction_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate subscriptions.original_transaction_id values exist; resolve before applying unique constraint.';
  END IF;

  -- Create unique index if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE indexname = 'subscriptions_original_transaction_id_key'
  ) THEN
    CREATE UNIQUE INDEX subscriptions_original_transaction_id_key
      ON public.subscriptions (original_transaction_id);
  END IF;
END $$;
