-- Participant reads stay client-scoped. Validated couples handlers are the only
-- update path because a row-level policy cannot distinguish each user's consent.
BEGIN;
ALTER POLICY "Service role updates partnerships" ON public.partner_links TO service_role;
REVOKE UPDATE ON public.partner_links FROM PUBLIC, anon, authenticated;
GRANT UPDATE ON public.partner_links TO service_role;
COMMIT;
