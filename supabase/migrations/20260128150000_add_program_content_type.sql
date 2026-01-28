-- =====================================================================================================================
-- Migration: 20260128150000_add_program_content_type.sql
-- Description: Add 'program' to content_type_enum for program translations
-- Date: 2026-01-28
-- =====================================================================================================================

-- Add 'program' to content_type_enum if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum 
    WHERE enumlabel = 'program' 
    AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'content_type_enum')
  ) THEN
    ALTER TYPE public.content_type_enum ADD VALUE 'program';
  END IF;
END $$;
