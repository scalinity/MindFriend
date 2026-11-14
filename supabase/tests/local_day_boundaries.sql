-- Synthetic rollback fixture: days are counted in the person's synced zone.
-- The zone is chosen so its date differs from the UTC date right now (UTC+14 in the second
-- half of the UTC day, UTC-11 in the first), so the checks below never pass by coincidence.
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17400000-0000-4000-8000-000000000001', 'local-day@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES ('17400000-0000-4000-8000-000000000001') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.user_settings(user_id) VALUES ('17400000-0000-4000-8000-000000000001') ON CONFLICT DO NOTHING;

DO $$
DECLARE
  uid constant uuid := '17400000-0000-4000-8000-000000000001';
  -- Whichever of UTC+14 or UTC-11 has a different date from UTC right now (one always does).
  zone text := CASE WHEN (now() AT TIME ZONE 'Pacific/Kiritimati')::date <> (now() AT TIME ZONE 'UTC')::date
                    THEN 'Pacific/Kiritimati' ELSE 'Pacific/Pago_Pago' END;
  local_today date;
  streak_day date;
BEGIN
  -- The default is unknown, and is treated as UTC.
  IF public.user_local_date(uid) <> (now() AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'Unsynced profile should count UTC days';
  END IF;

  -- The app syncs the device zone.
  UPDATE public.profiles SET timezone = zone WHERE id = uid;
  local_today := (now() AT TIME ZONE zone)::date;
  IF local_today = (now() AT TIME ZONE 'UTC')::date THEN RAISE EXCEPTION 'Fixture zone is not far enough'; END IF;
  IF public.user_local_date(uid) <> local_today THEN
    RAISE EXCEPTION 'user_local_date % is not the local date %', public.user_local_date(uid), local_today;
  END IF;
  IF (SELECT timezone FROM public.user_settings WHERE user_id = uid) <> zone THEN
    RAISE EXCEPTION 'user_settings.timezone did not follow the profile';
  END IF;

  -- A journal entry starts the streak on the local day.
  INSERT INTO public.journal_entries(user_id, content) VALUES (uid, 'Synthetic entry');
  SELECT last_entry_date INTO streak_day FROM public.journal_streaks WHERE user_id = uid;
  IF streak_day IS DISTINCT FROM local_today THEN
    RAISE EXCEPTION 'Journal streak counted % instead of the local day %', streak_day, local_today;
  END IF;

  -- Switching zones can leave the last entry one day ahead of local today; it counts as today.
  UPDATE public.journal_streaks SET last_entry_date = local_today + 1, current_streak = 5 WHERE user_id = uid;
  INSERT INTO public.journal_entries(user_id, content) VALUES (uid, 'Synthetic entry after the zone switch');
  IF (SELECT current_streak FROM public.journal_streaks WHERE user_id = uid) <> 5 THEN
    RAISE EXCEPTION 'A zone switch reset the journal streak';
  END IF;
  -- ...and the stored date comes back to local today, so tomorrow's entry extends the streak.
  IF (SELECT last_entry_date FROM public.journal_streaks WHERE user_id = uid) <> local_today THEN
    RAISE EXCEPTION 'The journal streak kept a date ahead of local today';
  END IF;
  UPDATE public.journal_streaks SET last_entry_date = local_today - 1 WHERE user_id = uid;
  INSERT INTO public.journal_entries(user_id, content) VALUES (uid, 'Synthetic entry on the next local day');
  IF (SELECT current_streak FROM public.journal_streaks WHERE user_id = uid) <> 6 THEN
    RAISE EXCEPTION 'The entry on the following local day did not extend the streak';
  END IF;
  IF position('LEAST(last_micro_date, v_today)' in pg_get_functiondef('public.update_micro_streak()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'The micro-moment streak keeps a date ahead of local today';
  END IF;

  -- A zone name that is not real falls back to UTC instead of failing the caller.
  UPDATE public.profiles SET timezone = 'Not/AZone' WHERE id = uid;
  IF public.user_time_zone(uid) <> 'UTC' THEN RAISE EXCEPTION 'Invalid zone did not fall back to UTC'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', uid::text, true);
  PERFORM * FROM public.get_home_context(uid);
END $$;

-- Ordinary callers cannot read another person's zone through the helpers.
DO $$ BEGIN
  IF has_function_privilege('authenticated', 'public.user_time_zone(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.user_local_date(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Time zone helpers are callable by clients';
  END IF;
END $$;

ROLLBACK;
