-- Follow-ups to 20261113211000_local_day_boundaries.
--
-- 1. Switching a person from the 'UTC' default to their real zone can leave a streak's last date
--    one day ahead of their new local today (an evening entry in the Americas was stored as the
--    next UTC day). Comparing for equality then fell through to "streak broken". A last date on or
--    after local today now counts as today, so the switch never resets a streak.
-- 2. get_home_context subtracted UTC calendar dates of exercise and circle activity from the
--    local date. Those timestamps are now converted to the person's zone first.
--
-- As before, each live definition is read and only the expected text is replaced.

DO $$
DECLARE
  def text;
  changed text;
BEGIN
  def := pg_get_functiondef('public.update_journal_streak()'::regprocedure);
  changed := replace(def, 'IF last_date = user_today THEN', 'IF last_date >= user_today THEN');
  IF changed = def THEN RAISE EXCEPTION 'update_journal_streak: expected same-day check not found'; END IF;
  EXECUTE changed;

  def := pg_get_functiondef('public.update_micro_streak()'::regprocedure);
  changed := replace(def, 'ELSIF v_last_date = v_today THEN', 'ELSIF v_last_date >= v_today THEN');
  IF changed = def THEN RAISE EXCEPTION 'update_micro_streak: expected same-day check not found'; END IF;
  EXECUTE changed;

  def := pg_get_functiondef('public.get_home_context(uuid)'::regprocedure);
  changed := replace(replace(def,
    'MAX(completed_at)::date', '(MAX(completed_at) AT TIME ZONE public.user_time_zone(p_user_id))::date'),
    'MAX(created_at)::date', '(MAX(created_at) AT TIME ZONE public.user_time_zone(p_user_id))::date');
  IF changed = def OR position('MAX(completed_at) AT TIME ZONE' in changed) = 0
     OR position('MAX(created_at) AT TIME ZONE' in changed) = 0 THEN
    RAISE EXCEPTION 'get_home_context: expected activity date casts not found';
  END IF;
  EXECUTE changed;
END $$;
