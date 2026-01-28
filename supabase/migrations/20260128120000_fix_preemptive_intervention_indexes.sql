-- Fix index name collisions from 20260128110000
-- The original idx_interventions_* names may collide with existing indexes on interventions table
-- PostgreSQL index names are schema-scoped, not table-scoped
-- We only create new indexes with proper names - don't drop existing indexes as they may belong to other tables

-- Create properly-named indexes on preemptive_interventions table
CREATE INDEX IF NOT EXISTS idx_preemptive_interventions_user_status ON public.preemptive_interventions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_preemptive_interventions_prediction ON public.preemptive_interventions(prediction_id);
CREATE INDEX IF NOT EXISTS idx_preemptive_interventions_pending ON public.preemptive_interventions(user_id, created_at DESC) WHERE status = 'pending';
