-- Fix missing duration_seconds column in exercises table
-- This column is required by get_home_context RPC and the iOS client
-- Issue: "column duration_seconds does not exist" error in HomeView

DO $$
BEGIN
    -- Check if column exists
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'exercises'
        AND column_name = 'duration_seconds'
    ) THEN
        -- Add column with default 0 (schema requires NOT NULL)
        ALTER TABLE exercises ADD COLUMN duration_seconds INT NOT NULL DEFAULT 0;
        
        -- Log the change
        RAISE NOTICE 'Added duration_seconds column to exercises table';
    END IF;
END $$;
