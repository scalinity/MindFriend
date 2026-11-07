-- Widget/Watch actions keep their original identity until an authenticated receipt is saved.
CREATE SCHEMA IF NOT EXISTS companion_private;
REVOKE ALL ON SCHEMA companion_private FROM PUBLIC;
GRANT USAGE ON SCHEMA companion_private TO authenticated;

ALTER TABLE public.moods ADD COLUMN observed_at timestamptz;
COMMENT ON COLUMN public.moods.observed_at IS
  'Time of a known check-in write. NULL on historical rows whose last edit time is unknown.';

CREATE FUNCTION companion_private.stamp_mood_observation() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.observed_at := LEAST(COALESCE(NEW.observed_at, clock_timestamp()), clock_timestamp());
  ELSIF NEW.observed_at IS NOT DISTINCT FROM OLD.observed_at THEN
    NEW.observed_at := clock_timestamp();
  ELSE
    NEW.observed_at := LEAST(COALESCE(NEW.observed_at, clock_timestamp()), clock_timestamp());
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION companion_private.stamp_mood_observation() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER stamp_mood_observation BEFORE INSERT OR UPDATE ON public.moods
FOR EACH ROW EXECUTE FUNCTION companion_private.stamp_mood_observation();

CREATE TABLE public.companion_actions (
  event_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('mood', 'quest', 'breathing')),
  body jsonb NOT NULL,
  observed_at timestamptz NOT NULL,
  local_date date NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'applied', 'preserved_newer', 'preserved_existing'))
);
CREATE INDEX companion_actions_owner_day ON public.companion_actions(user_id, local_date, kind);
ALTER TABLE public.companion_actions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.companion_actions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.companion_actions TO authenticated;
CREATE POLICY companion_actions_owner_read ON public.companion_actions FOR SELECT TO authenticated
USING (user_id = (SELECT auth.uid()));

-- This private helper alone can write receipts. The public wrapper keeps the RPC surface invoker-only.
CREATE FUNCTION companion_private.ingest_action(p_action jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_id uuid := (p_action->>'event_id')::uuid;
  v_kind text := p_action->>'kind';
  v_observed timestamptz := (p_action->>'observed_at')::timestamptz;
  v_day date := (p_action->>'local_date')::date;
  v_zone text := p_action->>'time_zone';
  v_score integer := (p_action->>'mood_score')::integer;
  v_quest uuid := (p_action->>'quest_id')::uuid;
  v_cycles integer := (p_action->>'breathing_cycles')::integer;
  v_row public.companion_actions%ROWTYPE;
  v_mood public.moods%ROWTYPE;
  v_effective timestamptz;
  v_effective_day date;
  v_inserted uuid;
  v_status text := 'applied';
BEGIN
  IF v_owner IS NULL OR (p_action->>'owner_id')::uuid IS DISTINCT FROM v_owner THEN
    RAISE EXCEPTION 'Companion action belongs to another account' USING ERRCODE = '42501';
  END IF;
  IF v_id IS NULL OR v_kind IS NULL OR v_kind NOT IN ('mood', 'quest', 'breathing')
     OR v_observed IS NULL OR NOT isfinite(v_observed) OR v_day IS NULL
     OR v_zone IS NULL OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_zone) THEN
    RAISE EXCEPTION 'Invalid companion action' USING ERRCODE = '22023';
  END IF;
  IF (v_observed AT TIME ZONE v_zone)::date <> v_day
     OR (v_kind = 'mood' AND (v_score IS NULL OR v_score NOT BETWEEN 1 AND 5 OR v_quest IS NOT NULL OR v_cycles IS NOT NULL))
     OR (v_kind = 'quest' AND (v_quest IS NULL OR v_score IS NOT NULL OR v_cycles IS NOT NULL))
     OR (v_kind = 'breathing' AND (v_cycles IS NULL OR v_cycles NOT BETWEEN 1 AND 100 OR v_score IS NOT NULL OR v_quest IS NOT NULL)) THEN
    RAISE EXCEPTION 'Invalid companion action details' USING ERRCODE = '22023';
  END IF;

  -- A future device clock cannot pin a daily mood ahead of later app writes.
  -- The original date/time stay intact in body for exact retries.
  v_effective := LEAST(v_observed, clock_timestamp());
  v_effective_day := (v_effective AT TIME ZONE v_zone)::date;
  INSERT INTO public.companion_actions(event_id, user_id, kind, body, observed_at, local_date)
  VALUES (v_id, v_owner, v_kind, p_action, v_effective, v_effective_day)
  ON CONFLICT (event_id) DO NOTHING
  RETURNING event_id INTO v_inserted;
  IF v_inserted IS NULL THEN
    SELECT * INTO STRICT v_row FROM public.companion_actions WHERE event_id = v_id FOR UPDATE;
    IF v_row.user_id <> v_owner OR v_row.body <> p_action OR v_row.status = 'pending' THEN
      RAISE EXCEPTION 'Conflicting companion action identity' USING ERRCODE = '22023';
    END IF;
    RETURN jsonb_build_object('event_id', v_id, 'owner_id', v_owner, 'status', v_row.status);
  END IF;

  IF v_kind = 'mood' THEN
    v_inserted := NULL;
    INSERT INTO public.moods(id, user_id, local_date, mood_score, source, observed_at)
    VALUES (v_id, v_owner, v_effective_day, v_score, 'manual', v_effective)
    ON CONFLICT (user_id, local_date) DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NULL THEN
      SELECT * INTO STRICT v_mood FROM public.moods
      WHERE user_id = v_owner AND local_date = v_effective_day FOR UPDATE;
      IF v_mood.observed_at IS NULL THEN
        -- Never fabricate the last edit time of an existing historical row.
        v_status := 'preserved_existing';
      ELSIF v_mood.observed_at >= v_effective THEN
        v_status := 'preserved_newer';
      ELSE
        UPDATE public.moods SET mood_score = v_score, observed_at = v_effective
        WHERE id = v_mood.id AND user_id = v_owner;
      END IF;
    END IF;
  ELSIF v_kind = 'quest' THEN
    PERFORM 1 FROM public.quests
    WHERE id = v_quest AND user_id = v_owner AND local_date = v_day::text FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Quest does not belong to this account and day' USING ERRCODE = '42501';
    END IF;
    UPDATE public.quests SET status = 'completed', completed_at = v_effective
    WHERE id = v_quest AND user_id = v_owner AND status <> 'completed';
  END IF;
  -- Breathing actions record completed cycles only; no duration, efficacy or physiology is invented.
  UPDATE public.companion_actions SET status = v_status WHERE event_id = v_id AND user_id = v_owner;
  RETURN jsonb_build_object('event_id', v_id, 'owner_id', v_owner, 'status', v_status);
END;
$$;
REVOKE ALL ON FUNCTION companion_private.ingest_action(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION companion_private.ingest_action(jsonb) TO authenticated;

CREATE FUNCTION public.ingest_companion_action(p_action jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$
  SELECT companion_private.ingest_action(p_action);
$$;
REVOKE ALL ON FUNCTION public.ingest_companion_action(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_companion_action(jsonb) TO authenticated;

CREATE FUNCTION public.get_companion_day_summary(p_local_date date, p_time_zone text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  result jsonb;
  day_start timestamptz;
  day_end timestamptz;
  week_start timestamptz;
BEGIN
  IF auth.uid() IS NULL OR p_local_date IS NULL OR p_time_zone IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_time_zone) THEN
    RAISE EXCEPTION 'Invalid companion summary request' USING ERRCODE = '22023';
  END IF;
  day_start := p_local_date::timestamp AT TIME ZONE p_time_zone;
  day_end := (p_local_date + 1)::timestamp AT TIME ZONE p_time_zone;
  week_start := (p_local_date - 6)::timestamp AT TIME ZONE p_time_zone;
  SELECT jsonb_build_object('breathing_count', count(*), 'last_breathing_at', max(observed_at)) INTO result
  FROM public.companion_actions
  WHERE user_id = (SELECT auth.uid()) AND local_date = p_local_date AND kind = 'breathing' AND status = 'applied';
  RETURN result || (
    SELECT jsonb_build_object('today_exercise_count', count(*) FILTER (WHERE completed_at >= day_start),
      'weekly_exercise_count', count(*) + (
        SELECT count(*) FROM public.companion_actions
        WHERE user_id = (SELECT auth.uid()) AND local_date BETWEEN p_local_date - 6 AND p_local_date
          AND kind = 'breathing' AND status = 'applied'
      ))
    FROM public.exercise_sessions
    WHERE user_id = (SELECT auth.uid()) AND completed_at >= week_start AND completed_at < day_end
  );
END;
$$;
REVOKE ALL ON FUNCTION public.get_companion_day_summary(date,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_companion_day_summary(date,text) TO authenticated;
