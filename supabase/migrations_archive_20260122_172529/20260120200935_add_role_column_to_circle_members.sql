-- Migration: Add role column to circle_members if it doesn't exist
-- This is idempotent - safe to run multiple times

-- Add role column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'circle_members'
        AND column_name = 'role'
    ) THEN
        ALTER TABLE circle_members
        ADD COLUMN role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member'));

        -- Update existing records where user is the circle owner
        UPDATE circle_members cm
        SET role = 'owner'
        FROM circles c
        WHERE cm.circle_id = c.id
        AND cm.user_id = c.owner_id;
    END IF;
END $$;
