-- F009: Personalized Daily Briefing
-- Create tables for daily briefing feature (MVP scope)
-- Excludes: wellness_score, audio fields, important_dates, voice preferences (Phase 2)

-- ============================================================================
-- TABLE: daily_briefings
-- ============================================================================
-- Stores generated daily briefings, one per user per day
CREATE TABLE IF NOT EXISTS daily_briefings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_date DATE NOT NULL, -- YYYY-MM-DD in user's timezone

  -- Greeting
  greeting TEXT NOT NULL,

  -- Mood prediction (from F003)
  predicted_mood NUMERIC(3,1) CHECK (predicted_mood IS NULL OR (predicted_mood >= 0 AND predicted_mood <= 10)),
  mood_context TEXT,

  -- Quest
  quest_id UUID REFERENCES quests(id) ON DELETE SET NULL,
  quest_title TEXT,

  -- Calendar events (JSONB array)
  calendar_events JSONB DEFAULT '[]'::jsonb,

  -- Personalized suggestion
  suggestion TEXT NOT NULL,

  -- Metadata
  generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_viewed_at TIMESTAMPTZ,

  -- Phase 2 fields (nullable, will be populated in future)
  wellness_score NUMERIC(3,1) CHECK (wellness_score IS NULL OR (wellness_score >= 0 AND wellness_score <= 10)),
  important_dates JSONB DEFAULT '[]'::jsonb,
  audio_text TEXT,
  audio_url TEXT,
  voice_played BOOLEAN DEFAULT false,

  -- Constraints
  UNIQUE(user_id, local_date),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- TABLE: briefing_preferences
-- ============================================================================
-- User preferences for briefing generation
CREATE TABLE IF NOT EXISTS briefing_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Briefing toggle
  enabled BOOLEAN NOT NULL DEFAULT true,

  -- Calendar integration
  include_calendar BOOLEAN NOT NULL DEFAULT true,
  calendar_lookahead_hours INTEGER NOT NULL DEFAULT 24 CHECK (calendar_lookahead_hours BETWEEN 1 AND 48),

  -- Phase 2: Notification delivery time (for push notifications)
  preferred_time TIME DEFAULT '08:00:00',

  -- Phase 2: Voice preferences (nullable, will be used in Phase 2)
  voice_enabled BOOLEAN DEFAULT false,
  voice_provider TEXT,
  voice_id TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_daily_briefings_user_date
  ON daily_briefings(user_id, local_date DESC);

CREATE INDEX IF NOT EXISTS idx_daily_briefings_generated_at
  ON daily_briefings(generated_at DESC);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================
ALTER TABLE daily_briefings ENABLE ROW LEVEL SECURITY;
ALTER TABLE briefing_preferences ENABLE ROW LEVEL SECURITY;

-- daily_briefings: Users can read their own
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'daily_briefings'
    AND policyname = 'Users can read own briefings'
  ) THEN
    CREATE POLICY "Users can read own briefings"
      ON daily_briefings
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- daily_briefings: Service role can insert (Edge Function)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'daily_briefings'
    AND policyname = 'Service role can insert briefings'
  ) THEN
    CREATE POLICY "Service role can insert briefings"
      ON daily_briefings
      FOR INSERT
      WITH CHECK (true); -- Service role bypasses RLS but policy needed for explicit permission
  END IF;
END $$;

-- daily_briefings: Users can update their own (for last_viewed_at)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'daily_briefings'
    AND policyname = 'Users can update own briefings'
  ) THEN
    CREATE POLICY "Users can update own briefings"
      ON daily_briefings
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- briefing_preferences: Full CRUD for own preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'briefing_preferences'
    AND policyname = 'Users can manage own briefing preferences'
  ) THEN
    CREATE POLICY "Users can manage own briefing preferences"
      ON briefing_preferences
      FOR ALL
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- ============================================================================
-- TRIGGER: Update updated_at timestamp
-- ============================================================================
CREATE OR REPLACE FUNCTION update_briefing_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_daily_briefings_updated_at ON daily_briefings;
CREATE TRIGGER update_daily_briefings_updated_at
  BEFORE UPDATE ON daily_briefings
  FOR EACH ROW
  EXECUTE FUNCTION update_briefing_updated_at();

DROP TRIGGER IF EXISTS update_briefing_preferences_updated_at ON briefing_preferences;
CREATE TRIGGER update_briefing_preferences_updated_at
  BEFORE UPDATE ON briefing_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_briefing_updated_at();

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE daily_briefings IS 'F009: Personalized daily briefings - one per user per day';
COMMENT ON TABLE briefing_preferences IS 'F009: User preferences for briefing generation and delivery';

COMMENT ON COLUMN daily_briefings.local_date IS 'Date in user timezone (YYYY-MM-DD), ensures one briefing per day per user';
COMMENT ON COLUMN daily_briefings.calendar_events IS 'Array of calendar events from EventKit: [{"title", "start_time", "end_time", "location"}]';
COMMENT ON COLUMN daily_briefings.suggestion IS 'Personalized suggestion based on sleep, calendar, mood prediction, or default encouragement';
COMMENT ON COLUMN daily_briefings.wellness_score IS 'Phase 2: From F002 Daily Wellness Score';
COMMENT ON COLUMN daily_briefings.important_dates IS 'Phase 2: Upcoming birthdays/anniversaries from companion memory';
COMMENT ON COLUMN daily_briefings.audio_text IS 'Phase 2: TTS-optimized text for voice playback';
COMMENT ON COLUMN daily_briefings.audio_url IS 'Phase 2: Pre-generated audio file URL';

COMMENT ON COLUMN briefing_preferences.calendar_lookahead_hours IS 'How many hours ahead to query calendar events (24 or 48)';
COMMENT ON COLUMN briefing_preferences.preferred_time IS 'Phase 2: Time to deliver push notification (HH:MM:SS)';
COMMENT ON COLUMN briefing_preferences.voice_enabled IS 'Phase 2: Enable voice playback feature';
