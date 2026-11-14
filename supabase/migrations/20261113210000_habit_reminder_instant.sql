-- Habit reminders could never be saved. Every released client (1.0.4, 1.0.5 and 2.0) models
-- habits.reminder_time and routines.target_time as a Swift Date, which the Supabase client
-- sends as a full UTC date-time without a zone suffix ("2026-11-13T13:30:00.000"). Neither
-- time with time zone nor time without time zone accepts that text, so the insert failed with
-- "invalid input syntax for type time with time zone"; and a timetz value read back
-- ("13:30:00+00") would not decode into a Date either.
--
-- timestamptz accepts the payload as the instant the person picked (the database runs in UTC,
-- the same zone the client wrote), and returns ISO 8601 text that the released clients decode.
-- The app takes the hour and minute of that instant in the device's zone, so the reminder keeps
-- the local time of day that was chosen. Server code that needs it reads
-- (reminder_time AT TIME ZONE profiles.timezone)::time.
--
-- Production holds no non-null value in either column; existing values, if any, keep their time
-- of day on 1 January 2000.

ALTER TABLE public.habits
  ALTER COLUMN reminder_time TYPE timestamptz
  USING (CASE WHEN reminder_time IS NULL THEN NULL ELSE DATE '2000-01-01' + reminder_time END);

ALTER TABLE public.routines
  ALTER COLUMN target_time TYPE timestamptz
  USING (CASE WHEN target_time IS NULL THEN NULL ELSE DATE '2000-01-01' + target_time END);

COMMENT ON COLUMN public.habits.reminder_time IS
  'The reminder as picked on the device; its local time of day is the daily reminder time.';
COMMENT ON COLUMN public.routines.target_time IS
  'The start time as picked on the device; its local time of day is the daily target.';
