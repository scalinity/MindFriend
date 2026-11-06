-- Historical trajectories were not tagged with a source. Retain every row and
-- value, but do not treat unknown provenance as an observed improvement.
ALTER TABLE public.emotional_trajectories
  ADD COLUMN measurement_status TEXT NOT NULL DEFAULT 'legacy_unverified'
    CHECK (measurement_status IN ('legacy_unverified', 'observed', 'synthetic')),
  ADD COLUMN measurement_source TEXT;
ALTER TABLE public.intervention_efficacy
  ADD COLUMN measurement_status TEXT NOT NULL DEFAULT 'legacy_unverified'
    CHECK (measurement_status IN ('legacy_unverified', 'observed', 'synthetic')),
  ADD COLUMN measurement_source TEXT;
ALTER TABLE public.user_efficacy_profiles
  ADD COLUMN measurement_status TEXT NOT NULL DEFAULT 'legacy_unverified'
    CHECK (measurement_status IN ('legacy_unverified', 'observed', 'synthetic'));

COMMENT ON COLUMN public.emotional_trajectories.measurement_status IS
  'Legacy rows remain unverified; do not infer provenance from sample values. Observed requires an identified measurement source; synthetic is for explicitly identified fixtures only.';
COMMENT ON COLUMN public.intervention_efficacy.measurement_status IS
  'Only observed results may contribute to efficacy displays and recommendations. Unknown historical values are retained without attributing a source.';
COMMENT ON COLUMN public.user_efficacy_profiles.measurement_status IS
  'An observed profile contains only observed efficacy records. Historical mixed or unknown profiles remain preserved as legacy_unverified.';
