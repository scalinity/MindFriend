-- Migration: Add performance indexes for pathway tables
-- Purpose: Optimize common query patterns identified by review agents
-- Date: 2026-01-24

-- Index for fetching user's active pathways (TransitionService.fetchActivePathways)
CREATE INDEX IF NOT EXISTS idx_user_pathways_user_status
ON user_pathways(user_id, status)
WHERE status = 'active';

-- Index for check-in lookups and duplicate detection
CREATE INDEX IF NOT EXISTS idx_pathway_progress_pathway_day
ON pathway_progress(user_pathway_id, day_number);

-- Index for milestone queries (TransitionService.fetchPhaseMilestones)
CREATE INDEX IF NOT EXISTS idx_pathway_milestones_pathway_phase
ON pathway_milestones(user_pathway_id, phase_number);

-- Index for phase detail lookups
CREATE INDEX IF NOT EXISTS idx_pathway_phases_pathway_phase
ON pathway_phases(pathway_id, phase_number);

-- Composite index for personalization data queries
CREATE INDEX IF NOT EXISTS idx_user_pathways_user_created
ON user_pathways(user_id, created_at DESC);

-- Index for efficient progress tracking
CREATE INDEX IF NOT EXISTS idx_pathway_progress_created
ON pathway_progress(user_pathway_id, created_at DESC);

-- Add comment explaining the indexes
COMMENT ON INDEX idx_user_pathways_user_status IS
'Optimizes fetchActivePathways query - filters by user_id and status=active';

COMMENT ON INDEX idx_pathway_progress_pathway_day IS
'Prevents duplicate check-ins and speeds up day_number lookups';

COMMENT ON INDEX idx_pathway_milestones_pathway_phase IS
'Optimizes fetchPhaseMilestones query - composite key for milestone retrieval';

COMMENT ON INDEX idx_pathway_phases_pathway_phase IS
'Optimizes fetchPhaseDetails query - composite key for phase lookup';
