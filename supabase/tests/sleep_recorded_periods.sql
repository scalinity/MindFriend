-- Run against the migrated disposable sleep schema with auth.uid() and the unchanged owner policy.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
INSERT INTO public.sleep_entries(user_id,date,source,bedtime,wake_time,time_in_bed_minutes,time_asleep_minutes,recorded_periods)
VALUES ('11111111-1111-4111-8111-111111111111','2026-01-02','healthkit','2026-01-02 12:00-05','2026-01-02 12:30-05',30,30,
 '[{"start":"2026-01-02T17:00:00Z","end":"2026-01-02T17:30:00Z","in_bed_seconds":1800,"asleep_seconds":1800}]');
-- An older client omitting the new column can still insert and patch its owned records.
INSERT INTO public.sleep_entries(user_id,date,source,bedtime,wake_time,time_in_bed_minutes,time_asleep_minutes)
VALUES ('11111111-1111-4111-8111-111111111111','2026-01-03','manual','2026-01-03 00:00-05','2026-01-03 08:00-05',480,450);
UPDATE public.sleep_entries SET notes='Synthetic retained feedback' WHERE date='2026-01-02';
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.sleep_entries WHERE date='2026-01-02' AND recorded_periods IS NOT NULL AND notes='Synthetic retained feedback') THEN
        RAISE EXCEPTION 'Owned metadata and old-client patch must coexist';
    END IF;
    BEGIN
        UPDATE public.sleep_entries SET recorded_periods='{}' WHERE date='2026-01-02';
        RAISE EXCEPTION 'Non-array metadata accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE public.sleep_entries SET time_in_bed_minutes=0 WHERE date='2026-01-02';
        RAISE EXCEPTION 'Zero imported duration accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE public.sleep_entries SET time_in_bed_minutes=1441 WHERE date='2026-01-02';
        RAISE EXCEPTION 'Oversize duration accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE public.sleep_entries SET time_in_bed_minutes=30,time_asleep_minutes=30 WHERE date='2026-01-03';
        RAISE EXCEPTION 'Manual minimum changed';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE public.sleep_entries SET user_id='22222222-2222-4222-8222-222222222222' WHERE date='2026-01-02';
        RAISE EXCEPTION 'Ownership reassignment accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
DO $$ BEGIN
    IF EXISTS(SELECT 1 FROM public.sleep_entries WHERE user_id='11111111-1111-4111-8111-111111111111') THEN
        RAISE EXCEPTION 'Cross-owner sleep exposed';
    END IF;
    UPDATE public.sleep_entries SET recorded_periods=NULL WHERE user_id='11111111-1111-4111-8111-111111111111';
    IF FOUND THEN RAISE EXCEPTION 'Cross-owner metadata update accepted'; END IF;
    BEGIN
        INSERT INTO public.sleep_entries(user_id,date,source,bedtime,wake_time,time_in_bed_minutes)
        VALUES ('11111111-1111-4111-8111-111111111111','2026-01-04','healthkit','2026-01-04 12:00-05','2026-01-04 12:30-05',30);
        RAISE EXCEPTION 'Cross-owner insertion accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
    BEGIN
        PERFORM recorded_periods FROM public.sleep_entries;
        RAISE EXCEPTION 'Anonymous sleep read accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
