-- Migration: Fix quest_templates schema mismatch
-- Adds missing columns (category, xp_reward, is_premium) that Swift expects
-- Migrates data from legacy "type" column to "category" column

-- Add missing columns if they don't exist
ALTER TABLE quest_templates ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE quest_templates ADD COLUMN IF NOT EXISTS xp_reward INT DEFAULT 50;
ALTER TABLE quest_templates ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT false;

-- Migrate data from "type" to "category" if type exists and category is empty
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'quest_templates' AND column_name = 'type'
  ) THEN
    -- Map legacy type values to category values
    UPDATE quest_templates
    SET category = CASE
      WHEN type = 'breathing' THEN 'mindfulness'
      WHEN type = 'walk' THEN 'physical'
      WHEN type = 'journal' THEN 'creative'
      WHEN type = 'focus' THEN 'mindfulness'
      WHEN type = 'gratitude' THEN 'gratitude'
      WHEN type = 'stretch' THEN 'physical'
      ELSE COALESCE(type, 'mindfulness')
    END
    WHERE category IS NULL AND type IS NOT NULL;
  END IF;
END $$;

-- Set default for any remaining NULL categories
UPDATE quest_templates SET category = 'mindfulness' WHERE category IS NULL;

-- Make category NOT NULL with a default for future inserts
ALTER TABLE quest_templates ALTER COLUMN category SET DEFAULT 'mindfulness';

-- Add an index on category for efficient filtering
CREATE INDEX IF NOT EXISTS idx_quest_templates_category ON quest_templates(category);

-- Verify the migration
-- SELECT id, title, type, category, xp_reward, is_premium FROM quest_templates LIMIT 5;
