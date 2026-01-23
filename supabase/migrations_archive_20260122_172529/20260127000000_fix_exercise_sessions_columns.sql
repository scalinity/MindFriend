-- Fix missing columns in exercise_sessions table
ALTER TABLE exercise_sessions ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;
ALTER TABLE exercise_sessions ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE exercise_sessions ADD COLUMN IF NOT EXISTS completed BOOLEAN DEFAULT false;
ALTER TABLE exercise_sessions ADD COLUMN IF NOT EXISTS rating INT CHECK (rating BETWEEN 1 AND 5);
ALTER TABLE exercise_sessions ADD COLUMN IF NOT EXISTS note TEXT;
