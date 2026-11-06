-- Run as postgres against a disposable local database after the migration:
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/monthly_ai_budget.test.sql
-- Synthetic metadata only. All fixture changes are rolled back.
\set ON_ERROR_STOP on
BEGIN;
TRUNCATE public.monthly_ai_budget_receipts, public.monthly_ai_budget_months;

DO $$
DECLARE
    v_role text;
    v_table text;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        IF pg_catalog.has_function_privilege(v_role,
            'public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)', 'EXECUTE') THEN
            RAISE EXCEPTION '% can execute budget RPC', v_role;
        END IF;
        FOREACH v_table IN ARRAY ARRAY['monthly_ai_budget_months', 'monthly_ai_budget_receipts'] LOOP
            IF pg_catalog.has_table_privilege(v_role, 'public.' || v_table,
                'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
                RAISE EXCEPTION '% has budget table privileges', v_role;
            END IF;
        END LOOP;
    END LOOP;
    IF NOT pg_catalog.has_function_privilege('service_role',
        'public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)', 'EXECUTE') THEN
        RAISE EXCEPTION 'service RPC grant missing';
    END IF;
    IF pg_catalog.has_column_privilege('service_role',
        'public.monthly_ai_budget_months', 'reserved_microdollars', 'UPDATE')
        OR pg_catalog.has_table_privilege('service_role',
            'public.monthly_ai_budget_receipts', 'INSERT,UPDATE,DELETE,TRUNCATE') THEN
        RAISE EXCEPTION 'service can mutate ledger outside RPC';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class AS c,
            LATERAL pg_catalog.aclexplode(c.relacl) AS a
        WHERE c.oid IN ('public.monthly_ai_budget_months'::regclass,
            'public.monthly_ai_budget_receipts'::regclass) AND a.grantee = 0
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p,
            LATERAL pg_catalog.aclexplode(p.proacl) AS a
        WHERE p.oid = 'public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)'::regprocedure
            AND a.grantee = 0
    ) THEN RAISE EXCEPTION 'PUBLIC has a budget grant'; END IF;
    IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_class AS c
        WHERE c.oid IN ('public.monthly_ai_budget_months'::regclass,
            'public.monthly_ai_budget_receipts'::regclass) AND c.relrowsecurity) <> 2 THEN
        RAISE EXCEPTION 'RLS missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc AS p
        WHERE p.oid = 'public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)'::regprocedure
            AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
    ) THEN RAISE EXCEPTION 'RPC must use security definer with empty search_path'; END IF;
END;
$$;

SET LOCAL ROLE anon;
DO $$
BEGIN
    BEGIN
        PERFORM public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000101', 'chat', 1);
        RAISE EXCEPTION 'anon RPC allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        PERFORM 1 FROM public.monthly_ai_budget_months;
        RAISE EXCEPTION 'anon counter read allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        PERFORM 1 FROM public.monthly_ai_budget_receipts;
        RAISE EXCEPTION 'anon receipt read allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $$
BEGIN
    BEGIN
        PERFORM public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000101', 'chat', 1);
        RAISE EXCEPTION 'authenticated RPC allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        PERFORM 1 FROM public.monthly_ai_budget_months;
        RAISE EXCEPTION 'authenticated counter read allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        PERFORM 1 FROM public.monthly_ai_budget_receipts;
        RAISE EXCEPTION 'authenticated receipt read allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
RESET ROLE;

-- Server chooses Eastern month even if the session uses another timezone.
SET LOCAL TIME ZONE 'Pacific/Kiritimati';
SET LOCAL ROLE service_role;
DO $$
DECLARE
    v_first jsonb;
    v_result jsonb;
    v_invalid bigint;
    v_month date := pg_catalog.date_trunc('month',
        pg_catalog.timezone('America/New_York', pg_catalog.clock_timestamp()))::date;
BEGIN
    FOREACH v_invalid IN ARRAY ARRAY[0::bigint, -1::bigint, 10000001::bigint, 9223372036854775807::bigint] LOOP
        BEGIN
            PERFORM public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
                '00000000-0000-0000-0000-000000000101', 'chat', v_invalid);
            RAISE EXCEPTION 'invalid amount allowed';
        EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    END LOOP;
    BEGIN
        PERFORM public.reserve_monthly_ai_budget(NULL,
            '00000000-0000-0000-0000-000000000101', 'chat', 1);
        RAISE EXCEPTION 'null UUID allowed';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    BEGIN
        PERFORM public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000101', '', 1);
        RAISE EXCEPTION 'empty feature allowed';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    BEGIN
        PERFORM public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000101', E'chat\n', 1);
        RAISE EXCEPTION 'newline feature allowed';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    IF EXISTS (SELECT 1 FROM public.monthly_ai_budget_months)
        OR EXISTS (SELECT 1 FROM public.monthly_ai_budget_receipts) THEN
        RAISE EXCEPTION 'invalid requests created ledger state';
    END IF;

    v_first := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101', 'chat', 1);
    IF v_first <> pg_catalog.jsonb_build_object(
        'allowed', true, 'reason', 'reserved',
        'request_id', '00000000-0000-0000-0000-000000000001',
        'user_id', '00000000-0000-0000-0000-000000000101', 'feature', 'chat',
        'month_start', v_month, 'reserve_microdollars', 1,
        'reserved_microdollars', 1, 'limit_microdollars', 10000000,
        'remaining_microdollars', 9999999
    ) THEN RAISE EXCEPTION 'first row/contract incorrect: %', v_first; END IF;

    v_result := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000102', 'tts', 9999999);
    IF v_result->>'allowed' <> 'true' OR v_result->>'remaining_microdollars' <> '0' THEN
        RAISE EXCEPTION 'exact shared ceiling denied';
    END IF;
    v_result := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000103', 'image', 1);
    IF v_result->>'allowed' <> 'false' OR v_result->>'reason' <> 'exhausted' THEN
        RAISE EXCEPTION 'overlimit admission allowed';
    END IF;
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101', 'chat', 1) <> v_first THEN
        RAISE EXCEPTION 'retry changed original result or debited again';
    END IF;
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000102', 'chat', 1)->>'reason' <> 'request_mismatch'
        OR public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101', 'tts', 1)->>'reason' <> 'request_mismatch'
        OR public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101', 'chat', 2)->>'reason' <> 'request_mismatch' THEN
        RAISE EXCEPTION 'mismatched UUID reused';
    END IF;
    IF (SELECT reserved_microdollars FROM public.monthly_ai_budget_months
        WHERE month_start = v_month) <> 10000000
        OR (SELECT pg_catalog.count(*) FROM public.monthly_ai_budget_receipts) <> 3 THEN
        RAISE EXCEPTION 'counter or receipt count incorrect';
    END IF;

    BEGIN
        UPDATE public.monthly_ai_budget_months SET reserved_microdollars = 0;
        RAISE EXCEPTION 'service can refund reservations';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        DELETE FROM public.monthly_ai_budget_receipts;
        RAISE EXCEPTION 'service can erase UUID history';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN
        UPDATE public.monthly_ai_budget_months SET limit_microdollars = 10000001;
        RAISE EXCEPTION 'service can raise hard ceiling';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE public.monthly_ai_budget_months SET limit_microdollars = -1;
        RAISE EXCEPTION 'negative config accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;

    UPDATE public.monthly_ai_budget_months SET limit_microdollars = 0 WHERE month_start = v_month;
    v_result := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000101', 'chat', 1);
    IF v_result->>'reason' <> 'disabled' OR v_result->>'allowed' <> 'false'
        OR v_result->>'reserved_microdollars' <> '10000000' THEN
        RAISE EXCEPTION 'disabled config admitted or released reservations';
    END IF;
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000103', 'image', 1)->>'reason' <> 'exhausted' THEN
        RAISE EXCEPTION 'original denial changed after config change';
    END IF;
END;
$$;
RESET ROLE;

-- Seed historical decisions directly as postgres, simulating a month boundary
-- without a caller-controlled clock or touching real accounts.
INSERT INTO public.monthly_ai_budget_months (month_start, reserved_microdollars, limit_microdollars)
    VALUES ('2000-01-01', 500, 1000);
INSERT INTO public.monthly_ai_budget_receipts (request_id, user_id, feature,
    reserve_microdollars, month_start, allowed, reason, reserved_microdollars, limit_microdollars)
VALUES
    ('00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000101',
        'chat', 500, '2000-01-01', true, 'reserved', 500, 1000),
    ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000101',
        'chat', 501, '2000-01-01', false, 'exhausted', 500, 1000);

SET LOCAL ROLE service_role;
DO $$
DECLARE
    v_result jsonb;
BEGIN
    v_result := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000010',
        '00000000-0000-0000-0000-000000000101', 'chat', 500);
    IF v_result->>'allowed' <> 'true' OR v_result->>'month_start' <> '2000-01-01'
        OR v_result->>'remaining_microdollars' <> '500' THEN
        RAISE EXCEPTION 'old-month admission was not reused';
    END IF;
    v_result := public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000011',
        '00000000-0000-0000-0000-000000000101', 'chat', 501);
    IF v_result->>'reason' <> 'exhausted' OR v_result->>'month_start' <> '2000-01-01' THEN
        RAISE EXCEPTION 'old-month denial was not reused';
    END IF;
    IF (SELECT reserved_microdollars FROM public.monthly_ai_budget_months WHERE month_start = '2000-01-01') <> 500
        OR (SELECT pg_catalog.count(*) FROM public.monthly_ai_budget_receipts) <> 6 THEN
        RAISE EXCEPTION 'month-boundary retry changed ledger';
    END IF;
END;
$$;
RESET ROLE;

-- A service-preconfigured empty month must use its reduced limit on first admission.
TRUNCATE public.monthly_ai_budget_receipts, public.monthly_ai_budget_months;
SET LOCAL ROLE service_role;
INSERT INTO public.monthly_ai_budget_months (month_start, limit_microdollars)
    VALUES (pg_catalog.date_trunc('month', pg_catalog.timezone('America/New_York', pg_catalog.clock_timestamp()))::date, 100);
DO $$
BEGIN
    IF public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000101', 'chat', 101)->>'reason' <> 'exhausted'
        OR public.reserve_monthly_ai_budget('00000000-0000-0000-0000-000000000021',
        '00000000-0000-0000-0000-000000000101', 'chat', 100)->>'allowed' <> 'true' THEN
        RAISE EXCEPTION 'reduced limit ignored';
    END IF;
END;
$$;
RESET ROLE;
ROLLBACK;
\echo 'monthly_ai_budget: role, boundary, idempotency, and config assertions passed'
