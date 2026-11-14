-- Synthetic rollback fixture for get_pending_celebrations.
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17200000-0000-4000-8000-000000000001', 'celebrations@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES ('17200000-0000-4000-8000-000000000001') ON CONFLICT(id) DO NOTHING;

-- A month-old backlog row, a streak milestone, an already-shown row and twelve recent level-ups.
INSERT INTO public.celebration_events(user_id, celebration_type, value, shown_at, created_at) VALUES
 ('17200000-0000-4000-8000-000000000001', 'level_up', 2, NULL, now() - interval '30 days'),
 ('17200000-0000-4000-8000-000000000001', 'streak_milestone', 7, NULL, now() - interval '1 hour'),
 ('17200000-0000-4000-8000-000000000001', 'badge_unlock', 1, now(), now() - interval '1 hour');
INSERT INTO public.celebration_events(user_id, celebration_type, value, shown_at, created_at)
 SELECT '17200000-0000-4000-8000-000000000001', 'level_up', 10 + n, NULL, now() - n * interval '1 minute'
 FROM generate_series(1, 12) AS n;

DO $$ DECLARE pending integer; oldest integer; BEGIN
 SELECT count(*), min(value) INTO pending, oldest
   FROM public.get_pending_celebrations('17200000-0000-4000-8000-000000000001');
 IF pending <> 10 THEN RAISE EXCEPTION 'Expected 10 pending celebrations, got %', pending; END IF;
 IF EXISTS(SELECT 1 FROM public.get_pending_celebrations('17200000-0000-4000-8000-000000000001')
           WHERE celebration_type = 'streak_milestone' OR value = 2) THEN
   RAISE EXCEPTION 'Backlog or streak milestone returned';
 END IF;
 -- Oldest first among the recent rows: values 22 down to 13 (the two newest wait).
 IF oldest <> 13 THEN RAISE EXCEPTION 'Expected the oldest recent rows first, got min %', oldest; END IF;
END $$;

ROLLBACK;
