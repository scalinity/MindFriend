-- Migration: 20260303000000_live_experiences.sql
-- Description: Live & Synchronous Experiences - Daily live sessions, circle rooms, presence
-- See: docs/specs/03-live-experiences.md

-- =============================================================================
-- MARK: - Live Sessions Table
-- Scheduled live sessions (managed by MindFriend)
-- =============================================================================

CREATE TABLE IF NOT EXISTS live_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  session_type TEXT NOT NULL CHECK (session_type IN ('breathing', 'meditation', 'body_scan')),
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end TIMESTAMPTZ NOT NULL,
  audio_url TEXT,
  is_recurring BOOLEAN NOT NULL DEFAULT TRUE,
  recurrence_rule TEXT,  -- RRULE format
  max_participants INT,  -- NULL = unlimited
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_sessions_scheduled ON live_sessions(scheduled_start) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_live_sessions_active ON live_sessions(is_active, scheduled_end);

-- =============================================================================
-- MARK: - Live Session Participants
-- Tracks who joins live sessions
-- =============================================================================

CREATE TABLE IF NOT EXISTS live_session_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at TIMESTAMPTZ,
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  reactions_sent INT NOT NULL DEFAULT 0,
  UNIQUE(session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_live_participants_session ON live_session_participants(session_id, joined_at);
CREATE INDEX IF NOT EXISTS idx_live_participants_user ON live_session_participants(user_id, joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_participants_active ON live_session_participants(session_id) WHERE left_at IS NULL;

-- =============================================================================
-- MARK: - Circle Live Rooms
-- Real-time group activities within friend circles
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_live_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL CHECK (activity_type IN ('breathing', 'meditation', 'body_scan', 'custom')),
  exercise_id UUID REFERENCES exercises(id),
  title TEXT,
  duration_minutes INT NOT NULL CHECK (duration_minutes BETWEEN 1 AND 30),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_circle_rooms_circle ON circle_live_rooms(circle_id, status);
CREATE INDEX IF NOT EXISTS idx_circle_rooms_active ON circle_live_rooms(status, ends_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_circle_rooms_creator ON circle_live_rooms(created_by);

-- =============================================================================
-- MARK: - Circle Room Participants
-- Tracks who joins circle live rooms
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_room_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES circle_live_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at TIMESTAMPTZ,
  completed BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE(room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_circle_room_participants ON circle_room_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_circle_room_participants_user ON circle_room_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_circle_room_participants_active ON circle_room_participants(room_id) WHERE left_at IS NULL;

-- =============================================================================
-- MARK: - Buddy Quest Windows
-- Accountability windows for buddy pairs
-- =============================================================================

CREATE TABLE IF NOT EXISTS buddy_quest_windows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buddy_relationship_id UUID NOT NULL REFERENCES buddy_relationships(id) ON DELETE CASCADE,
  window_start_local TIME NOT NULL,
  window_end_local TIME NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, buddy_relationship_id)
);

CREATE INDEX IF NOT EXISTS idx_buddy_windows_user ON buddy_quest_windows(user_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_buddy_windows_relationship ON buddy_quest_windows(buddy_relationship_id);

-- =============================================================================
-- MARK: - Buddy Window Events
-- Activity log for buddy accountability windows
-- =============================================================================

CREATE TABLE IF NOT EXISTS buddy_window_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  window_id UUID NOT NULL REFERENCES buddy_quest_windows(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('window_open', 'quest_started', 'quest_completed', 'encouragement_sent', 'window_closed')),
  actor_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_buddy_window_events ON buddy_window_events(window_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_buddy_window_events_actor ON buddy_window_events(actor_user_id);

-- =============================================================================
-- MARK: - User Presence
-- Tracks online status (updated frequently, short TTL)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_presence (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'online' CHECK (status IN ('online', 'away', 'offline')),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  current_activity TEXT,  -- 'quest', 'exercise', 'chat', 'browsing'
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_presence_last_seen ON user_presence(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_presence_status ON user_presence(status) WHERE status = 'online';

-- =============================================================================
-- MARK: - User Settings Extensions
-- Presence visibility settings
-- =============================================================================

ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS show_presence BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS show_activity_status BOOLEAN DEFAULT FALSE;

-- =============================================================================
-- MARK: - Row Level Security
-- =============================================================================

ALTER TABLE live_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_session_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_live_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE buddy_quest_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE buddy_window_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_presence ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- MARK: - Live Sessions Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'live_sessions' AND policyname = 'Live sessions readable by all authenticated') THEN
    CREATE POLICY "Live sessions readable by all authenticated" ON live_sessions
      FOR SELECT TO authenticated USING (is_active = TRUE);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Live Session Participants Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'live_session_participants' AND policyname = 'Users can view own participation') THEN
    CREATE POLICY "Users can view own participation" ON live_session_participants
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'live_session_participants' AND policyname = 'Users can insert own participation') THEN
    CREATE POLICY "Users can insert own participation" ON live_session_participants
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'live_session_participants' AND policyname = 'Users can update own participation') THEN
    CREATE POLICY "Users can update own participation" ON live_session_participants
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Circle Live Rooms Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_live_rooms' AND policyname = 'Circle members can view rooms') THEN
    CREATE POLICY "Circle members can view rooms" ON circle_live_rooms
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM circle_members cm
          WHERE cm.circle_id = circle_live_rooms.circle_id
            AND cm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_live_rooms' AND policyname = 'Circle members can create rooms') THEN
    CREATE POLICY "Circle members can create rooms" ON circle_live_rooms
      FOR INSERT WITH CHECK (
        auth.uid() = created_by
        AND EXISTS (
          SELECT 1 FROM circle_members cm
          WHERE cm.circle_id = circle_live_rooms.circle_id
            AND cm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_live_rooms' AND policyname = 'Room creator can update room') THEN
    CREATE POLICY "Room creator can update room" ON circle_live_rooms
      FOR UPDATE USING (auth.uid() = created_by);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Circle Room Participants Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_room_participants' AND policyname = 'Circle members can view room participants') THEN
    CREATE POLICY "Circle members can view room participants" ON circle_room_participants
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM circle_live_rooms clr
          JOIN circle_members cm ON cm.circle_id = clr.circle_id
          WHERE clr.id = circle_room_participants.room_id
            AND cm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_room_participants' AND policyname = 'Users can insert own room participation') THEN
    CREATE POLICY "Users can insert own room participation" ON circle_room_participants
      FOR INSERT WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (
          SELECT 1 FROM circle_live_rooms clr
          JOIN circle_members cm ON cm.circle_id = clr.circle_id
          WHERE clr.id = circle_room_participants.room_id
            AND cm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_room_participants' AND policyname = 'Users can update own room participation') THEN
    CREATE POLICY "Users can update own room participation" ON circle_room_participants
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Buddy Quest Windows Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buddy_quest_windows' AND policyname = 'Users can view own buddy windows') THEN
    CREATE POLICY "Users can view own buddy windows" ON buddy_quest_windows
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buddy_quest_windows' AND policyname = 'Buddies can view partner windows') THEN
    CREATE POLICY "Buddies can view partner windows" ON buddy_quest_windows
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM buddy_relationships br
          WHERE br.id = buddy_quest_windows.buddy_relationship_id
            AND br.status = 'accepted'
            AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buddy_quest_windows' AND policyname = 'Users can insert own buddy windows') THEN
    CREATE POLICY "Users can insert own buddy windows" ON buddy_quest_windows
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buddy_quest_windows' AND policyname = 'Users can update own buddy windows') THEN
    CREATE POLICY "Users can update own buddy windows" ON buddy_quest_windows
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Buddy Window Events Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buddy_window_events' AND policyname = 'Buddies can view window events') THEN
    CREATE POLICY "Buddies can view window events" ON buddy_window_events
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM buddy_quest_windows bqw
          JOIN buddy_relationships br ON br.id = bqw.buddy_relationship_id
          WHERE bqw.id = buddy_window_events.window_id
            AND br.status = 'accepted'
            AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'buddy_window_events' AND policyname = 'Users can insert own window events') THEN
    CREATE POLICY "Users can insert own window events" ON buddy_window_events
      FOR INSERT WITH CHECK (auth.uid() = actor_user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - User Presence Policies
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_presence' AND policyname = 'Users can view own presence') THEN
    CREATE POLICY "Users can view own presence" ON user_presence
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_presence' AND policyname = 'Connections can view presence') THEN
    CREATE POLICY "Connections can view presence" ON user_presence
      FOR SELECT USING (
        -- Circle members can see each other
        user_id IN (
          SELECT cm2.user_id FROM circle_members cm1
          JOIN circle_members cm2 ON cm1.circle_id = cm2.circle_id
          WHERE cm1.user_id = auth.uid()
        )
        OR
        -- Buddies can see each other
        user_id IN (
          SELECT CASE WHEN br.inviter_id = auth.uid() THEN br.invitee_id ELSE br.inviter_id END
          FROM buddy_relationships br
          WHERE br.status = 'accepted'
            AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_presence' AND policyname = 'Users can upsert own presence') THEN
    CREATE POLICY "Users can upsert own presence" ON user_presence
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_presence' AND policyname = 'Users can update own presence') THEN
    CREATE POLICY "Users can update own presence" ON user_presence
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Seed Data - Daily Live Sessions
-- =============================================================================

INSERT INTO live_sessions (title, description, session_type, scheduled_start, scheduled_end, is_recurring, recurrence_rule)
VALUES
  -- Morning Calm (07:00 UTC daily)
  ('Morning Calm', 'Start your day with gentle breathing and intention setting', 'breathing',
   '2026-01-01 07:00:00+00'::TIMESTAMPTZ, '2026-01-01 07:10:00+00'::TIMESTAMPTZ,
   TRUE, 'FREQ=DAILY;BYHOUR=7;BYMINUTE=0'),

  -- Midday Reset (12:00 UTC daily)
  ('Midday Reset', 'Take a mindful break to recharge your afternoon', 'meditation',
   '2026-01-01 12:00:00+00'::TIMESTAMPTZ, '2026-01-01 12:10:00+00'::TIMESTAMPTZ,
   TRUE, 'FREQ=DAILY;BYHOUR=12;BYMINUTE=0'),

  -- Afternoon Refresh (17:00 UTC daily)
  ('Afternoon Refresh', 'Release the tension of the day with body awareness', 'body_scan',
   '2026-01-01 17:00:00+00'::TIMESTAMPTZ, '2026-01-01 17:10:00+00'::TIMESTAMPTZ,
   TRUE, 'FREQ=DAILY;BYHOUR=17;BYMINUTE=0'),

  -- Evening Wind-Down (21:00 UTC daily)
  ('Evening Wind-Down', 'Prepare for restful sleep with calming meditation', 'meditation',
   '2026-01-01 21:00:00+00'::TIMESTAMPTZ, '2026-01-01 21:15:00+00'::TIMESTAMPTZ,
   TRUE, 'FREQ=DAILY;BYHOUR=21;BYMINUTE=0'),

  -- Night Owl Session (01:00 UTC daily)
  ('Night Owl Session', 'For those who find peace in the quiet hours', 'breathing',
   '2026-01-01 01:00:00+00'::TIMESTAMPTZ, '2026-01-01 01:10:00+00'::TIMESTAMPTZ,
   TRUE, 'FREQ=DAILY;BYHOUR=1;BYMINUTE=0')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- MARK: - Helper Functions
-- =============================================================================

-- Get current/upcoming live sessions with participant counts
CREATE OR REPLACE FUNCTION get_live_sessions()
RETURNS TABLE(
  id UUID,
  title TEXT,
  description TEXT,
  session_type TEXT,
  scheduled_start TIMESTAMPTZ,
  scheduled_end TIMESTAMPTZ,
  audio_url TEXT,
  participant_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ls.id,
    ls.title,
    ls.description,
    ls.session_type,
    ls.scheduled_start,
    ls.scheduled_end,
    ls.audio_url,
    COALESCE(p.cnt, 0) AS participant_count
  FROM live_sessions ls
  LEFT JOIN (
    SELECT session_id, COUNT(*) AS cnt
    FROM live_session_participants
    WHERE left_at IS NULL
    GROUP BY session_id
  ) p ON p.session_id = ls.id
  WHERE ls.is_active = TRUE
    AND ls.scheduled_end > NOW()
  ORDER BY ls.scheduled_start ASC
  LIMIT 10;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get active circle rooms for a user's circles
CREATE OR REPLACE FUNCTION get_active_circle_rooms()
RETURNS TABLE(
  id UUID,
  circle_id UUID,
  circle_name TEXT,
  created_by UUID,
  creator_name TEXT,
  activity_type TEXT,
  title TEXT,
  duration_minutes INT,
  started_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  participant_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    clr.id,
    clr.circle_id,
    c.name AS circle_name,
    clr.created_by,
    p.display_name AS creator_name,
    clr.activity_type,
    clr.title,
    clr.duration_minutes,
    clr.started_at,
    clr.ends_at,
    COALESCE(part.cnt, 0) AS participant_count
  FROM circle_live_rooms clr
  JOIN circles c ON c.id = clr.circle_id
  JOIN profiles p ON p.id = clr.created_by
  JOIN circle_members cm ON cm.circle_id = clr.circle_id AND cm.user_id = auth.uid()
  LEFT JOIN (
    SELECT room_id, COUNT(*) AS cnt
    FROM circle_room_participants
    WHERE left_at IS NULL
    GROUP BY room_id
  ) part ON part.room_id = clr.id
  WHERE clr.status = 'active'
    AND clr.ends_at > NOW()
  ORDER BY clr.started_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update user presence
CREATE OR REPLACE FUNCTION update_presence(p_activity TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
  INSERT INTO user_presence (user_id, status, last_seen_at, current_activity, updated_at)
  VALUES (auth.uid(), 'online', NOW(), p_activity, NOW())
  ON CONFLICT (user_id) DO UPDATE SET
    status = 'online',
    last_seen_at = NOW(),
    current_activity = COALESCE(p_activity, user_presence.current_activity),
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get presence for circle members
CREATE OR REPLACE FUNCTION get_circle_presence(p_circle_id UUID)
RETURNS TABLE(
  user_id UUID,
  display_name TEXT,
  status TEXT,
  last_seen_at TIMESTAMPTZ,
  current_activity TEXT,
  is_online BOOLEAN,
  is_recently_active BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    up.user_id,
    p.display_name,
    up.status,
    up.last_seen_at,
    up.current_activity,
    (up.status = 'online' AND up.last_seen_at > NOW() - INTERVAL '2 minutes') AS is_online,
    (up.last_seen_at > NOW() - INTERVAL '15 minutes') AS is_recently_active
  FROM user_presence up
  JOIN profiles p ON p.id = up.user_id
  JOIN circle_members cm ON cm.user_id = up.user_id AND cm.circle_id = p_circle_id
  JOIN user_settings us ON us.user_id = up.user_id AND us.show_presence = TRUE
  WHERE up.last_seen_at > NOW() - INTERVAL '15 minutes'
  ORDER BY up.last_seen_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Grant Execute Permissions
-- =============================================================================

-- Update reaction count for live session participant
CREATE OR REPLACE FUNCTION update_live_session_reactions(
  p_session_id UUID,
  p_user_id UUID
)
RETURNS VOID AS $$
BEGIN
  UPDATE live_session_participants
  SET reactions_sent = reactions_sent + 1
  WHERE session_id = p_session_id
    AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_live_sessions() TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_circle_rooms() TO authenticated;
GRANT EXECUTE ON FUNCTION update_presence(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_circle_presence(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_live_session_reactions(UUID, UUID) TO authenticated;
