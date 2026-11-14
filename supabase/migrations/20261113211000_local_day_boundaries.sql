-- Streaks, the home screen and the buddy widget counted days in UTC, so for people in the
-- Americas an evening entry landed on the next day (a broken or skipped streak), and after
-- 7 or 8 PM Eastern the home screen showed no mood and no quest for "today".
--
-- profiles.timezone is the person's zone once the app has synced it (2.0 writes it on launch,
-- sign-in and when the device zone changes). Until then it is the 'UTC' default, which keeps
-- today's behaviour for people on older builds.
--
-- Each function below is changed in place: its live definition is read and only the date
-- expression is replaced, so the rest of each body stays exactly as deployed. Each replacement
-- checks that the expected text is present.

CREATE OR REPLACE FUNCTION public.user_time_zone(p_user_id uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT p.timezone FROM public.profiles p
      WHERE p.id = p_user_id
        AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = p.timezone)),
    'UTC');
$$;

CREATE OR REPLACE FUNCTION public.user_local_date(p_user_id uuid)
RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (pg_catalog.now() AT TIME ZONE public.user_time_zone(p_user_id))::date;
$$;

REVOKE ALL ON FUNCTION public.user_time_zone(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.user_local_date(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_time_zone(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.user_local_date(uuid) TO service_role;

-- Reminder and risk jobs read user_settings.timezone, which nothing ever wrote. Keep it equal to
-- the synced profile zone.
CREATE OR REPLACE FUNCTION public.mirror_profile_timezone()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.user_settings SET timezone = NEW.timezone
  WHERE user_id = NEW.id AND timezone IS DISTINCT FROM NEW.timezone;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.mirror_profile_timezone() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tr_mirror_profile_timezone ON public.profiles;
CREATE TRIGGER tr_mirror_profile_timezone
  AFTER UPDATE OF timezone ON public.profiles
  FOR EACH ROW WHEN (NEW.timezone IS DISTINCT FROM OLD.timezone)
  EXECUTE FUNCTION public.mirror_profile_timezone();

DO $$
DECLARE
  def text;
  changed text;
BEGIN
  -- Journal streak: read the profile's zone instead of journal_streaks' own 'UTC' copy.
  def := pg_get_functiondef('public.update_journal_streak()'::regprocedure);
  changed := regexp_replace(def,
    'SELECT COALESCE\(timezone, ''UTC''\) INTO user_tz\s+FROM journal_streaks\s+WHERE user_id = NEW\.user_id;',
    'user_tz := public.user_time_zone(NEW.user_id);');
  IF changed = def THEN RAISE EXCEPTION 'update_journal_streak: expected time zone lookup not found'; END IF;
  EXECUTE changed;

  -- Micro-moment streak.
  def := pg_get_functiondef('public.update_micro_streak()'::regprocedure);
  changed := replace(def, 'v_today := CURRENT_DATE;', 'v_today := public.user_local_date(NEW.user_id);');
  IF changed = def THEN RAISE EXCEPTION 'update_micro_streak: expected CURRENT_DATE not found'; END IF;
  EXECUTE changed;

  -- Recovery quest: quest streaks compare against the client's local quest date.
  def := pg_get_functiondef('public.complete_recovery_quest(uuid,uuid)'::regprocedure);
  changed := replace(def, 'last_quest_date = CURRENT_DATE::TEXT',
                          'last_quest_date = public.user_local_date(p_user_id)::TEXT');
  IF changed = def THEN RAISE EXCEPTION 'complete_recovery_quest: expected CURRENT_DATE not found'; END IF;
  EXECUTE changed;

  -- Home screen context: today's mood, today's quest, days since, daily recommendation seed.
  def := pg_get_functiondef('public.get_home_context(uuid)'::regprocedure);
  changed := replace(def, 'CURRENT_DATE', 'public.user_local_date(p_user_id)');
  IF changed = def THEN RAISE EXCEPTION 'get_home_context: expected CURRENT_DATE not found'; END IF;
  EXECUTE changed;

  -- Buddy widget: "completed today" and "needs a check-in" on the viewer's local day.
  def := pg_get_functiondef('public.get_buddy_widget_data(uuid)'::regprocedure);
  changed := replace(def, 'CURRENT_DATE', 'public.user_local_date(p_user_id)');
  IF changed = def THEN RAISE EXCEPTION 'get_buddy_widget_data: expected CURRENT_DATE not found'; END IF;
  EXECUTE changed;
END $$;
