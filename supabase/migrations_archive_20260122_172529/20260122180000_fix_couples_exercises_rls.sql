-- Migration: Fix RLS on couples_exercises table
-- Purpose: Enable Row Level Security (flagged by Supabase Security Advisor)
-- This table is a read-only exercise library - all authenticated users can view

-- Enable RLS
ALTER TABLE IF EXISTS public.couples_exercises ENABLE ROW LEVEL SECURITY;

-- Create read policy for authenticated users (exercises are public content)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'couples_exercises'
        AND policyname = 'Authenticated users can view couples exercises'
    ) THEN
        CREATE POLICY "Authenticated users can view couples exercises"
            ON public.couples_exercises FOR SELECT
            TO authenticated
            USING (true);
    END IF;
END $$;

-- Note: No INSERT/UPDATE/DELETE policies needed as this is admin-seeded content
-- Service role can still modify via SUPABASE_SERVICE_ROLE_KEY
