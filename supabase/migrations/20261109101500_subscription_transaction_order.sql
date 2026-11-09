-- Orders the transactions that share one original transaction, so a replayed or
-- late-delivered older transaction cannot replace the plan a newer charge recorded.
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS last_transaction_purchased_at timestamptz;

COMMENT ON COLUMN public.subscriptions.last_transaction_purchased_at IS
  'Apple purchaseDate of last_transaction_id. verify-purchase never lets an earlier purchase replace the stored plan.';
