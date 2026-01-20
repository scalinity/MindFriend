-- Migration: Create couples_exercise_sessions table with RLS
-- Purpose: Track joint exercise session progress and completion
-- Status: CRITICAL PATH - Foundation

CREATE TABLE IF NOT EXISTS couples_exercise_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_link_id UUID NOT NULL REFERENCES partner_links(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES couples_exercises(id) ON DELETE RESTRICT,
    user_id_1 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_id_2 UUID NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'paused', 'completed', 'abandoned')),
    user_1_rating SMALLINT NULL CHECK (user_1_rating >= 1 AND user_1_rating <= 10),
    user_2_rating SMALLINT NULL CHECK (user_2_rating >= 1 AND user_2_rating <= 10),
    user_1_notes TEXT NULL CHECK (char_length(user_1_notes) <= 500),
    user_2_notes TEXT NULL CHECK (char_length(user_2_notes) <= 500),
    user_1_progress_percent SMALLINT NOT NULL DEFAULT 0 CHECK (user_1_progress_percent >= 0 AND user_1_progress_percent <= 100),
    user_2_progress_percent SMALLINT NOT NULL DEFAULT 0 CHECK (user_2_progress_percent >= 0 AND user_2_progress_percent <= 100),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ NULL,
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT valid_users CHECK (user_id_1 != COALESCE(user_id_2, user_id_1)),
    CONSTRAINT rating_requires_completion CHECK (
        (status != 'completed' AND user_1_rating IS NULL AND user_2_rating IS NULL) OR
        (status = 'completed' AND user_1_rating IS NOT NULL AND user_2_rating IS NOT NULL)
    )
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_sessions_partner_link ON couples_exercise_sessions(partner_link_id);
CREATE INDEX IF NOT EXISTS idx_sessions_exercise ON couples_exercise_sessions(exercise_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_1 ON couples_exercise_sessions(user_id_1);
CREATE INDEX IF NOT EXISTS idx_sessions_user_2 ON couples_exercise_sessions(user_id_2);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON couples_exercise_sessions(status);
CREATE INDEX IF NOT EXISTS idx_sessions_completed ON couples_exercise_sessions(completed_at) WHERE status = 'completed';

-- Enable RLS
ALTER TABLE couples_exercise_sessions ENABLE ROW LEVEL SECURITY;

-- RLS Policy 1: Users can read sessions they participate in (as user_id_1)
CREATE POLICY "Users read own sessions as user_1"
  ON couples_exercise_sessions FOR SELECT
  USING (auth.uid() = user_id_1);

-- RLS Policy 2: Users can read sessions they participate in (as user_id_2)
CREATE POLICY "Users read own sessions as user_2"
  ON couples_exercise_sessions FOR SELECT
  USING (auth.uid() = user_id_2);

-- RLS Policy 3: Users can insert new session (initiate exercise)
CREATE POLICY "Users create sessions"
  ON couples_exercise_sessions FOR INSERT
  WITH CHECK (
    auth.uid() = user_id_1 AND
    user_id_2 IS NULL AND
    status = 'pending'
  );

-- RLS Policy 4: Users can update their own progress/notes/rating
-- Note: Application layer must prevent changing core fields (partner_link_id, exercise_id, user_id_1/2)
CREATE POLICY "Users update their own progress"
  ON couples_exercise_sessions FOR UPDATE
  USING (
    (auth.uid() = user_id_1 OR auth.uid() = user_id_2)
  );

-- RLS Policy 5: Users cannot delete sessions
CREATE POLICY "Users cannot delete sessions"
  ON couples_exercise_sessions FOR DELETE
  USING (false);
