BEGIN;

DO $$ BEGIN
  IF pg_catalog.to_regprocedure('companion_private.ingest_action(jsonb)') IS NULL
     OR pg_catalog.to_regprocedure('public.apply_mood_checkin(uuid,date,integer,integer,integer,text,timestamp with time zone)') IS NULL
     OR (SELECT count(*) FROM pg_catalog.pg_attribute
         WHERE attrelid=pg_catalog.to_regclass('public.moods')
           AND attname IN ('observed_at','last_event_at') AND NOT attisdropped) <> 2 THEN
    RAISE EXCEPTION 'Companion and canonical action migrations must be applied first' USING ERRCODE='55000';
  END IF;
END $$;

-- Phone and companion writes must compare the original event time, independent of
-- delivery order. Both mood clocks carry that same instant. New daily check-ins and
-- assigned quest completions use one state-change/reward transaction across devices.
CREATE OR REPLACE FUNCTION public.apply_mood_checkin(
  p_owner uuid, p_local_date date, p_mood integer, p_anxiety integer, p_energy integer,
  p_note text, p_event_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_id uuid; v_existing timestamptz; v_outcome text; v_xp integer := 0; v_level_up boolean := false;
  v_stats record;
BEGIN
  -- Every canonical writer, including offline sync, takes this lock before any
  -- day-row read/insert so companion score updates preserve the phone fields.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'mood_checkin:' || p_owner::text || ':' || p_local_date::text, 0));
  INSERT INTO public.moods (user_id, local_date, mood_score, anxiety_score, energy_score, note, created_at, last_event_at, observed_at, source)
  VALUES (p_owner, p_local_date, p_mood, p_anxiety, p_energy, p_note, p_event_at, p_event_at, p_event_at, 'manual')
  ON CONFLICT (user_id, local_date) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    v_outcome := 'created';
    -- Existing mood reward (10 XP, activity "mood"), only for a genuinely new day.
    SELECT a.level_up INTO v_level_up FROM public.award_xp(p_owner, 10, 'mood', NULL) a;
    v_xp := 10;
  ELSE
    SELECT m.id, COALESCE(m.last_event_at, m.created_at) INTO v_id, v_existing
      FROM public.moods m WHERE m.user_id = p_owner AND m.local_date = p_local_date FOR UPDATE;
    -- Strictly newer events win; older or equal ones never overwrite.
    IF p_event_at > v_existing THEN
      UPDATE public.moods SET mood_score = p_mood, anxiety_score = p_anxiety, energy_score = p_energy,
             note = p_note, last_event_at = p_event_at, observed_at = p_event_at
       WHERE id = v_id AND user_id = p_owner;
      v_outcome := 'updated';
    ELSE
      v_outcome := 'kept_existing';
    END IF;
  END IF;

  SELECT us.xp_total, us.level, us.level_title INTO v_stats FROM public.user_stats us WHERE us.user_id = p_owner;
  RETURN jsonb_build_object('outcome', v_outcome, 'mood_id', v_id, 'local_date', p_local_date,
    'xp_awarded', v_xp, 'level_up', COALESCE(v_level_up, false),
    'new_xp', v_stats.xp_total, 'new_level', v_stats.level, 'new_title', v_stats.level_title);
END;
$$;

CREATE OR REPLACE FUNCTION companion_private.ingest_action(p_action jsonb) RETURNS jsonb
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
  v_result jsonb;
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
    -- Use the same per-day order and reward transaction as phone online/offline writes.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
      'mood_checkin:' || v_owner::text || ':' || v_effective_day::text, 0));
    SELECT * INTO v_mood FROM public.moods
      WHERE user_id = v_owner AND local_date = v_effective_day FOR UPDATE;
    IF FOUND AND v_mood.observed_at IS NULL THEN
      v_status := 'preserved_existing';
    ELSIF FOUND AND v_mood.observed_at >= v_effective THEN
      v_status := 'preserved_newer';
    ELSE
      -- A companion mood changes only its score; preserve existing optional phone fields.
      v_result := public.apply_mood_checkin(v_owner, v_effective_day, v_score,
        v_mood.anxiety_score, v_mood.energy_score, v_mood.note, v_effective);
      IF v_result->>'outcome' = 'kept_existing' THEN v_status := 'preserved_newer'; END IF;
    END IF;
  ELSIF v_kind = 'quest' THEN
    PERFORM 1 FROM public.quests
    WHERE id = v_quest AND user_id = v_owner AND local_date = v_day::text FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Quest does not belong to this account and day' USING ERRCODE = '42501';
    END IF;
    PERFORM public.apply_quest_completion(v_owner, v_quest, v_effective, NULL, NULL);
  END IF;
  -- Breathing actions record completed cycles only; no duration, efficacy or physiology is invented.
  UPDATE public.companion_actions SET status = v_status WHERE event_id = v_id AND user_id = v_owner;
  RETURN jsonb_build_object('event_id', v_id, 'owner_id', v_owner, 'status', v_status);
END;
$$;

-- Existing grants remain unchanged by CREATE OR REPLACE. Internal mutation helpers
-- remain unavailable to clients; the companion wrapper still validates auth.uid().
COMMIT;
