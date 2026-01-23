-- Circle Virality Feature Migration
-- Adds: hugs, challenges, reactions, invite tracking
-- See: specs/03-circle-virality.md

-- =============================================================================
-- MARK: - Profiles (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  handle TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  email TEXT,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  subscription_tier TEXT NOT NULL DEFAULT 'free' CHECK (subscription_tier IN ('free', 'premium')),
  daily_ai_quota INT NOT NULL DEFAULT 20,
  daily_ai_used INT NOT NULL DEFAULT 0,
  quota_reset_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  current_streak_days INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can view own profile'
  ) THEN
    CREATE POLICY "Users can view own profile" ON profiles
      FOR SELECT USING (auth.uid() = id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile" ON profiles
      FOR UPDATE USING (auth.uid() = id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can insert own profile'
  ) THEN
    CREATE POLICY "Users can insert own profile" ON profiles
      FOR INSERT WITH CHECK (auth.uid() = id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Circles (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS circles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  invite_code TEXT UNIQUE NOT NULL,
  max_members INT NOT NULL DEFAULT 10,
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE circles ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- MARK: - Circle Members (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(circle_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_circle_members_user ON circle_members(user_id);
CREATE INDEX IF NOT EXISTS idx_circle_members_circle ON circle_members(circle_id);

ALTER TABLE circle_members ENABLE ROW LEVEL SECURITY;

-- Helper function for circle membership check
CREATE OR REPLACE FUNCTION public.is_circle_member(check_circle_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = check_circle_id
    AND user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_circle_member(uuid) TO authenticated;

-- RLS policies for circles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circles' AND policyname = 'Members can view circles'
  ) THEN
    CREATE POLICY "Members can view circles" ON circles
      FOR SELECT USING (public.is_circle_member(id) OR owner_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circles' AND policyname = 'Owner can update circles'
  ) THEN
    CREATE POLICY "Owner can update circles" ON circles
      FOR UPDATE USING (owner_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circles' AND policyname = 'Users can create circles'
  ) THEN
    CREATE POLICY "Users can create circles" ON circles
      FOR INSERT WITH CHECK (owner_id = auth.uid());
  END IF;
END $$;

-- RLS policies for circle_members
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circle_members' AND policyname = 'Members can view circle members'
  ) THEN
    CREATE POLICY "Members can view circle members" ON circle_members
      FOR SELECT USING (public.is_circle_member(circle_id));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circle_members' AND policyname = 'Users can join circles'
  ) THEN
    CREATE POLICY "Users can join circles" ON circle_members
      FOR INSERT WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- =============================================================================
-- MARK: - Exercises (needed for challenges)
-- =============================================================================

CREATE TABLE IF NOT EXISTS exercises (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  duration_seconds INT NOT NULL,
  content_kind TEXT NOT NULL CHECK (content_kind IN ('text', 'audio', 'guided')),
  content_text TEXT,
  audio_url TEXT,
  premium_only BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'exercises' AND policyname = 'Anyone can view exercises'
  ) THEN
    CREATE POLICY "Anyone can view exercises" ON exercises
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Circle Posts (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL DEFAULT 'checkin' CHECK (kind IN ('checkin', 'milestone')),
  mood_emoji TEXT,
  body_text TEXT,
  local_date TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_circle_posts_circle ON circle_posts(circle_id, created_at DESC);

ALTER TABLE circle_posts ENABLE ROW LEVEL SECURITY;

-- Circle members can view posts in their circles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circle_posts' AND policyname = 'Members can view circle posts'
  ) THEN
    CREATE POLICY "Members can view circle posts"
      ON circle_posts FOR SELECT
      USING (public.is_circle_member(circle_id));
  END IF;
END $$;

-- Members can create posts in their circles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'circle_posts' AND policyname = 'Members can create posts'
  ) THEN
    CREATE POLICY "Members can create posts"
      ON circle_posts FOR INSERT
      WITH CHECK (auth.uid() = user_id AND public.is_circle_member(circle_id));
  END IF;
END $$;

-- =============================================================================
-- MARK: - Circle Hugs
-- One-tap encouragement with 5/day limit per recipient
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_hugs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_date DATE NOT NULL DEFAULT CURRENT_DATE,

  -- Prevent spam: max one hug per sender-recipient pair per day
  CONSTRAINT unique_hug_per_day UNIQUE (sender_id, recipient_id, created_date)
);

CREATE INDEX idx_hugs_recipient ON circle_hugs(recipient_id, created_at DESC);
CREATE INDEX idx_hugs_circle ON circle_hugs(circle_id, created_at DESC);

ALTER TABLE circle_hugs ENABLE ROW LEVEL SECURITY;

-- Members can send hugs in their circles
CREATE POLICY "Members can send hugs in their circles"
  ON circle_hugs FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id
    AND public.is_circle_member(circle_id)
  );

-- Members can see hugs in their circles
CREATE POLICY "Members can see hugs in their circles"
  ON circle_hugs FOR SELECT
  USING (
    public.is_circle_member(circle_id)
  );

-- =============================================================================
-- MARK: - Check Hug Limit Function
-- Atomic check for daily hug limit (5 per sender-recipient pair per day)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_hug_limit(
  p_sender_id UUID,
  p_recipient_id UUID,
  p_limit INT DEFAULT 5
)
RETURNS TABLE(allowed BOOLEAN, count_today INT, remaining INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  -- Count hugs sent today from this sender to this recipient
  SELECT COUNT(*)
  INTO v_count
  FROM circle_hugs
  WHERE sender_id = p_sender_id
    AND recipient_id = p_recipient_id
    AND created_at::date = CURRENT_DATE;

  RETURN QUERY SELECT
    v_count < p_limit AS allowed,
    v_count AS count_today,
    GREATEST(0, p_limit - v_count) AS remaining;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_hug_limit(UUID, UUID, INT) TO authenticated;

-- =============================================================================
-- MARK: - Hug Limit Trigger (Fix 2: Atomic enforcement)
-- Prevents race conditions where concurrent INSERTs could exceed the limit
-- =============================================================================

CREATE OR REPLACE FUNCTION enforce_hug_limit()
RETURNS TRIGGER AS $$
DECLARE
  v_count INT;
BEGIN
  -- Count hugs sent today from this sender to this recipient
  SELECT COUNT(*) INTO v_count
  FROM circle_hugs
  WHERE sender_id = NEW.sender_id
    AND recipient_id = NEW.recipient_id
    AND created_at::date = CURRENT_DATE;

  IF v_count >= 5 THEN
    RAISE EXCEPTION 'Daily hug limit reached (5 per recipient per day)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_hug_limit_trigger
  BEFORE INSERT ON circle_hugs
  FOR EACH ROW EXECUTE FUNCTION enforce_hug_limit();

COMMENT ON FUNCTION enforce_hug_limit IS 'Trigger function that enforces 5 hugs/day limit per sender-recipient pair atomically';

-- =============================================================================
-- MARK: - Circle Challenges
-- 24-hour challenges created by circle owner
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  challenge_type TEXT NOT NULL CHECK (challenge_type IN ('exercise', 'mood_checkin', 'quest', 'custom')),
  title TEXT NOT NULL,
  description TEXT,
  target_exercise_id UUID REFERENCES exercises(id),
  starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT valid_challenge_timeframe CHECK (ends_at > starts_at)
);

CREATE INDEX idx_challenges_circle ON circle_challenges(circle_id, ends_at DESC);
CREATE INDEX idx_challenges_active ON circle_challenges(circle_id, starts_at, ends_at);

ALTER TABLE circle_challenges ENABLE ROW LEVEL SECURITY;

-- Members can view challenges in their circles
CREATE POLICY "Members can view circle challenges"
  ON circle_challenges FOR SELECT
  USING (
    public.is_circle_member(circle_id)
  );

-- Only circle owner can create challenges
CREATE POLICY "Owner can create challenges"
  ON circle_challenges FOR INSERT
  WITH CHECK (
    auth.uid() = created_by
    AND EXISTS (
      SELECT 1 FROM circles
      WHERE id = circle_challenges.circle_id
      AND owner_id = auth.uid()
    )
  );

-- =============================================================================
-- MARK: - Challenge Completions
-- Track who has completed each challenge
-- =============================================================================

CREATE TABLE IF NOT EXISTS challenge_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id UUID NOT NULL REFERENCES circle_challenges(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(challenge_id, user_id)
);

CREATE INDEX idx_completions_challenge ON challenge_completions(challenge_id);
CREATE INDEX idx_completions_user ON challenge_completions(user_id, completed_at DESC);

ALTER TABLE challenge_completions ENABLE ROW LEVEL SECURITY;

-- Members can mark their own completion (only in circles they belong to)
-- Fix 4: Added is_circle_member() check to prevent non-members from completing
CREATE POLICY "Members can mark completion in their circles"
  ON challenge_completions FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM circle_challenges c
      WHERE c.id = challenge_completions.challenge_id
      AND public.is_circle_member(c.circle_id)
    )
  );

-- Members can view completions for challenges in their circles
CREATE POLICY "Members can view completions"
  ON challenge_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM circle_challenges c
      WHERE c.id = challenge_completions.challenge_id
      AND public.is_circle_member(c.circle_id)
    )
  );

-- =============================================================================
-- MARK: - Circle Reactions
-- Emoji reactions on posts (especially milestone posts)
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES circle_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL CHECK (emoji IN ('🎉', '👏', '💪', '❤️', '🔥')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One reaction per user per post (can change emoji via upsert)
  UNIQUE(post_id, user_id)
);

CREATE INDEX idx_reactions_post ON circle_reactions(post_id);

ALTER TABLE circle_reactions ENABLE ROW LEVEL SECURITY;

-- Members can add reactions to posts in their circles
CREATE POLICY "Members can add reactions"
  ON circle_reactions FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM circle_posts p
      WHERE p.id = circle_reactions.post_id
      AND public.is_circle_member(p.circle_id)
    )
  );

-- Members can update their own reactions
CREATE POLICY "Members can update own reactions"
  ON circle_reactions FOR UPDATE
  USING (auth.uid() = user_id);

-- Members can delete their own reactions
CREATE POLICY "Members can delete own reactions"
  ON circle_reactions FOR DELETE
  USING (auth.uid() = user_id);

-- Members can view reactions on posts in their circles
CREATE POLICY "Members can view reactions"
  ON circle_reactions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM circle_posts p
      WHERE p.id = circle_reactions.post_id
      AND public.is_circle_member(p.circle_id)
    )
  );

-- =============================================================================
-- MARK: - Update Circle Posts
-- Add 'challenge_complete' to post types
-- Fix 1: Backwards-compatible column addition (keeps 'kind' during rollout)
-- =============================================================================

-- Add new column alongside existing 'kind' (backwards compatible)
ALTER TABLE circle_posts ADD COLUMN IF NOT EXISTS post_type TEXT;

-- Migrate existing data from 'kind' to 'post_type'
UPDATE circle_posts SET post_type = kind WHERE post_type IS NULL;

-- Set NOT NULL constraint after data migration
ALTER TABLE circle_posts ALTER COLUMN post_type SET NOT NULL;

-- Add constraint for valid post types
ALTER TABLE circle_posts DROP CONSTRAINT IF EXISTS circle_posts_kind_check;
ALTER TABLE circle_posts ADD CONSTRAINT circle_posts_post_type_check
  CHECK (post_type IN ('checkin', 'milestone', 'challenge_complete'));

-- NOTE: Keep 'kind' column during rollout period for backwards compatibility
-- DROP COLUMN kind in a future migration after all iOS clients are updated

-- =============================================================================
-- MARK: - Circle Invites
-- Track pending invites for nudge notifications
-- =============================================================================

CREATE TABLE IF NOT EXISTS circle_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  invitee_email TEXT,
  invitee_phone TEXT,
  invite_code TEXT NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  reminder_sent_at TIMESTAMPTZ,

  -- Must have either email or phone
  CONSTRAINT invite_has_contact CHECK (invitee_email IS NOT NULL OR invitee_phone IS NOT NULL)
);

CREATE INDEX idx_invites_circle ON circle_invites(circle_id);
CREATE INDEX idx_invites_pending ON circle_invites(circle_id) WHERE accepted_at IS NULL;
CREATE INDEX idx_invites_code ON circle_invites(invite_code);
CREATE INDEX idx_invites_email ON circle_invites(invitee_email) WHERE invitee_email IS NOT NULL;
CREATE INDEX idx_invites_phone ON circle_invites(invitee_phone) WHERE invitee_phone IS NOT NULL;

ALTER TABLE circle_invites ENABLE ROW LEVEL SECURITY;

-- Circle members can view invites for their circles
CREATE POLICY "Members can view circle invites"
  ON circle_invites FOR SELECT
  USING (
    public.is_circle_member(circle_id)
  );

-- Circle members can create invites
CREATE POLICY "Members can create invites"
  ON circle_invites FOR INSERT
  WITH CHECK (
    auth.uid() = inviter_id
    AND public.is_circle_member(circle_id)
  );

-- Inviter can update their invites (for marking reminders sent)
CREATE POLICY "Inviter can update own invites"
  ON circle_invites FOR UPDATE
  USING (
    auth.uid() = inviter_id
  );

-- Fix 6: Inviter can delete their own pending invites
CREATE POLICY "Inviter can delete own pending invites"
  ON circle_invites FOR DELETE
  USING (
    auth.uid() = inviter_id
    AND accepted_at IS NULL
  );

-- =============================================================================
-- MARK: - Helper Function: Get Active Challenge
-- Returns the active challenge for a circle (if any)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_active_challenge(p_circle_id UUID)
RETURNS TABLE(
  id UUID,
  circle_id UUID,
  created_by UUID,
  challenge_type TEXT,
  title TEXT,
  description TEXT,
  target_exercise_id UUID,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.circle_id,
    c.created_by,
    c.challenge_type,
    c.title,
    c.description,
    c.target_exercise_id,
    c.starts_at,
    c.ends_at,
    c.created_at
  FROM circle_challenges c
  WHERE c.circle_id = p_circle_id
    AND c.starts_at <= NOW()
    AND c.ends_at > NOW()
  ORDER BY c.created_at DESC
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_active_challenge(UUID) TO authenticated;

-- =============================================================================
-- MARK: - Comments
-- =============================================================================

COMMENT ON TABLE circle_hugs IS 'One-tap encouragement between circle members, limited to 5/day per recipient';
COMMENT ON TABLE circle_challenges IS '24-hour challenges created by circle owners for engagement';
COMMENT ON TABLE challenge_completions IS 'Tracks which users completed which challenges';
COMMENT ON TABLE circle_reactions IS 'Emoji reactions on circle posts (🎉👏💪❤️🔥)';
COMMENT ON TABLE circle_invites IS 'Pending invites with email/phone for nudge notifications';
COMMENT ON FUNCTION public.check_hug_limit IS 'Checks if sender can still send hugs to recipient today (limit 5)';
COMMENT ON FUNCTION public.get_active_challenge IS 'Returns the currently active challenge for a circle';
