-- Follow-up to 20261114000000_local_day_follow_ups. A last streak date ahead of local today (left
-- by the switch from the UTC default) counts as today, but stayed stored as the future date, so
-- an entry on the next local day matched neither "today" nor "yesterday" and could not extend the
-- streak. The same-day branch now also brings the stored date back to local today.

DO $$
DECLARE
  def text;
  changed text;
BEGIN
  def := pg_get_functiondef('public.update_journal_streak()'::regprocedure);
  changed := regexp_replace(def, 'SET\s+total_entries\s*=\s*total\s*\+\s*1\s*,',
    'SET total_entries = total + 1, last_entry_date = LEAST(last_entry_date, user_today),');
  IF changed = def THEN RAISE EXCEPTION 'update_journal_streak: expected same-day update not found'; END IF;
  EXECUTE changed;

  def := pg_get_functiondef('public.update_micro_streak()'::regprocedure);
  changed := regexp_replace(def, 'SET\s+total_micro_moments\s*=\s*total_micro_moments\s*\+\s*1\s*,',
    'SET total_micro_moments = total_micro_moments + 1, last_micro_date = LEAST(last_micro_date, v_today),');
  IF changed = def THEN RAISE EXCEPTION 'update_micro_streak: expected same-day update not found'; END IF;
  EXECUTE changed;
END $$;
