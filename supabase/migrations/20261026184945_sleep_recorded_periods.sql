-- Keep measured periods alongside the daily aggregate without changing its identity or feedback.
ALTER TABLE public.sleep_entries ADD COLUMN recorded_periods jsonb;
ALTER TABLE public.sleep_entries ADD CONSTRAINT sleep_entries_recorded_periods_check
    CHECK (recorded_periods IS NULL OR jsonb_typeof(recorded_periods) = 'array');
-- Imported naps can be shorter than one hour; manual entry keeps its existing minimum.
ALTER TABLE public.sleep_entries DROP CONSTRAINT sleep_entries_time_in_bed_minutes_check;
ALTER TABLE public.sleep_entries ADD CONSTRAINT sleep_entries_time_in_bed_minutes_check
    CHECK (time_in_bed_minutes >= CASE WHEN source = 'manual' THEN 60 ELSE 1 END
       AND time_in_bed_minutes <= 1440);
