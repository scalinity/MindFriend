-- Shared reservation ledger: $10 USD total per America/New_York calendar month.
-- Reserve an upper bound before paid submission. Unknown provider outcomes stay
-- reserved; a receipt is not proof of provider submission or exactly-once work.
BEGIN;

CREATE TABLE public.monthly_ai_budget_months (
    month_start date PRIMARY KEY CHECK (EXTRACT(DAY FROM month_start) = 1),
    reserved_microdollars bigint NOT NULL DEFAULT 0
        CHECK (reserved_microdollars BETWEEN 0 AND 10000000),
    -- Service-only, per-month control. Zero closes new admissions for that month.
    -- Lowering below existing reservations never releases their debit.
    limit_microdollars bigint NOT NULL DEFAULT 10000000
        CHECK (limit_microdollars BETWEEN 0 AND 10000000),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);

CREATE TABLE public.monthly_ai_budget_receipts (
    request_id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    feature text NOT NULL CHECK (feature ~ '^[a-z][a-z0-9_.:-]{0,63}$'),
    reserve_microdollars bigint NOT NULL
        CHECK (reserve_microdollars BETWEEN 1 AND 10000000),
    month_start date NOT NULL REFERENCES public.monthly_ai_budget_months(month_start),
    allowed boolean NOT NULL,
    reason text NOT NULL CHECK (reason IN ('reserved', 'exhausted', 'disabled')),
    -- Snapshots preserve the original decision, including a denial, on every retry.
    reserved_microdollars bigint NOT NULL CHECK (reserved_microdollars BETWEEN 0 AND 10000000),
    limit_microdollars bigint NOT NULL CHECK (limit_microdollars BETWEEN 0 AND 10000000),
    created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
    CHECK (
        (allowed AND reason = 'reserved' AND reserved_microdollars >= reserve_microdollars
            AND reserved_microdollars <= limit_microdollars)
        OR (NOT allowed AND reason = 'disabled' AND limit_microdollars = 0)
        OR (NOT allowed AND reason = 'exhausted' AND limit_microdollars > 0
            AND reserve_microdollars > GREATEST(limit_microdollars - reserved_microdollars, 0))
    )
);

ALTER TABLE public.monthly_ai_budget_months ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_ai_budget_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.monthly_ai_budget_months, public.monthly_ai_budget_receipts
    FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.monthly_ai_budget_months, public.monthly_ai_budget_receipts TO service_role;
-- Counter and receipts can only be mutated by the reservation function's owner.
-- Service callers may preconfigure a future month or lower/disable the current one.
GRANT INSERT (month_start, limit_microdollars), UPDATE (limit_microdollars)
    ON public.monthly_ai_budget_months TO service_role;

CREATE POLICY monthly_ai_budget_months_service_select ON public.monthly_ai_budget_months
    FOR SELECT TO service_role USING (true);
CREATE POLICY monthly_ai_budget_months_service_insert ON public.monthly_ai_budget_months
    FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY monthly_ai_budget_months_service_update ON public.monthly_ai_budget_months
    FOR UPDATE TO service_role USING (true) WITH CHECK (true);
CREATE POLICY monthly_ai_budget_receipts_service_select ON public.monthly_ai_budget_receipts
    FOR SELECT TO service_role USING (true);

CREATE FUNCTION public.reserve_monthly_ai_budget(
    p_request_id uuid,
    p_user_id uuid,
    p_feature text,
    p_reserve_microdollars bigint
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_month date;
    v_budget public.monthly_ai_budget_months%ROWTYPE;
    v_receipt public.monthly_ai_budget_receipts%ROWTYPE;
    v_allowed boolean;
    v_reason text;
BEGIN
    IF p_request_id IS NULL OR p_user_id IS NULL OR p_feature IS NULL
        OR p_feature !~ '^[a-z][a-z0-9_.:-]{0,63}$'
        OR p_reserve_microdollars IS NULL OR p_reserve_microdollars <= 0
        OR p_reserve_microdollars > 10000000 THEN
        RAISE EXCEPTION 'Invalid monthly AI budget reservation' USING ERRCODE = '22023';
    END IF;

    -- One shared transaction lock covers first-row creation and request UUID races,
    -- even when the callers have different users/features or straddle midnight.
    PERFORM pg_catalog.pg_advisory_xact_lock(624130, 1);

    SELECT r.* INTO v_receipt FROM public.monthly_ai_budget_receipts AS r
        WHERE r.request_id = p_request_id;
    IF FOUND THEN
        IF v_receipt.user_id <> p_user_id OR v_receipt.feature <> p_feature
            OR v_receipt.reserve_microdollars <> p_reserve_microdollars THEN
            RETURN pg_catalog.jsonb_build_object('allowed', false, 'reason', 'request_mismatch');
        END IF;
    ELSE
        -- Derive the month after waiting for the lock, independent of session timezone
        -- and transaction start time. No caller-supplied date or ceiling is accepted.
        v_month := pg_catalog.date_trunc('month',
            pg_catalog.timezone('America/New_York', pg_catalog.clock_timestamp()))::date;
        INSERT INTO public.monthly_ai_budget_months (month_start) VALUES (v_month)
            ON CONFLICT (month_start) DO NOTHING;
        SELECT m.* INTO STRICT v_budget FROM public.monthly_ai_budget_months AS m
            WHERE m.month_start = v_month FOR UPDATE;

        v_allowed := v_budget.limit_microdollars > 0
            AND p_reserve_microdollars <= v_budget.limit_microdollars - v_budget.reserved_microdollars;
        v_reason := CASE WHEN v_budget.limit_microdollars = 0 THEN 'disabled'
            WHEN v_allowed THEN 'reserved' ELSE 'exhausted' END;
        IF v_allowed THEN
            UPDATE public.monthly_ai_budget_months AS m
                SET reserved_microdollars = m.reserved_microdollars + p_reserve_microdollars,
                    updated_at = pg_catalog.clock_timestamp()
                WHERE m.month_start = v_month RETURNING m.* INTO v_budget;
        END IF;

        INSERT INTO public.monthly_ai_budget_receipts (
            request_id, user_id, feature, reserve_microdollars, month_start,
            allowed, reason, reserved_microdollars, limit_microdollars
        ) VALUES (
            p_request_id, p_user_id, p_feature, p_reserve_microdollars, v_month,
            v_allowed, v_reason, v_budget.reserved_microdollars, v_budget.limit_microdollars
        ) RETURNING * INTO v_receipt;
    END IF;

    RETURN pg_catalog.jsonb_build_object(
        'allowed', v_receipt.allowed,
        'reason', v_receipt.reason,
        'request_id', v_receipt.request_id,
        'user_id', v_receipt.user_id,
        'feature', v_receipt.feature,
        'month_start', v_receipt.month_start,
        'reserve_microdollars', v_receipt.reserve_microdollars,
        'reserved_microdollars', v_receipt.reserved_microdollars,
        'limit_microdollars', v_receipt.limit_microdollars,
        'remaining_microdollars', GREATEST(v_receipt.limit_microdollars - v_receipt.reserved_microdollars, 0)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_monthly_ai_budget(uuid, uuid, text, bigint)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_monthly_ai_budget(uuid, uuid, text, bigint) TO service_role;

COMMENT ON TABLE public.monthly_ai_budget_months IS
    'Global AI reservations, in integer USD microdollars, per Eastern calendar month. Hard maximum $10; service-only per-month limit may reduce or disable new admissions.';
COMMENT ON TABLE public.monthly_ai_budget_receipts IS
    'Immutable reservation decisions and cost snapshots; no prompts, conversation content, provider keys, refunds, or provider completion claims. Retain across rollback and month rollover.';
COMMENT ON FUNCTION public.reserve_monthly_ai_budget(uuid, uuid, text, bigint) IS
    'Service-only atomic shared reservation. Matching UUID retries return the original decision without another debit. Mismatched UUID reuse denies. Provider callers must reserve an upper bound before submission and retain reservations after unknown outcomes.';

COMMIT;
