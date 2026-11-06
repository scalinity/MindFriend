-- Reserve a conservative upper bound before each paid text call, including
-- titles/memory extraction. Zero/missing configuration never enables spending.
CREATE TABLE public.openai_daily_budget (
  day date PRIMARY KEY,
  reserved_microdollars bigint NOT NULL CHECK (reserved_microdollars >= 0)
);
ALTER TABLE public.openai_daily_budget ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.openai_daily_budget FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.openai_daily_budget TO service_role;

CREATE FUNCTION public.reserve_openai_budget(p_limit_cents integer, p_microdollars integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE changed integer;
BEGIN
  IF p_limit_cents IS NULL OR p_limit_cents < 0 OR p_limit_cents > 10000
     OR p_microdollars IS NULL OR p_microdollars <= 0 THEN
    RAISE EXCEPTION 'Invalid budget reservation' USING ERRCODE = '22023';
  END IF;
  IF p_limit_cents = 0 OR p_microdollars > p_limit_cents::bigint * 10000 THEN RETURN false; END IF;
  INSERT INTO public.openai_daily_budget (day,reserved_microdollars)
    VALUES ((now() AT TIME ZONE 'America/New_York')::date,p_microdollars)
    ON CONFLICT (day) DO UPDATE
      SET reserved_microdollars = openai_daily_budget.reserved_microdollars + excluded.reserved_microdollars
      WHERE openai_daily_budget.reserved_microdollars + excluded.reserved_microdollars <= p_limit_cents::bigint * 10000;
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed = 1;
END $$;
REVOKE ALL ON FUNCTION public.reserve_openai_budget(integer,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_openai_budget(integer,integer) TO service_role;
