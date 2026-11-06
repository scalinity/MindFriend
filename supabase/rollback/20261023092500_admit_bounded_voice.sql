-- Pause new relay admission; retain every monthly receipt and active reservation.
-- Keep the bounded claim/finalizer. Never restore an unbudgeted provider path.
BEGIN;
UPDATE public.voice_provider_budget SET daily_seconds = 0 WHERE singleton;
COMMIT;
