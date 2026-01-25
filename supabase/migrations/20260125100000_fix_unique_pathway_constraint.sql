-- Migration: Fix Unique Pathway Constraint
-- Created: 2026-01-25 10:00:00
-- Purpose: Fix database constraint logic error identified in Phase 2 review
-- Issue: unique_active_pathway allows multiple enrollments per pathway with different statuses
-- Fix: Replace with unique(user_id, pathway_id) to ensure one enrollment per pathway

-- Drop the old constraint
ALTER TABLE user_pathways
DROP CONSTRAINT IF EXISTS unique_active_pathway;

-- Add corrected constraint
-- One enrollment per user per pathway (regardless of status)
ALTER TABLE user_pathways
ADD CONSTRAINT unique_user_pathway UNIQUE(user_id, pathway_id);

COMMENT ON CONSTRAINT unique_user_pathway ON user_pathways IS
'Ensures one enrollment record per user per pathway. Status changes update the same row instead of creating new rows.';
