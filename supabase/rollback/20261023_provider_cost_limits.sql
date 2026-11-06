-- Safe rollback/pause: prevent new provider admission before reverting application
-- functions or clients. Keep every session, reservation and accounting column.
-- In-flight relays can still finalize. Do not restore the unbudgeted claim RPC.
BEGIN;
UPDATE public.voice_provider_budget SET daily_seconds = 0 WHERE singleton;
COMMIT;
