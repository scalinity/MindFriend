-- Migration: Medication Reminders Feature
-- Purpose: Create medication tracking tables with RLS and indexes
-- Author: dev-pipeline
-- Date: 2026-01-19

-- 1. Create medications table
CREATE TABLE IF NOT EXISTS medications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Medication info
    name TEXT NOT NULL,
    dosage TEXT,
    purpose TEXT,
    color TEXT,
    icon TEXT DEFAULT 'pill',

    -- Schedule
    frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'twice_daily', 'three_times_daily', 'weekly', 'as_needed', 'custom')),
    times_per_day INTEGER DEFAULT 1 CHECK (times_per_day >= 1 AND times_per_day <= 10),
    scheduled_times TIME[] NOT NULL,
    days_of_week INTEGER[],

    -- Reminders
    reminder_enabled BOOLEAN DEFAULT true,
    reminder_sound TEXT DEFAULT 'default',
    notification_text TEXT,
    use_generic_notification BOOLEAN DEFAULT false,

    -- Tracking
    supply_count INTEGER CHECK (supply_count IS NULL OR supply_count >= 0),
    refill_reminder_count INTEGER CHECK (refill_reminder_count IS NULL OR refill_reminder_count >= 0),

    -- Status
    is_active BOOLEAN DEFAULT true,
    archived_at TIMESTAMPTZ,
    started_at DATE DEFAULT CURRENT_DATE,
    ended_at DATE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Create medication_logs table
CREATE TABLE IF NOT EXISTS medication_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    medication_id UUID NOT NULL REFERENCES medications(id) ON DELETE CASCADE,

    -- Scheduling
    scheduled_at TIMESTAMPTZ NOT NULL,

    -- Status
    status TEXT NOT NULL CHECK (status IN ('pending', 'taken', 'skipped', 'late')),
    logged_at TIMESTAMPTZ,

    -- Details
    skip_reason TEXT CHECK (skip_reason IS NULL OR status = 'skipped'),
    notes TEXT CHECK (notes IS NULL OR char_length(notes) <= 500),
    side_effects TEXT[],

    -- Correlation (optional - if mood logged near this time)
    mood_at_time INTEGER CHECK (mood_at_time IS NULL OR (mood_at_time >= 1 AND mood_at_time <= 10)),

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_medication_schedule UNIQUE(medication_id, scheduled_at)
);

-- 3. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_medications_user_active
    ON medications(user_id, is_active)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_medications_user_archived
    ON medications(user_id, archived_at)
    WHERE archived_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_medications_refill
    ON medications(user_id, supply_count)
    WHERE supply_count IS NOT NULL AND supply_count > 0;

CREATE INDEX IF NOT EXISTS idx_med_logs_user_date
    ON medication_logs(user_id, scheduled_at DESC);

CREATE INDEX IF NOT EXISTS idx_med_logs_status
    ON medication_logs(user_id, status)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_med_logs_medication_date
    ON medication_logs(medication_id, scheduled_at DESC);

-- 4. Enable Row Level Security
ALTER TABLE medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_logs ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS policies for medications
DO $$
BEGIN
  -- SELECT policy - users read own medications
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medications'
    AND policyname = 'users_read_own_medications'
  ) THEN
    CREATE POLICY "users_read_own_medications"
      ON medications FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  -- INSERT policy - users insert own medications
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medications'
    AND policyname = 'users_insert_own_medications'
  ) THEN
    CREATE POLICY "users_insert_own_medications"
      ON medications FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;

  -- UPDATE policy - users update own medications
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medications'
    AND policyname = 'users_update_own_medications'
  ) THEN
    CREATE POLICY "users_update_own_medications"
      ON medications FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;

  -- DELETE policy - users delete own medications
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medications'
    AND policyname = 'users_delete_own_medications'
  ) THEN
    CREATE POLICY "users_delete_own_medications"
      ON medications FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- 6. Create RLS policies for medication_logs
DO $$
BEGIN
  -- SELECT policy - users read own logs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medication_logs'
    AND policyname = 'users_read_own_logs'
  ) THEN
    CREATE POLICY "users_read_own_logs"
      ON medication_logs FOR SELECT
      USING (auth.uid() = user_id);
  END IF;

  -- INSERT policy - users insert own logs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medication_logs'
    AND policyname = 'users_insert_own_logs'
  ) THEN
    CREATE POLICY "users_insert_own_logs"
      ON medication_logs FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;

  -- UPDATE policy - users update own logs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medication_logs'
    AND policyname = 'users_update_own_logs'
  ) THEN
    CREATE POLICY "users_update_own_logs"
      ON medication_logs FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;

  -- DELETE policy - users delete own logs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'medication_logs'
    AND policyname = 'users_delete_own_logs'
  ) THEN
    CREATE POLICY "users_delete_own_logs"
      ON medication_logs FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;
