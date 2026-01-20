-- Habit Stacking & Routines System Schema
-- Implements behavior science-based habit formation with streak tracking

-- Create habit_categories enum
DO $$ BEGIN
  CREATE TYPE habit_category AS ENUM (
    'breathing',
    'meditation', 
    'journaling',
    'movement',
    'custom'
  );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Create habit_difficulty enum
DO $$ BEGIN
  CREATE TYPE habit_difficulty AS ENUM (
    'easy',
    'medium',
    'hard'
  );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Create routine_type enum
DO $$ BEGIN
  CREATE TYPE routine_type AS ENUM (
    'morning',
    'evening',
    'custom'
  );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Habits table: Core habit definitions with anchor behavior stacking
CREATE TABLE IF NOT EXISTS habits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  anchor TEXT NOT NULL, -- "After I [anchor], I will [behavior]"
  behavior TEXT NOT NULL,
  category habit_category NOT NULL,
  difficulty habit_difficulty NOT NULL DEFAULT 'easy',
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds > 0 AND duration_seconds <= 600),
  reminder_time TIME WITH TIME ZONE, -- Optional reminder time
  reminder_minutes_before INTEGER DEFAULT 5 CHECK (reminder_minutes_before > 0 AND reminder_minutes_before <= 60),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT habits_user_name_unique UNIQUE (user_id, name)
);

CREATE INDEX idx_habits_user_id ON habits(user_id);
CREATE INDEX idx_habits_category ON habits(category);
CREATE INDEX idx_habits_is_active ON habits(is_active) WHERE is_active;

-- Routines table: Ordered sequences of habits (morning/evening flow)
CREATE TABLE IF NOT EXISTS routines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type routine_type NOT NULL,
  target_time TIME WITH TIME ZONE, -- When routine should be started
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT routines_user_type_unique UNIQUE (user_id, type)
);

CREATE INDEX idx_routines_user_id ON routines(user_id);
CREATE INDEX idx_routines_type ON routines(type);
CREATE INDEX idx_routines_is_active ON routines(is_active) WHERE is_active;

-- Routine_habits junction table: Orders habits within a routine
CREATE TABLE IF NOT EXISTS routine_habits (
  routine_id UUID NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  order_index INTEGER NOT NULL CHECK (order_index >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (routine_id, habit_id),
  CONSTRAINT unique_routine_habit_order UNIQUE (routine_id, order_index)
);

CREATE INDEX idx_routine_habits_routine_id ON routine_habits(routine_id);
CREATE INDEX idx_routine_habits_habit_id ON routine_habits(habit_id);

-- Habit completions table: Daily tracking with streak calculation
CREATE TABLE IF NOT EXISTS habit_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  habit_id UUID NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  completed_date DATE NOT NULL, -- Use DATE to avoid timezone complexity
  current_streak INTEGER NOT NULL DEFAULT 1 CHECK (current_streak >= 0),
  skipped BOOLEAN NOT NULL DEFAULT false,
  skip_reason TEXT, -- Optional reason if skipped
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT habit_completions_unique_per_day UNIQUE (habit_id, completed_date)
);

CREATE INDEX idx_habit_completions_habit_id ON habit_completions(habit_id);
CREATE INDEX idx_habit_completions_user_id ON habit_completions(user_id);
CREATE INDEX idx_habit_completions_date ON habit_completions(completed_date);
CREATE INDEX idx_habit_completions_user_date ON habit_completions(user_id, completed_date);

-- Routine completions table: Track routine execution
CREATE TABLE IF NOT EXISTS routine_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id UUID NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  completed_date DATE NOT NULL,
  completed_habit_ids UUID[] NOT NULL DEFAULT '{}',
  skipped_habit_ids UUID[] NOT NULL DEFAULT '{}',
  completion_percentage INTEGER NOT NULL CHECK (completion_percentage >= 0 AND completion_percentage <= 100),
  total_duration_seconds INTEGER NOT NULL CHECK (total_duration_seconds >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT routine_completions_unique_per_day UNIQUE (routine_id, completed_date)
);

CREATE INDEX idx_routine_completions_routine_id ON routine_completions(routine_id);
CREATE INDEX idx_routine_completions_user_id ON routine_completions(user_id);
CREATE INDEX idx_routine_completions_date ON routine_completions(completed_date);

-- Habit templates table: Pre-built habits for users to adopt
CREATE TABLE IF NOT EXISTS habit_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  category habit_category NOT NULL,
  difficulty habit_difficulty NOT NULL,
  default_duration_seconds INTEGER NOT NULL CHECK (default_duration_seconds > 0 AND default_duration_seconds <= 600),
  behavior_template TEXT NOT NULL, -- "After I [anchor], I will..." template
  description TEXT,
  anchor_example TEXT, -- Example anchor habit
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_habit_templates_category ON habit_templates(category);

-- Routine templates table: Pre-built routine sequences
CREATE TABLE IF NOT EXISTS routine_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  type routine_type NOT NULL,
  description TEXT,
  target_time TIME WITH TIME ZONE,
  habit_template_ids UUID[] NOT NULL DEFAULT '{}', -- References habit_templates
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_routine_templates_type ON routine_templates(type);

-- ==================
-- Row Level Security (RLS) Policies
-- ==================

-- Enable RLS on all tables
ALTER TABLE habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE routine_templates ENABLE ROW LEVEL SECURITY;

-- Habits RLS: Users can only read/write their own habits
CREATE POLICY "Users read own habits" ON habits
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users create own habits" ON habits
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own habits" ON habits
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users delete own habits" ON habits
  FOR DELETE USING (auth.uid() = user_id);

-- Routines RLS: Users can only read/write their own routines
CREATE POLICY "Users read own routines" ON routines
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users create own routines" ON routines
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own routines" ON routines
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users delete own routines" ON routines
  FOR DELETE USING (auth.uid() = user_id);

-- Routine habits RLS: Accessible through routine ownership
CREATE POLICY "Users read routine habits" ON routine_habits
  FOR SELECT USING (
    routine_id IN (SELECT id FROM routines WHERE user_id = auth.uid())
  );

CREATE POLICY "Users manage routine habits" ON routine_habits
  FOR INSERT WITH CHECK (
    routine_id IN (SELECT id FROM routines WHERE user_id = auth.uid())
  );

CREATE POLICY "Users update routine habits" ON routine_habits
  FOR UPDATE USING (
    routine_id IN (SELECT id FROM routines WHERE user_id = auth.uid())
  );

CREATE POLICY "Users delete routine habits" ON routine_habits
  FOR DELETE USING (
    routine_id IN (SELECT id FROM routines WHERE user_id = auth.uid())
  );

-- Habit completions RLS: Users can only access their own completions
CREATE POLICY "Users read own completions" ON habit_completions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users create own completions" ON habit_completions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own completions" ON habit_completions
  FOR UPDATE USING (auth.uid() = user_id);

-- Routine completions RLS: Users can only access their own routine completions
CREATE POLICY "Users read own routine completions" ON routine_completions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users create own routine completions" ON routine_completions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own routine completions" ON routine_completions
  FOR UPDATE USING (auth.uid() = user_id);

-- Habit templates RLS: Templates are readable by all authenticated users
CREATE POLICY "Authenticated users read templates" ON habit_templates
  FOR SELECT USING (auth.role() = 'authenticated');

-- Routine templates RLS: Templates are readable by all authenticated users
CREATE POLICY "Authenticated users read routine templates" ON routine_templates
  FOR SELECT USING (auth.role() = 'authenticated');

-- ==================
-- Seed Data: Habit Templates
-- ==================

INSERT INTO habit_templates (name, category, difficulty, default_duration_seconds, behavior_template, description, anchor_example) VALUES
  -- Breathing exercises
  ('Box Breathing', 'breathing', 'easy', 120, 'After I [wake up], I will practice box breathing', 'Calm your nervous system with 4-4-4-4 breathing pattern', 'wake up'),
  ('Morning Breath Reset', 'breathing', 'easy', 90, 'After I [have coffee], I will do breathing exercises', 'Energize your morning with deep breathing', 'have coffee'),
  ('Stress Relief Breathing', 'breathing', 'medium', 180, 'After I [feel stressed], I will practice breathing', 'Release tension with guided breathing', 'feel stressed'),
  
  -- Meditation
  ('Mindfulness Moment', 'meditation', 'easy', 300, 'After I [sit down], I will meditate', 'Start with 5-minute mindfulness practice', 'sit down'),
  ('Loving Kindness', 'meditation', 'medium', 420, 'After I [breakfast], I will practice loving kindness', 'Cultivate compassion through guided meditation', 'breakfast'),
  
  -- Journaling
  ('Gratitude Journal', 'journaling', 'easy', 180, 'After I [dinner], I will journal gratitude', 'Reflect on things you''re grateful for today', 'dinner'),
  ('Thought Record', 'journaling', 'medium', 300, 'After I [evening routine], I will journal', 'Process emotions and thoughts through writing', 'evening routine'),
  
  -- Movement
  ('Stretching Routine', 'movement', 'easy', 300, 'After I [wake up], I will stretch', 'Gentle stretching to start your day', 'wake up'),
  ('Quick Walk', 'movement', 'medium', 600, 'After I [lunch], I will take a walk', 'Move your body after eating', 'lunch');

-- ==================
-- Seed Data: Routine Templates
-- ==================

INSERT INTO routine_templates (name, type, description, target_time, habit_template_ids) VALUES
  ('Morning Calm', 'morning', 'Start your day centered and grounded', '07:00:00+00:00', 
    (SELECT ARRAY_AGG(id) FROM habit_templates WHERE name IN ('Box Breathing', 'Mindfulness Moment', 'Stretching Routine'))
  ),
  ('Evening Wind Down', 'evening', 'Prepare for restful sleep', '21:00:00+00:00',
    (SELECT ARRAY_AGG(id) FROM habit_templates WHERE name IN ('Gratitude Journal', 'Stress Relief Breathing'))
  );
