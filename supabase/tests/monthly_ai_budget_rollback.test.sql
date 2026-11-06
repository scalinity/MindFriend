-- Disposable database only: this intentionally applies the closing rollback.
-- Run after the forward migration and monthly_ai_budget.test.sql:
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/monthly_ai_budget_rollback.test.sql
\set ON_ERROR_STOP on
SET ROLE service_role;
SELECT public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000099',
    '00000000-0000-0000-0000-000000000101', 'rollback.fixture', 1);
RESET ROLE;
CREATE TEMP TABLE budget_receipts_before_rollback AS TABLE public.monthly_ai_budget_receipts;
CREATE TEMP TABLE budget_months_before_rollback AS
    SELECT month_start, reserved_microdollars, created_at FROM public.monthly_ai_budget_months;

\ir ../rollback/20261023052846_bound_monthly_ai_budget.sql

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM budget_receipts_before_rollback WHERE allowed) THEN
        RAISE EXCEPTION 'rollback test requires an accepted reservation';
    END IF;
    IF EXISTS (
        (TABLE public.monthly_ai_budget_receipts EXCEPT TABLE budget_receipts_before_rollback)
        UNION ALL
        (TABLE budget_receipts_before_rollback EXCEPT TABLE public.monthly_ai_budget_receipts)
    ) OR EXISTS (
        (SELECT month_start, reserved_microdollars, created_at FROM public.monthly_ai_budget_months
            EXCEPT TABLE budget_months_before_rollback)
        UNION ALL
        (TABLE budget_months_before_rollback EXCEPT
            SELECT month_start, reserved_microdollars, created_at FROM public.monthly_ai_budget_months)
    ) THEN RAISE EXCEPTION 'rollback lost or changed ledger history'; END IF;
    IF EXISTS (SELECT 1 FROM public.monthly_ai_budget_months WHERE limit_microdollars <> 0)
        OR public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000098',
            '00000000-0000-0000-0000-000000000101', 'rollback.fixture', 1)
            <> '{"allowed":false,"reason":"unavailable"}'::jsonb THEN
        RAISE EXCEPTION 'rollback left admissions open';
    END IF;
    IF pg_catalog.has_function_privilege('service_role',
        'public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)', 'EXECUTE')
        OR pg_catalog.has_column_privilege('service_role',
            'public.monthly_ai_budget_months', 'limit_microdollars', 'INSERT,UPDATE') THEN
        RAISE EXCEPTION 'rollback service mutation grants remain';
    END IF;
    INSERT INTO public.monthly_ai_budget_months (month_start) VALUES ('1900-01-01');
    IF (SELECT limit_microdollars FROM public.monthly_ai_budget_months WHERE month_start = '1900-01-01') <> 0 THEN
        RAISE EXCEPTION 'rollback left future default open';
    END IF;
    DELETE FROM public.monthly_ai_budget_months WHERE month_start = '1900-01-01';
END;
$$;
SET ROLE service_role;
DO $$
BEGIN
    BEGIN
        PERFORM public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000098',
            '00000000-0000-0000-0000-000000000101', 'rollback.fixture', 1);
        RAISE EXCEPTION 'service can reserve after rollback';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    PERFORM 1 FROM public.monthly_ai_budget_months;
    PERFORM 1 FROM public.monthly_ai_budget_receipts;
END;
$$;
RESET ROLE;
\echo 'monthly_ai_budget: rollback retention and closed admissions assertions passed'
