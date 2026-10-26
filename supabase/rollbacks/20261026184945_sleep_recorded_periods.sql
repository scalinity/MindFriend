-- Roll back only before new-format records exist. Preserve later measurements instead of deleting them.
BEGIN;
LOCK TABLE public.sleep_entries IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM public.sleep_entries WHERE recorded_periods IS NOT NULL OR time_in_bed_minutes < 60) THEN
        RAISE EXCEPTION 'New sleep records exist; preserve them and use the compatible client/function rollback';
    END IF;
END $$;
ALTER TABLE public.sleep_entries DROP CONSTRAINT sleep_entries_time_in_bed_minutes_check;
ALTER TABLE public.sleep_entries ADD CONSTRAINT sleep_entries_time_in_bed_minutes_check
    CHECK (time_in_bed_minutes >= 60 AND time_in_bed_minutes <= 1440);
ALTER TABLE public.sleep_entries DROP COLUMN recorded_periods;
COMMIT;
