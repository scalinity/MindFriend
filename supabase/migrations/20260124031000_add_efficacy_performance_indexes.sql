-- Performance Optimization Indexes for Intervention Efficacy Engine
-- Based on performance review: docs/EFFICACY_ENGINE_PERFORMANCE_REVIEW.md

-- P1 Index: Efficacy Dashboard Queries
-- Optimizes get-efficacy-dashboard function (top exercises + recent sessions)
-- Impact: Reduces query time from ~90ms to ~18ms (5x speedup)
CREATE INDEX IF NOT EXISTS idx_intervention_efficacy_dashboard
ON intervention_efficacy(user_id, completed_at DESC, efficacy_score DESC);

-- P1 Index: Recommendation Lookups
-- Optimizes get-recommendations function (profile fetching)
-- Impact: Reduces query time from ~30ms to ~5ms (6x speedup)
CREATE INDEX IF NOT EXISTS idx_user_efficacy_profiles_lookup
ON user_efficacy_profiles(user_id, completion_count DESC)
WHERE completion_count >= 5;

-- P1 Index: Aggregation Batch Job
-- Optimizes aggregate-efficacy-profiles function (nightly cron)
-- Impact: Reduces query time from ~200ms to ~50ms (4x speedup)
-- Note: No partial index (WHERE clause) because NOW() is not immutable
CREATE INDEX IF NOT EXISTS idx_intervention_efficacy_aggregate
ON intervention_efficacy(completed_at DESC, user_id, exercise_id);

-- P2 Index: Generic Exercise Recommendations (Optional - Deploy if needed)
-- Optimizes get-recommendations fallback for users with few personalized exercises
-- Impact: Reduces fallback query from ~15ms to ~3ms
-- Uncomment if load testing shows this is needed:
-- CREATE INDEX IF NOT EXISTS idx_exercises_recommendations
-- ON exercises(type, duration)
-- WHERE is_active = TRUE;

COMMENT ON INDEX idx_intervention_efficacy_dashboard IS 'Optimizes dashboard queries for top exercises and recent sessions';
COMMENT ON INDEX idx_user_efficacy_profiles_lookup IS 'Optimizes recommendation profile lookups for users with sufficient data';
COMMENT ON INDEX idx_intervention_efficacy_aggregate IS 'Optimizes nightly aggregation batch job for recent efficacy records';
