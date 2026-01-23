-- =====================================================================================================================
-- Migration: 20260329000004_fix_assessment_types.sql
-- Description: Fix assessment type mismatches for P07 and P08 therapeutic programs
-- Issue: P07 (DBT Distress Tolerance) and P08 (DBT Emotion Regulation) incorrectly use PHQ-9
--        (depression assessment) for programs that don't target depression. PHQ-9 is clinically
--        inappropriate for measuring distress tolerance or emotion regulation outcomes.
-- Date: 2026-01-20
-- =====================================================================================================================

-- Fix P07: DBT Distress Tolerance should not require baseline assessment
-- Rationale: No appropriate assessment exists for distress tolerance capacity. PHQ-9 measures
--            depression, not crisis management skills or distress tolerance.
UPDATE programs
SET
  requires_baseline_assessment = FALSE,
  assessment_type = NULL,
  updated_at = NOW()
WHERE slug = 'dbt-distress-tolerance-10day';

-- Fix P08: DBT Emotion Regulation should not require baseline assessment
-- Rationale: No appropriate assessment exists for general emotion regulation. PHQ-9 measures
--            depression specifically, not emotional dysregulation or mood instability.
UPDATE programs
SET
  requires_baseline_assessment = FALSE,
  assessment_type = NULL,
  updated_at = NOW()
WHERE slug = 'dbt-emotion-regulation-14day';
