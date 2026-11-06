-- Close admissions without losing reservations or request identities.
BEGIN;

-- Wait for admitted transactions before closing the function and month controls.
SELECT pg_catalog.pg_advisory_xact_lock(624130, 1);

CREATE OR REPLACE FUNCTION public.reserve_monthly_ai_budget(
    p_request_id uuid,
    p_user_id uuid,
    p_feature text,
    p_reserve_microdollars bigint
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN pg_catalog.jsonb_build_object('allowed', false, 'reason', 'unavailable');
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_monthly_ai_budget(uuid, uuid, text, bigint)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE INSERT (month_start, limit_microdollars), UPDATE (limit_microdollars)
    ON public.monthly_ai_budget_months FROM service_role;
ALTER TABLE public.monthly_ai_budget_months ALTER COLUMN limit_microdollars SET DEFAULT 0;
UPDATE public.monthly_ai_budget_months SET limit_microdollars = 0,
    updated_at = pg_catalog.clock_timestamp();

-- Keep both RLS tables, all receipt snapshots, and all reserved amounts intact.
COMMIT;
