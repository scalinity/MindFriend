-- Add the missing moods.source column.
--
-- The iOS app (WellnessInsightsService.loadWeeklyMoodTrend, shipped in 1.0.3)
-- selects moods.source, and get_moods_for_pattern_analysis() returns m.source
-- for the weekly summary, but the column was never created. Both fail with
-- "column moods.source does not exist" (Sentry MINDFRIEND-1A, MINDFRIEND-1B).
--
-- NOT NULL with a constant default is a metadata-only change on Postgres 11+,
-- so existing rows read as 'manual' without a table rewrite, and clients that
-- never send source (createMood upserts without it) keep working unchanged.
-- Allowed values mirror the app's MoodSource enum so every row still decodes.

ALTER TABLE public.moods
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'manual';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'moods_source_check'
      AND conrelid = 'public.moods'::regclass
  ) THEN
    ALTER TABLE public.moods
      ADD CONSTRAINT moods_source_check
      CHECK (source IN ('manual', 'post_quest', 'post_exercise'));
  END IF;
END
$$;

COMMENT ON COLUMN public.moods.source IS
  'Where the mood entry came from: manual, post_quest or post_exercise. Matches the iOS MoodSource enum.';
