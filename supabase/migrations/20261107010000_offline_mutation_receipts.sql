-- Owner-scoped idempotent receipts for work saved offline (mood, quest, exercise).
--
-- The iOS offline queue can deliver an item more than once: a crash after the
-- server accepted it, or a failed local save, replays it. Each item's stable
-- UUID is the operation ID. One authenticated transaction (a) serializes on
-- owner+operation, (b) returns the stored receipt untouched when the same
-- operation and normalized payload are replayed, (c) rejects the same operation
-- with a different kind/payload, and otherwise (d) performs the canonical write
-- and stores the receipt together.
--
-- It also establishes the canonical invariants the offline path needs:
--   * moods.last_event_at: one ordering time for accepted mood events, advanced
--     by a trigger for every writer (including older app builds).
--   * update_stats_on_quest_completion(): out-of-order quest dates no longer move
--     last_quest_date backward or reset the streak.
--   * apply_mood_checkin()/apply_quest_completion(): the single atomic save +
--     reward path, shared by offline sync and by the online callers
--     (save_mood_checkin / complete_quest_with_reward).
--   * update_challenge_progress_on_exercise(): reads exercises.type (the canonical
--     column) so inserting an exercise session works.
-- Additive: one new table, one new nullable column, new functions, and
-- CREATE OR REPLACE of two existing trigger functions. Reward amounts are unchanged.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$ BEGIN
  IF to_regprocedure('public.complete_exercise_session(uuid,integer,text)') IS NULL
     OR to_regprocedure('public.award_exercise_session_xp(uuid)') IS NULL
     OR to_regprocedure('public.award_xp(uuid,integer,text,text)') IS NULL
     OR to_regclass('public.moods') IS NULL
     OR to_regclass('public.quests') IS NULL
     OR to_regclass('public.exercise_sessions') IS NULL
     OR to_regclass('public.user_stats') IS NULL
     OR to_regclass('public.challenge_participants') IS NULL
     OR to_regprocedure('public.update_stats_on_quest_completion()') IS NULL
     OR to_regprocedure('public.update_challenge_progress_on_exercise()') IS NULL THEN
    RAISE EXCEPTION 'Offline receipts require the reviewed completion baseline';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Receipts: content-free (hash + IDs + small result), cascade with the account.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.offline_mutation_receipts (
  user_id       uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  operation_id  uuid        NOT NULL,
  kind          text        NOT NULL,
  payload_hash  text        NOT NULL,
  target_id     uuid,
  result        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation_id),
  CONSTRAINT offline_mutation_receipts_kind_check CHECK (kind IN ('mood', 'quest', 'exercise')),
  CONSTRAINT offline_mutation_receipts_hash_check CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT offline_mutation_receipts_result_check
    CHECK (jsonb_typeof(result) = 'object' AND pg_column_size(result) <= 2048)
);

COMMENT ON TABLE public.offline_mutation_receipts IS
  'Idempotency receipts for offline-queued mood/quest/exercise work. Content-free: payload hash, canonical record IDs and a small result only.';

ALTER TABLE public.offline_mutation_receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS offline_mutation_receipts_owner_select ON public.offline_mutation_receipts;
CREATE POLICY offline_mutation_receipts_owner_select ON public.offline_mutation_receipts
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
-- No INSERT/UPDATE/DELETE policy and no table write grant: receipts are written
-- only by sync_offline_mutation().

REVOKE ALL ON TABLE public.offline_mutation_receipts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.offline_mutation_receipts TO authenticated;
GRANT ALL ON TABLE public.offline_mutation_receipts TO service_role;

-- ---------------------------------------------------------------------------
-- Payload helpers (strict, no coercion). Internal: not granted to API roles.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.offline_mutation_int(p jsonb, k text, required boolean, lo bigint, hi bigint)
RETURNS bigint LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v jsonb := p -> k;
  n numeric;
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN
    IF required THEN RAISE EXCEPTION 'INVALID_PAYLOAD: % is required', k USING ERRCODE = '22023'; END IF;
    RETURN NULL;
  END IF;
  IF jsonb_typeof(v) <> 'number' THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: % must be a number', k USING ERRCODE = '22023';
  END IF;
  n := (v #>> '{}')::numeric;
  IF n <> trunc(n) OR n < lo OR n > hi THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: % out of range', k USING ERRCODE = '22023';
  END IF;
  RETURN n::bigint;
END $$;

CREATE OR REPLACE FUNCTION public.offline_mutation_text(p jsonb, k text, max_chars integer)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE v jsonb := p -> k; s text;
BEGIN
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN RETURN NULL; END IF;
  IF jsonb_typeof(v) <> 'string' THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: % must be text', k USING ERRCODE = '22023';
  END IF;
  s := v #>> '{}';
  IF s = '' THEN RETURN NULL; END IF;
  IF char_length(s) > max_chars THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: % too long', k USING ERRCODE = '22023';
  END IF;
  RETURN s;
END $$;

CREATE OR REPLACE FUNCTION public.offline_mutation_uuid(p jsonb, k text)
RETURNS uuid LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE v jsonb := p -> k; s text;
BEGIN
  IF v IS NULL OR jsonb_typeof(v) <> 'string' THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: % must be a UUID', k USING ERRCODE = '22023';
  END IF;
  s := lower(v #>> '{}');
  IF s !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: % must be a UUID', k USING ERRCODE = '22023';
  END IF;
  RETURN s::uuid;
END $$;

CREATE OR REPLACE FUNCTION public.offline_mutation_only_keys(p jsonb, allowed text[])
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF NOT (k = ANY (allowed)) THEN
      RAISE EXCEPTION 'INVALID_PAYLOAD: unknown field' USING ERRCODE = '22023';
    END IF;
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.offline_mutation_int(jsonb, text, boolean, bigint, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_mutation_text(jsonb, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_mutation_uuid(jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.offline_mutation_only_keys(jsonb, text[]) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- OR06: exercise-session insert trigger referenced exercises.exercise_type, a
-- column that does not exist (the canonical column is exercises.type), so any
-- exercise_sessions INSERT failed. Same body as 20260131030000 with the column
-- fixed; challenges.exercise_type is text, so compare against type::text.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_challenge_progress_on_exercise() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_duration_minutes INTEGER;
BEGIN
    SELECT duration_minutes INTO v_duration_minutes
    FROM public.exercises
    WHERE id = NEW.exercise_id;

    UPDATE public.challenge_participants
    SET current_progress = current_progress + COALESCE(v_duration_minutes, 0)
    WHERE challenge_id IN (
        SELECT c.id FROM public.challenges c
        WHERE c.challenge_type = 'minutes'
        AND c.exercise_type = (
            SELECT e.type::text FROM public.exercises e WHERE e.id = NEW.exercise_id
        )
        AND c.ends_at > NOW()
    )
    AND user_id = NEW.user_id
    AND EXISTS (
        SELECT 1 FROM public.challenges c
        WHERE c.id = challenge_participants.challenge_id
        AND c.starts_at <= NOW()
    );

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- OR01: one canonical ordering time for accepted mood events.
-- NULL means "never edited since creation": readers use COALESCE(last_event_at,
-- created_at), so no table rewrite or backfill is needed. A live edit by ANY
-- writer (older app builds included) that changes the check-in content advances
-- it to now() unless the writer supplied a newer value itself (the offline path).
-- ---------------------------------------------------------------------------
ALTER TABLE public.moods ADD COLUMN IF NOT EXISTS last_event_at timestamptz;

CREATE OR REPLACE FUNCTION public.moods_advance_event_time() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.last_event_at := COALESCE(NEW.last_event_at, now());
  ELSIF (NEW.mood_score, NEW.anxiety_score, NEW.energy_score, NEW.note)
        IS DISTINCT FROM (OLD.mood_score, OLD.anxiety_score, OLD.energy_score, OLD.note)
        AND NEW.last_event_at IS NOT DISTINCT FROM OLD.last_event_at THEN
    NEW.last_event_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS moods_advance_event_time ON public.moods;
CREATE TRIGGER moods_advance_event_time BEFORE INSERT OR UPDATE ON public.moods
  FOR EACH ROW EXECUTE FUNCTION public.moods_advance_event_time();

-- ---------------------------------------------------------------------------
-- OR02: out-of-order quest completion. Same function as v3 (20260130233000:
-- caller validation, bounded locks, NOWAIT fallback) with one change: a quest
-- older than last_quest_date no longer moves last_quest_date backward or resets
-- the streak. The completion still counts exactly once. The streak only grows
-- when the late quest genuinely connects consecutive days (gap filling);
-- shield-protected streaks are never reduced.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_stats_on_quest_completion() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  ONE_DAY CONSTANT INTERVAL := INTERVAL '1 day';
  LOCK_TIMEOUT_MS CONSTANT INT := 5000;
  quest_date DATE;
  yesterday_date DATE;
  last_quest DATE;
  current_streak INT := 0;
  longest_streak INT := 0;
  new_streak INT;
  new_last DATE;
  run_length INT;
  lock_acquired BOOLEAN;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    IF auth.uid() IS NULL THEN
      IF current_setting('role', true) != 'service_role' THEN
        RAISE EXCEPTION 'Quest completion trigger called without authenticated user context'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
    ELSIF auth.uid() != NEW.user_id THEN
      RAISE EXCEPTION 'Quest completion trigger: authenticated user does not match quest owner'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NEW.user_id IS NULL THEN
      RAISE EXCEPTION 'Quest completion trigger received NULL user_id for quest %', NEW.id
        USING ERRCODE = 'not_null_violation';
    END IF;

    BEGIN
      quest_date := NEW.local_date::DATE;
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format THEN
      RAISE EXCEPTION 'Quest % has invalid local_date format (length: % chars), cannot process completion',
        NEW.id, length(COALESCE(NEW.local_date, ''))
        USING ERRCODE = 'invalid_datetime_format';
    END;

    yesterday_date := quest_date - ONE_DAY;

    lock_acquired := pg_try_advisory_xact_lock(hashtext('user_stats_' || NEW.user_id::text));
    IF NOT lock_acquired THEN
      EXECUTE format('SET LOCAL lock_timeout = %L', LOCK_TIMEOUT_MS || 'ms');
      BEGIN
        PERFORM pg_advisory_xact_lock(hashtext('user_stats_' || NEW.user_id::text));
        lock_acquired := TRUE;
      EXCEPTION WHEN lock_not_available THEN
        RAISE WARNING 'Advisory lock timeout after %ms, proceeding without lock', LOCK_TIMEOUT_MS;
        lock_acquired := FALSE;
      END;
    END IF;

    BEGIN
      SELECT last_quest_date::DATE, COALESCE(current_streak_days, 0), COALESCE(longest_streak_days, 0)
      INTO last_quest, current_streak, longest_streak
      FROM user_stats WHERE user_id = NEW.user_id FOR UPDATE NOWAIT;
    EXCEPTION
      WHEN lock_not_available THEN
        RAISE WARNING 'Row lock unavailable, using optimistic update';
        SELECT last_quest_date::DATE, COALESCE(current_streak_days, 0), COALESCE(longest_streak_days, 0)
        INTO last_quest, current_streak, longest_streak
        FROM user_stats WHERE user_id = NEW.user_id;
      WHEN invalid_text_representation OR invalid_datetime_format THEN
        RAISE WARNING 'Malformed stored date for user (length: % chars), treating as first quest',
          length(COALESCE((SELECT last_quest_date FROM user_stats WHERE user_id = NEW.user_id), ''));
        last_quest := NULL;
        current_streak := 0;
        longest_streak := 0;
    END;

    new_last := quest_date;
    IF last_quest IS NULL THEN
      new_streak := 1;
    ELSIF last_quest = yesterday_date THEN
      new_streak := current_streak + 1;
    ELSIF last_quest = quest_date THEN
      RAISE WARNING 'Same-day quest completion detected for user, streak unchanged';
      new_streak := GREATEST(current_streak, 1);
    ELSIF quest_date < last_quest THEN
      -- Out of order: keep the later last_quest_date; count the completion once.
      new_last := last_quest;
      new_streak := GREATEST(current_streak, 1);
      BEGIN
        -- Consecutive completed days ending at last_quest_date (gap-filling).
        WITH d AS (
          SELECT DISTINCT (CASE WHEN q.local_date ~ '^\d{4}-\d{2}-\d{2}$' THEN q.local_date::date END) AS day
          FROM quests q
          WHERE q.user_id = NEW.user_id AND q.status = 'completed'
        ), days AS (
          SELECT day, day - (row_number() OVER (ORDER BY day))::int AS grp
          FROM d WHERE day IS NOT NULL AND day <= last_quest
        )
        SELECT count(*)::int INTO run_length FROM days
        WHERE grp = (SELECT grp FROM days WHERE day = last_quest);
        new_streak := GREATEST(new_streak, COALESCE(run_length, 0));
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Streak recomputation skipped (error code: %)', SQLSTATE;
      END;
    ELSE
      new_streak := 1;
    END IF;

    longest_streak := GREATEST(longest_streak, new_streak);

    BEGIN
      INSERT INTO user_stats (user_id, current_streak_days, longest_streak_days, total_quests_completed, last_quest_date, updated_at)
      VALUES (NEW.user_id, new_streak, longest_streak, 1, new_last::TEXT, NOW())
      ON CONFLICT (user_id) DO UPDATE SET
        current_streak_days = EXCLUDED.current_streak_days,
        longest_streak_days = EXCLUDED.longest_streak_days,
        total_quests_completed = user_stats.total_quests_completed + 1,
        last_quest_date = EXCLUDED.last_quest_date,
        updated_at = NOW();
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Stats update failed (error code: %), quest completion proceeding', SQLSTATE;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- The ONE atomic save + reward path for mood check-ins and quest completion.
-- Internal (not granted to API roles); wrapped by sync_offline_mutation and by
-- the online RPCs save_mood_checkin / complete_quest_with_reward. The reward is
-- paid in the same transaction as, and only on, the real state change, so no
-- caller ordering (offline-first, online-first, concurrent) can pay twice.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.apply_mood_checkin(
  p_owner uuid, p_local_date date, p_mood integer, p_anxiety integer, p_energy integer,
  p_note text, p_event_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_id uuid; v_existing timestamptz; v_outcome text; v_xp integer := 0; v_level_up boolean := false;
  v_stats record;
BEGIN
  INSERT INTO public.moods (user_id, local_date, mood_score, anxiety_score, energy_score, note, created_at, last_event_at, source)
  VALUES (p_owner, p_local_date, p_mood, p_anxiety, p_energy, p_note, p_event_at, p_event_at, 'manual')
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
             note = p_note, last_event_at = p_event_at
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

CREATE OR REPLACE FUNCTION public.apply_quest_completion(
  p_owner uuid, p_quest_id uuid, p_completed_at timestamptz, p_note text, p_rating integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_quest public.quests%ROWTYPE; v_outcome text; v_xp integer := 0; v_level_up boolean := false; v_stats record;
BEGIN
  SELECT * INTO v_quest FROM public.quests WHERE id = p_quest_id AND user_id = p_owner FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = '42501'; END IF;
  IF v_quest.status = 'completed' THEN
    v_outcome := 'already_completed';       -- whoever completed it first already paid
  ELSIF v_quest.status = 'assigned' THEN
    -- Same transition the app always used; the stats trigger fires on it.
    UPDATE public.quests
       SET status = 'completed',
           completed_at = LEAST(now(), GREATEST(p_completed_at, v_quest.assigned_at)),
           reflection_note = COALESCE(p_note, reflection_note),
           rating = COALESCE(p_rating, rating)
     WHERE id = v_quest.id AND user_id = p_owner;
    -- Existing quest reward (50 XP, activity "quest"), once per transition.
    SELECT a.level_up INTO v_level_up FROM public.award_xp(p_owner, 50, 'quest', NULL) a;
    v_xp := 50;
    v_outcome := 'completed';
  ELSE
    RAISE EXCEPTION 'STATE_REJECTED: quest cannot be completed from its current state' USING ERRCODE = '22023';
  END IF;
  SELECT us.xp_total, us.level, us.level_title INTO v_stats FROM public.user_stats us WHERE us.user_id = p_owner;
  RETURN jsonb_build_object('outcome', v_outcome, 'quest_id', v_quest.id, 'xp_awarded', v_xp,
    'level_up', COALESCE(v_level_up, false),
    'new_xp', v_stats.xp_total, 'new_level', v_stats.level, 'new_title', v_stats.level_title);
END;
$$;

REVOKE ALL ON FUNCTION public.apply_mood_checkin(uuid, date, integer, integer, integer, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_quest_completion(uuid, uuid, timestamptz, text, integer) FROM PUBLIC, anon, authenticated;

-- Online callers: same transaction, same reward rules.
CREATE OR REPLACE FUNCTION public.save_mood_checkin(
  p_local_date date, p_mood_score integer, p_anxiety_score integer DEFAULT NULL,
  p_energy_score integer DEFAULT NULL, p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_owner uuid := auth.uid();
BEGIN
  IF v_owner IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  IF p_local_date IS NULL OR p_local_date < (now() - interval '400 days')::date OR p_local_date > (now() + interval '2 days')::date
     OR p_mood_score IS NULL OR p_mood_score NOT BETWEEN 1 AND 10
     OR (p_anxiety_score IS NOT NULL AND p_anxiety_score NOT BETWEEN 1 AND 10)
     OR (p_energy_score IS NOT NULL AND p_energy_score NOT BETWEEN 1 AND 10)
     OR (p_note IS NOT NULL AND char_length(p_note) > 4000) THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: invalid mood check-in' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('mood_checkin:' || v_owner::text || ':' || p_local_date::text, 0));
  RETURN public.apply_mood_checkin(v_owner, p_local_date, p_mood_score, p_anxiety_score, p_energy_score,
                                   NULLIF(p_note, ''), now());
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_quest_with_reward(
  p_quest_id uuid, p_reflection_note text DEFAULT NULL, p_rating integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_owner uuid := auth.uid();
BEGIN
  IF v_owner IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  IF p_quest_id IS NULL OR (p_rating IS NOT NULL AND p_rating NOT BETWEEN 1 AND 5)
     OR (p_reflection_note IS NOT NULL AND char_length(p_reflection_note) > 4000) THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: invalid quest completion' USING ERRCODE = '22023';
  END IF;
  RETURN public.apply_quest_completion(v_owner, p_quest_id, now(), NULLIF(p_reflection_note, ''), p_rating);
END;
$$;

REVOKE ALL ON FUNCTION public.save_mood_checkin(date, integer, integer, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_quest_with_reward(uuid, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_mood_checkin(date, integer, integer, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_quest_with_reward(uuid, text, integer) TO authenticated;

-- ---------------------------------------------------------------------------
-- The one authenticated entry point.
--
-- Error contract (MESSAGE starts with a stable tag):
--   42501 AUTH_REQUIRED / OWNER_MISMATCH / NOT_FOUND   -> never retry
--   22023 INVALID_PAYLOAD / STATE_REJECTED             -> never retry
--   MF409 IDEMPOTENCY_CONFLICT                         -> never retry
-- Any other failure rolls the whole transaction back and is safe to retry.
--
-- SECURITY DEFINER only so the receipt table can stay write-protected for API
-- roles. Ownership always comes from auth.uid(); p_expected_owner is only a
-- caller assertion compared with it (it does not pin a token). Every referenced
-- record is checked against that owner. Nested canonical functions re-read auth.uid().
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_offline_mutation(
  p_expected_owner uuid,
  p_operation_id   uuid,
  p_kind           text,
  p_payload        jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_owner     uuid := auth.uid();
  v_now       timestamptz := now();
  v_norm      jsonb;
  v_hash      text;
  v_ms        bigint;
  v_recorded  timestamptz;
  v_receipt   public.offline_mutation_receipts%ROWTYPE;
  v_target    uuid;
  v_result    jsonb;
  v_created   timestamptz;
  -- mood
  v_tz        text;
  v_local     date;
  v_apply     jsonb;
  v_level_up  boolean;
  -- exercise
  v_exercise_id uuid;
  v_duration  integer;
  v_session   uuid;
  v_xp_amount integer;
BEGIN
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_expected_owner IS DISTINCT FROM v_owner THEN
    RAISE EXCEPTION 'OWNER_MISMATCH' USING ERRCODE = '42501';
  END IF;
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: operation id is required' USING ERRCODE = '22023';
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('mood', 'quest', 'exercise') THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: unsupported kind' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR pg_column_size(p_payload) > 16384 THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: payload must be a bounded object' USING ERRCODE = '22023';
  END IF;
  IF p_payload -> 'schema_version' IS DISTINCT FROM '1'::jsonb THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: unsupported schema version' USING ERRCODE = '22023';
  END IF;

  -- Shape validation and normalization are pure: nothing is read or written yet.
  IF p_kind = 'mood' THEN
    PERFORM public.offline_mutation_only_keys(p_payload,
      ARRAY['schema_version', 'mood_score', 'anxiety_score', 'energy_score', 'note', 'recorded_at_ms']);
    v_ms := public.offline_mutation_int(p_payload, 'recorded_at_ms', true, 0, 4102444800000);
    v_norm := jsonb_build_object(
      'mood_score',    public.offline_mutation_int(p_payload, 'mood_score', true, 1, 10),
      'anxiety_score', public.offline_mutation_int(p_payload, 'anxiety_score', false, 1, 10),
      'energy_score',  public.offline_mutation_int(p_payload, 'energy_score', false, 1, 10),
      'note',          public.offline_mutation_text(p_payload, 'note', 4000),
      'recorded_at_ms', v_ms);
  ELSIF p_kind = 'quest' THEN
    PERFORM public.offline_mutation_only_keys(p_payload, ARRAY['schema_version', 'quest_id', 'completed_at_ms']);
    v_ms := public.offline_mutation_int(p_payload, 'completed_at_ms', true, 0, 4102444800000);
    v_norm := jsonb_build_object(
      'quest_id', public.offline_mutation_uuid(p_payload, 'quest_id')::text,
      'completed_at_ms', v_ms);
  ELSE
    PERFORM public.offline_mutation_only_keys(p_payload,
      ARRAY['schema_version', 'exercise_id', 'duration_seconds', 'completed_at_ms']);
    v_ms := public.offline_mutation_int(p_payload, 'completed_at_ms', true, 0, 4102444800000);
    v_norm := jsonb_build_object(
      'exercise_id', public.offline_mutation_uuid(p_payload, 'exercise_id')::text,
      'duration_seconds', public.offline_mutation_int(p_payload, 'duration_seconds', true, 1, 21600),
      'completed_at_ms', v_ms);
  END IF;

  v_hash := encode(sha256(convert_to(
    jsonb_build_object('schema_version', 1, 'kind', p_kind, 'payload', v_norm)::text, 'UTF8')), 'hex');

  -- Serialize this owner+operation; retries wait here and then see the receipt.
  PERFORM pg_advisory_xact_lock(hashtextextended('offline_mutation:' || v_owner::text || ':' || p_operation_id::text, 0));

  SELECT * INTO v_receipt FROM public.offline_mutation_receipts
   WHERE user_id = v_owner AND operation_id = p_operation_id;
  IF FOUND THEN
    IF v_receipt.kind <> p_kind OR v_receipt.payload_hash <> v_hash THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = 'MF409';
    END IF;
    -- Exact canonical receipt, before any other work.
    RETURN jsonb_build_object(
      'schema_version', 1, 'operation_id', p_operation_id, 'kind', v_receipt.kind,
      'replayed', true, 'target_id', v_receipt.target_id, 'result', v_receipt.result,
      'payload_hash', v_receipt.payload_hash, 'created_at', v_receipt.created_at);
  END IF;

  -- Semantic bounds (only for first application).
  v_recorded := to_timestamp(v_ms / 1000.0);
  IF v_ms < 1577836800000 OR v_recorded > v_now + interval '5 minutes' OR v_recorded < v_now - interval '400 days' THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD: timestamp out of range' USING ERRCODE = '22023';
  END IF;

  -- Offline events are stamped no later than the sync time.
  v_recorded := LEAST(v_recorded, v_now);

  IF p_kind = 'mood' THEN
    -- Local day comes from the owner's stored time zone so a retry never depends
    -- on the device's current zone.
    SELECT p.timezone INTO v_tz FROM public.profiles p WHERE p.id = v_owner;
    IF v_tz IS NULL OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names n WHERE n.name = v_tz) THEN
      v_tz := 'UTC';
    END IF;
    v_local := (v_recorded AT TIME ZONE v_tz)::date;
    -- Shared atomic path: creation pays the 10 XP check-in reward once; updates and
    -- replays pay nothing; the strictly newest accepted event wins the day.
    v_apply := public.apply_mood_checkin(v_owner, v_local, (v_norm ->> 'mood_score')::integer,
      (v_norm ->> 'anxiety_score')::integer, (v_norm ->> 'energy_score')::integer, v_norm ->> 'note', v_recorded);
    v_target := (v_apply ->> 'mood_id')::uuid;
    v_result := jsonb_build_object('outcome', v_apply ->> 'outcome', 'local_date', v_apply ->> 'local_date',
                                   'xp_awarded', (v_apply ->> 'xp_awarded')::integer);

  ELSIF p_kind = 'quest' THEN
    v_apply := public.apply_quest_completion(v_owner, (v_norm ->> 'quest_id')::uuid, v_recorded, NULL, NULL);
    v_target := (v_apply ->> 'quest_id')::uuid;
    v_result := jsonb_build_object('outcome', v_apply ->> 'outcome', 'xp_awarded', (v_apply ->> 'xp_awarded')::integer,
                                   'level_up', (v_apply ->> 'level_up')::boolean);

  ELSE
    v_exercise_id := (v_norm ->> 'exercise_id')::uuid;
    v_duration := (v_norm ->> 'duration_seconds')::integer;
    IF NOT EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = v_exercise_id) THEN
      RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = '42501';
    END IF;
    -- One real canonical session per operation: created, completed and rewarded
    -- in this transaction together with the receipt.
    INSERT INTO public.exercise_sessions (user_id, exercise_id, started_at)
    VALUES (v_owner, v_exercise_id, v_recorded - make_interval(secs => v_duration))
    RETURNING id INTO v_session;

    PERFORM public.complete_exercise_session(v_session, NULL, NULL);
    -- Record the real completion time instead of the sync time.
    UPDATE public.exercise_sessions
       SET completed_at = LEAST(v_now, v_recorded), ended_at = LEAST(v_now, v_recorded)
     WHERE id = v_session AND user_id = v_owner;

    SELECT a.amount, a.level_up INTO v_xp_amount, v_level_up
      FROM public.award_exercise_session_xp(v_session) a;
    v_target := v_session;
    v_result := jsonb_build_object('outcome', 'completed', 'xp_awarded', COALESCE(v_xp_amount, 0),
                                   'level_up', COALESCE(v_level_up, false));
  END IF;

  INSERT INTO public.offline_mutation_receipts (user_id, operation_id, kind, payload_hash, target_id, result)
  VALUES (v_owner, p_operation_id, p_kind, v_hash, v_target, v_result)
  RETURNING created_at INTO v_created;

  RETURN jsonb_build_object(
    'schema_version', 1, 'operation_id', p_operation_id, 'kind', p_kind,
    'replayed', false, 'target_id', v_target, 'result', v_result,
    'payload_hash', v_hash, 'created_at', v_created);
END;
$$;

REVOKE ALL ON FUNCTION public.sync_offline_mutation(uuid, uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_offline_mutation(uuid, uuid, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.sync_offline_mutation(uuid, uuid, text, jsonb) IS
  'Idempotent, owner-scoped application of offline mood/quest/exercise work. Receipt before work; same operation with a different kind/payload is rejected (MF409).';

COMMIT;
