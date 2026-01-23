-- Community Forums Schema Migration
-- Implements 9 tables with RLS policies, triggers, and full-text search
-- Per decisions.md 2026-01-19: Community Forums Implementation Assumptions

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Check if current user is a moderator
CREATE OR REPLACE FUNCTION is_moderator()
RETURNS boolean AS $$
BEGIN
  RETURN COALESCE(
    (SELECT (auth.jwt() -> 'user_metadata' ->> 'role') = 'moderator'),
    false
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Generate anonymous animal name from pool of 50 animals
CREATE OR REPLACE FUNCTION generate_anonymous_name()
RETURNS text AS $$
DECLARE
  animals text[] := ARRAY[
    'Otter', 'Fox', 'Bear', 'Deer', 'Owl', 'Rabbit', 'Squirrel', 'Hedgehog',
    'Wolf', 'Badger', 'Raccoon', 'Moose', 'Panda', 'Koala', 'Penguin',
    'Seal', 'Dolphin', 'Whale', 'Eagle', 'Hawk', 'Sparrow', 'Robin',
    'Swan', 'Duck', 'Turtle', 'Frog', 'Snake', 'Lizard', 'Butterfly', 'Bee',
    'Ant', 'Spider', 'Crab', 'Lobster', 'Starfish', 'Jellyfish', 'Octopus',
    'Shark', 'Lion', 'Tiger', 'Elephant', 'Giraffe', 'Zebra', 'Kangaroo',
    'Sloth', 'Chipmunk', 'Beaver', 'Hamster', 'Porcupine', 'Flamingo'
  ];
  selected_animal text;
BEGIN
  selected_animal := animals[floor(random() * array_length(animals, 1) + 1)];
  RETURN 'Anonymous ' || selected_animal;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- =============================================================================
-- TABLES
-- =============================================================================

-- Forum categories (Mental Health, Life & Relationships, etc.)
CREATE TABLE IF NOT EXISTS forum_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(name) >= 1 AND length(name) <= 100),
  description text,
  icon text, -- SF Symbol name
  position int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Forum boards within categories (Anxiety Support, Depression Support, etc.)
CREATE TABLE IF NOT EXISTS forum_boards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES forum_categories(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(name) >= 1 AND length(name) <= 100),
  description text,
  position int NOT NULL DEFAULT 0,
  thread_count int NOT NULL DEFAULT 0 CHECK (thread_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Forum threads (original posts)
CREATE TABLE IF NOT EXISTS forum_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_id uuid NOT NULL REFERENCES forum_boards(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_anonymous boolean NOT NULL DEFAULT false,
  anonymous_name text,
  title text NOT NULL CHECK (length(title) >= 1 AND length(title) <= 300),
  content text NOT NULL CHECK (length(content) >= 1 AND length(content) <= 10000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'flagged')),
  moderation_confidence numeric(3,2) CHECK (moderation_confidence >= 0 AND moderation_confidence <= 1),
  is_crisis boolean NOT NULL DEFAULT false,
  reply_count int NOT NULL DEFAULT 0 CHECK (reply_count >= 0),
  helpful_count int NOT NULL DEFAULT 0 CHECK (helpful_count >= 0),
  tsv tsvector, -- Full-text search vector
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Forum replies (responses to threads, nested up to 5 levels)
CREATE TABLE IF NOT EXISTS forum_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
  parent_reply_id uuid REFERENCES forum_replies(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  is_anonymous boolean NOT NULL DEFAULT false,
  anonymous_name text,
  content text NOT NULL CHECK (length(content) >= 1 AND length(content) <= 10000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'flagged')),
  moderation_confidence numeric(3,2) CHECK (moderation_confidence >= 0 AND moderation_confidence <= 1),
  is_crisis boolean NOT NULL DEFAULT false,
  helpful_count int NOT NULL DEFAULT 0 CHECK (helpful_count >= 0),
  depth int NOT NULL DEFAULT 0 CHECK (depth >= 0 AND depth <= 5),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Helpful marks (upvotes) on threads and replies
CREATE TABLE IF NOT EXISTS forum_helpful (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  thread_id uuid REFERENCES forum_threads(id) ON DELETE CASCADE,
  reply_id uuid REFERENCES forum_replies(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((thread_id IS NOT NULL AND reply_id IS NULL) OR (thread_id IS NULL AND reply_id IS NOT NULL)),
  UNIQUE (user_id, thread_id),
  UNIQUE (user_id, reply_id)
);

-- Saved threads for later reading
CREATE TABLE IF NOT EXISTS forum_saved (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  thread_id uuid NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, thread_id)
);

-- Followed threads for realtime updates
CREATE TABLE IF NOT EXISTS forum_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  thread_id uuid NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, thread_id)
);

-- Content reports (user-submitted flags for moderation)
CREATE TABLE IF NOT EXISTS forum_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  thread_id uuid REFERENCES forum_threads(id) ON DELETE CASCADE,
  reply_id uuid REFERENCES forum_replies(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (reason IN ('harassment', 'spam', 'misinformation', 'self_harm', 'other')),
  details text CHECK (details IS NULL OR length(details) <= 1000),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed')),
  reviewed_by uuid REFERENCES auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((thread_id IS NOT NULL AND reply_id IS NULL) OR (thread_id IS NULL AND reply_id IS NOT NULL))
);

-- User bans (temporary or permanent suspensions)
CREATE TABLE IF NOT EXISTS forum_bans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  reason text NOT NULL CHECK (length(reason) >= 1 AND length(reason) <= 500),
  banned_by uuid NOT NULL REFERENCES auth.users(id),
  banned_until timestamptz, -- NULL = permanent ban
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Rate limiting (5 threads/hour, 20 replies/hour per user)
CREATE TABLE IF NOT EXISTS user_rate_limits (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  thread_count_1h int NOT NULL DEFAULT 0 CHECK (thread_count_1h >= 0),
  reply_count_1h int NOT NULL DEFAULT 0 CHECK (reply_count_1h >= 0),
  last_thread_reset timestamptz NOT NULL DEFAULT now(),
  last_reply_reset timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Full-text search index on forum_threads
CREATE INDEX IF NOT EXISTS idx_forum_threads_tsv ON forum_threads USING GIN (tsv);

-- Thread listing by board (sorted by created_at)
CREATE INDEX IF NOT EXISTS idx_forum_threads_board_created ON forum_threads (board_id, created_at DESC) WHERE status = 'approved';

-- Thread listing by board (sorted by helpful_count for "Helpful" sort)
CREATE INDEX IF NOT EXISTS idx_forum_threads_board_helpful ON forum_threads (board_id, helpful_count DESC, created_at DESC) WHERE status = 'approved';

-- Thread listing by board (sorted by reply_count for "Popular" sort)
CREATE INDEX IF NOT EXISTS idx_forum_threads_board_popular ON forum_threads (board_id, reply_count DESC, created_at DESC) WHERE status = 'approved';

-- Moderation queue (pending/flagged threads)
CREATE INDEX IF NOT EXISTS idx_forum_threads_status ON forum_threads (status, created_at) WHERE status IN ('pending', 'flagged');

-- Crisis events queue
CREATE INDEX IF NOT EXISTS idx_forum_threads_crisis ON forum_threads (is_crisis, created_at DESC) WHERE is_crisis = true;

-- Reply listing by thread
CREATE INDEX IF NOT EXISTS idx_forum_replies_thread ON forum_replies (thread_id, created_at ASC) WHERE status = 'approved';

-- Nested reply lookup
CREATE INDEX IF NOT EXISTS idx_forum_replies_parent ON forum_replies (parent_reply_id) WHERE parent_reply_id IS NOT NULL;

-- Moderation queue for replies
CREATE INDEX IF NOT EXISTS idx_forum_replies_status ON forum_replies (status, created_at) WHERE status IN ('pending', 'flagged');

-- Report queue for moderators
CREATE INDEX IF NOT EXISTS idx_forum_reports_status ON forum_reports (status, created_at) WHERE status = 'pending';

-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE forum_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_boards ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_helpful ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_saved ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE forum_bans ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_rate_limits ENABLE ROW LEVEL SECURITY;

-- Categories: Read-only for all authenticated users
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_categories' AND policyname = 'categories_select_all') THEN
    CREATE POLICY categories_select_all ON forum_categories FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Boards: Read-only for all authenticated users
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_boards' AND policyname = 'boards_select_all') THEN
    CREATE POLICY boards_select_all ON forum_boards FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Threads: SELECT approved threads OR own threads OR moderator
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_threads' AND policyname = 'threads_select_approved_or_own') THEN
    CREATE POLICY threads_select_approved_or_own ON forum_threads FOR SELECT TO authenticated
    USING (status = 'approved' OR author_id = auth.uid() OR is_moderator());
  END IF;
END $$;

-- Threads: INSERT allowed for all authenticated users (rate limit enforced by trigger)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_threads' AND policyname = 'threads_insert_own') THEN
    CREATE POLICY threads_insert_own ON forum_threads FOR INSERT TO authenticated
    WITH CHECK (author_id = auth.uid());
  END IF;
END $$;

-- Threads: UPDATE own threads within 15 minutes OR moderator
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_threads' AND policyname = 'threads_update_own_or_moderator') THEN
    CREATE POLICY threads_update_own_or_moderator ON forum_threads FOR UPDATE TO authenticated
    USING (
      (author_id = auth.uid() AND created_at > now() - interval '15 minutes')
      OR is_moderator()
    );
  END IF;
END $$;

-- Threads: DELETE own threads OR moderator
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_threads' AND policyname = 'threads_delete_own_or_moderator') THEN
    CREATE POLICY threads_delete_own_or_moderator ON forum_threads FOR DELETE TO authenticated
    USING (author_id = auth.uid() OR is_moderator());
  END IF;
END $$;

-- Replies: SELECT approved replies OR own replies OR moderator
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_replies' AND policyname = 'replies_select_approved_or_own') THEN
    CREATE POLICY replies_select_approved_or_own ON forum_replies FOR SELECT TO authenticated
    USING (status = 'approved' OR author_id = auth.uid() OR is_moderator());
  END IF;
END $$;

-- Replies: INSERT allowed for all authenticated users (depth + rate limit enforced by trigger)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_replies' AND policyname = 'replies_insert_own') THEN
    CREATE POLICY replies_insert_own ON forum_replies FOR INSERT TO authenticated
    WITH CHECK (author_id = auth.uid());
  END IF;
END $$;

-- Replies: UPDATE own replies within 15 minutes OR moderator
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_replies' AND policyname = 'replies_update_own_or_moderator') THEN
    CREATE POLICY replies_update_own_or_moderator ON forum_replies FOR UPDATE TO authenticated
    USING (
      (author_id = auth.uid() AND created_at > now() - interval '15 minutes')
      OR is_moderator()
    );
  END IF;
END $$;

-- Replies: DELETE own replies OR moderator
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_replies' AND policyname = 'replies_delete_own_or_moderator') THEN
    CREATE POLICY replies_delete_own_or_moderator ON forum_replies FOR DELETE TO authenticated
    USING (author_id = auth.uid() OR is_moderator());
  END IF;
END $$;

-- Helpful: Users manage their own helpful marks
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_helpful' AND policyname = 'helpful_select_own') THEN
    CREATE POLICY helpful_select_own ON forum_helpful FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_helpful' AND policyname = 'helpful_insert_own') THEN
    CREATE POLICY helpful_insert_own ON forum_helpful FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_helpful' AND policyname = 'helpful_delete_own') THEN
    CREATE POLICY helpful_delete_own ON forum_helpful FOR DELETE TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

-- Saved: Users manage their own saved threads
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_saved' AND policyname = 'saved_select_own') THEN
    CREATE POLICY saved_select_own ON forum_saved FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_saved' AND policyname = 'saved_insert_own') THEN
    CREATE POLICY saved_insert_own ON forum_saved FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_saved' AND policyname = 'saved_delete_own') THEN
    CREATE POLICY saved_delete_own ON forum_saved FOR DELETE TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

-- Follows: Users manage their own followed threads
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_follows' AND policyname = 'follows_select_own') THEN
    CREATE POLICY follows_select_own ON forum_follows FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_follows' AND policyname = 'follows_insert_own') THEN
    CREATE POLICY follows_insert_own ON forum_follows FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_follows' AND policyname = 'follows_delete_own') THEN
    CREATE POLICY follows_delete_own ON forum_follows FOR DELETE TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

-- Reports: INSERT for all authenticated users, SELECT/UPDATE for moderators only
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_reports' AND policyname = 'reports_insert_own') THEN
    CREATE POLICY reports_insert_own ON forum_reports FOR INSERT TO authenticated
    WITH CHECK (reporter_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_reports' AND policyname = 'reports_select_moderator') THEN
    CREATE POLICY reports_select_moderator ON forum_reports FOR SELECT TO authenticated
    USING (is_moderator());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_reports' AND policyname = 'reports_update_moderator') THEN
    CREATE POLICY reports_update_moderator ON forum_reports FOR UPDATE TO authenticated
    USING (is_moderator());
  END IF;
END $$;

-- Bans: Moderators only
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'forum_bans' AND policyname = 'bans_all_moderator') THEN
    CREATE POLICY bans_all_moderator ON forum_bans FOR ALL TO authenticated
    USING (is_moderator()) WITH CHECK (is_moderator());
  END IF;
END $$;

-- Rate limits: Service role only (accessed via Edge Function)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_rate_limits' AND policyname = 'rate_limits_service_role') THEN
    CREATE POLICY rate_limits_service_role ON user_rate_limits FOR ALL TO service_role USING (true);
  END IF;
END $$;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Update tsvector on forum_threads for full-text search
CREATE OR REPLACE FUNCTION update_thread_tsv()
RETURNS trigger AS $$
BEGIN
  NEW.tsv := to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_thread_tsv ON forum_threads;
CREATE TRIGGER trigger_update_thread_tsv
  BEFORE INSERT OR UPDATE OF title, content
  ON forum_threads
  FOR EACH ROW
  EXECUTE FUNCTION update_thread_tsv();

-- Update updated_at timestamp on forum_threads
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_thread_updated_at ON forum_threads;
CREATE TRIGGER trigger_update_thread_updated_at
  BEFORE UPDATE ON forum_threads
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS trigger_update_reply_updated_at ON forum_replies;
CREATE TRIGGER trigger_update_reply_updated_at
  BEFORE UPDATE ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- Check if user is banned before inserting thread/reply
CREATE OR REPLACE FUNCTION check_user_ban()
RETURNS trigger AS $$
DECLARE
  ban_record RECORD;
BEGIN
  SELECT * INTO ban_record
  FROM forum_bans
  WHERE user_id = NEW.author_id
    AND (banned_until IS NULL OR banned_until > now());

  IF FOUND THEN
    RAISE EXCEPTION 'User is banned until %', COALESCE(ban_record.banned_until::text, 'permanent');
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_ban_thread ON forum_threads;
CREATE TRIGGER trigger_check_ban_thread
  BEFORE INSERT ON forum_threads
  FOR EACH ROW
  EXECUTE FUNCTION check_user_ban();

DROP TRIGGER IF EXISTS trigger_check_ban_reply ON forum_replies;
CREATE TRIGGER trigger_check_ban_reply
  BEFORE INSERT ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION check_user_ban();

-- Calculate reply depth and reject if > 5 levels
CREATE OR REPLACE FUNCTION calculate_reply_depth()
RETURNS trigger AS $$
BEGIN
  IF NEW.parent_reply_id IS NULL THEN
    NEW.depth := 0;
  ELSE
    SELECT depth + 1 INTO NEW.depth
    FROM forum_replies
    WHERE id = NEW.parent_reply_id;

    IF NEW.depth > 5 THEN
      RAISE EXCEPTION 'Maximum reply depth (5 levels) exceeded';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_calculate_reply_depth ON forum_replies;
CREATE TRIGGER trigger_calculate_reply_depth
  BEFORE INSERT ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION calculate_reply_depth();

-- Increment board thread_count when thread is approved
CREATE OR REPLACE FUNCTION increment_board_thread_count()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
    UPDATE forum_boards
    SET thread_count = thread_count + 1
    WHERE id = NEW.board_id;
  ELSIF OLD.status = 'approved' AND NEW.status != 'approved' THEN
    UPDATE forum_boards
    SET thread_count = thread_count - 1
    WHERE id = NEW.board_id AND thread_count > 0;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_increment_board_thread_count ON forum_threads;
CREATE TRIGGER trigger_increment_board_thread_count
  AFTER INSERT OR UPDATE OF status ON forum_threads
  FOR EACH ROW
  EXECUTE FUNCTION increment_board_thread_count();

-- Decrement board thread_count when thread is deleted
CREATE OR REPLACE FUNCTION decrement_board_thread_count()
RETURNS trigger AS $$
BEGIN
  IF OLD.status = 'approved' THEN
    UPDATE forum_boards
    SET thread_count = thread_count - 1
    WHERE id = OLD.board_id AND thread_count > 0;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_decrement_board_thread_count ON forum_threads;
CREATE TRIGGER trigger_decrement_board_thread_count
  AFTER DELETE ON forum_threads
  FOR EACH ROW
  EXECUTE FUNCTION decrement_board_thread_count();

-- Increment thread reply_count when reply is approved
CREATE OR REPLACE FUNCTION increment_thread_reply_count()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
    UPDATE forum_threads
    SET reply_count = reply_count + 1
    WHERE id = NEW.thread_id;
  ELSIF OLD.status = 'approved' AND NEW.status != 'approved' THEN
    UPDATE forum_threads
    SET reply_count = reply_count - 1
    WHERE id = NEW.thread_id AND reply_count > 0;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_increment_thread_reply_count ON forum_replies;
CREATE TRIGGER trigger_increment_thread_reply_count
  AFTER INSERT OR UPDATE OF status ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION increment_thread_reply_count();

-- Decrement thread reply_count when reply is deleted
CREATE OR REPLACE FUNCTION decrement_thread_reply_count()
RETURNS trigger AS $$
BEGIN
  IF OLD.status = 'approved' THEN
    UPDATE forum_threads
    SET reply_count = reply_count - 1
    WHERE id = OLD.thread_id AND reply_count > 0;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_decrement_thread_reply_count ON forum_replies;
CREATE TRIGGER trigger_decrement_thread_reply_count
  AFTER DELETE ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION decrement_thread_reply_count();

-- Increment thread/reply helpful_count when helpful mark is added
CREATE OR REPLACE FUNCTION increment_helpful_count()
RETURNS trigger AS $$
BEGIN
  IF NEW.thread_id IS NOT NULL THEN
    UPDATE forum_threads
    SET helpful_count = helpful_count + 1
    WHERE id = NEW.thread_id;
  ELSIF NEW.reply_id IS NOT NULL THEN
    UPDATE forum_replies
    SET helpful_count = helpful_count + 1
    WHERE id = NEW.reply_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_increment_helpful_count ON forum_helpful;
CREATE TRIGGER trigger_increment_helpful_count
  AFTER INSERT ON forum_helpful
  FOR EACH ROW
  EXECUTE FUNCTION increment_helpful_count();

-- Decrement thread/reply helpful_count when helpful mark is removed
CREATE OR REPLACE FUNCTION decrement_helpful_count()
RETURNS trigger AS $$
BEGIN
  IF OLD.thread_id IS NOT NULL THEN
    UPDATE forum_threads
    SET helpful_count = helpful_count - 1
    WHERE id = OLD.thread_id AND helpful_count > 0;
  ELSIF OLD.reply_id IS NOT NULL THEN
    UPDATE forum_replies
    SET helpful_count = helpful_count - 1
    WHERE id = OLD.reply_id AND helpful_count > 0;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_decrement_helpful_count ON forum_helpful;
CREATE TRIGGER trigger_decrement_helpful_count
  AFTER DELETE ON forum_helpful
  FOR EACH ROW
  EXECUTE FUNCTION decrement_helpful_count();

-- Generate anonymous name if is_anonymous=true and anonymous_name is null
CREATE OR REPLACE FUNCTION set_anonymous_name()
RETURNS trigger AS $$
BEGIN
  IF NEW.is_anonymous = true AND NEW.anonymous_name IS NULL THEN
    NEW.anonymous_name := generate_anonymous_name();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_anonymous_name_thread ON forum_threads;
CREATE TRIGGER trigger_set_anonymous_name_thread
  BEFORE INSERT ON forum_threads
  FOR EACH ROW
  EXECUTE FUNCTION set_anonymous_name();

DROP TRIGGER IF EXISTS trigger_set_anonymous_name_reply ON forum_replies;
CREATE TRIGGER trigger_set_anonymous_name_reply
  BEFORE INSERT ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION set_anonymous_name();

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Seed categories (per spec: Mental Health, Life & Relationships)
INSERT INTO forum_categories (name, description, icon, position) VALUES
  ('Mental Health Support', 'Share experiences, find support, and connect with others on their mental health journey.', 'heart.text.square.fill', 1),
  ('Life & Relationships', 'Discuss work, relationships, family, and everyday challenges.', 'person.2.fill', 2)
ON CONFLICT DO NOTHING;

-- Seed boards within Mental Health Support category
INSERT INTO forum_boards (category_id, name, description, position)
SELECT
  cat.id,
  board.name,
  board.description,
  board.position
FROM forum_categories cat,
LATERAL (VALUES
  ('Anxiety & Stress', 'Managing anxiety, panic attacks, and stress. You''re not alone.', 1),
  ('Depression', 'Support for depression, low mood, and finding hope.', 2),
  ('General Mental Health', 'All other mental health topics and questions.', 3)
) AS board(name, description, position)
WHERE cat.name = 'Mental Health Support'
ON CONFLICT DO NOTHING;

-- Seed boards within Life & Relationships category
INSERT INTO forum_boards (category_id, name, description, position)
SELECT
  cat.id,
  board.name,
  board.description,
  board.position
FROM forum_categories cat,
LATERAL (VALUES
  ('Work & Career', 'Job stress, career transitions, work-life balance.', 1),
  ('Relationships & Family', 'Romantic relationships, family dynamics, friendships.', 2)
) AS board(name, description, position)
WHERE cat.name = 'Life & Relationships'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================

-- Note: Rate limiting for threads (5/hour) and replies (20/hour) is enforced
-- via the moderate-forum-content Edge Function, not database triggers.
-- This allows for flexible rate limit configuration without schema changes.
