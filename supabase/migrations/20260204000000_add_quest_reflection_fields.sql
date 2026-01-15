-- Migration: Add reflection_note and rating columns to quests table
-- These allow users to reflect on completed quests

ALTER TABLE quests ADD COLUMN IF NOT EXISTS reflection_note TEXT;
ALTER TABLE quests ADD COLUMN IF NOT EXISTS rating INT CHECK (rating BETWEEN 1 AND 5);
