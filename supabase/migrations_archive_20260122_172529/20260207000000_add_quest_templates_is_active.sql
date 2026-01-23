-- Migration: Add is_active column to quest_templates
-- Fixes: "column qt.is_active does not exist" error in assign_daily_quest RPC

-- Add the is_active column that the assign_daily_quest RPC expects
ALTER TABLE quest_templates
ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- Add an index for efficient filtering by active status
CREATE INDEX IF NOT EXISTS idx_quest_templates_is_active ON quest_templates(is_active) WHERE is_active = true;
