-- Onboarding Buddy System Migration
-- Creates buddy relationships, activity tracking, and encouragement features
-- See: specs/15-onboarding-buddy.md

-- =============================================================================
-- MARK: - Profile Extensions
-- Add referral tracking columns
-- =============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES profiles(id);
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS total_referrals INT NOT NULL DEFAULT 0;

-- Generate referral codes for existing users (8-char alphanumeric)
UPDATE profiles
SET referral_code = UPPER(SUBSTRING(MD5(id::TEXT || EXTRACT(EPOCH FROM NOW())::TEXT) FROM 1 FOR 8))
WHERE referral_code IS NULL;

-- Create index for referral lookups
CREATE INDEX IF NOT EXISTS idx_profiles_referral_code ON profiles(referral_code);
CREATE INDEX IF NOT EXISTS idx_profiles_referred_by ON profiles(referred_by) WHERE referred_by IS NOT NULL;

-- =============================================================================
-- MARK: - Buddy Relationships Table
-- Tracks inviter/invitee pairs, invite codes, status
-- =============================================================================

CREATE TABLE IF NOT EXISTS buddy_relationships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  invitee_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  invite_code TEXT NOT NULL UNIQUE,
  invite_method TEXT CHECK (invite_method IN ('sms', 'email', 'link')),
  invitee_contact TEXT, -- phone or email before they join
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
  invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  buddy_circle_id UUID REFERENCES circles(id),
  inviter_reward_claimed BOOLEAN NOT NULL DEFAULT FALSE,
  invitee_reward_claimed BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '30 days',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_buddy_inviter ON buddy_relationships(inviter_id);
CREATE INDEX idx_buddy_invitee ON buddy_relationships(invitee_id) WHERE invitee_id IS NOT NULL;
CREATE INDEX idx_buddy_code ON buddy_relationships(invite_code);
CREATE INDEX idx_buddy_contact ON buddy_relationships(invitee_contact) WHERE invitee_contact IS NOT NULL;
CREATE INDEX idx_buddy_status ON buddy_relationships(status) WHERE status = 'pending';

ALTER TABLE buddy_relationships ENABLE ROW LEVEL SECURITY;

-- Users can see their own buddy relationships (as inviter or invitee)
CREATE POLICY "Users see own buddy relationships" ON buddy_relationships
  FOR SELECT USING (
    auth.uid() = inviter_id OR auth.uid() = invitee_id
  );

-- Users can create buddy invites
CREATE POLICY "Users can create buddy invites" ON buddy_relationships
  FOR INSERT WITH CHECK (auth.uid() = inviter_id);

-- Users can update their own invites (for declining, etc.)
CREATE POLICY "Users can update own buddy relationships" ON buddy_relationships
  FOR UPDATE USING (
    auth.uid() = inviter_id OR auth.uid() = invitee_id
  );

-- =============================================================================
-- MARK: - Buddy Activity Table
-- Tracks quest completions for streak sharing between buddies
-- =============================================================================

CREATE TABLE IF NOT EXISTS buddy_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buddy_relationship_id UUID NOT NULL REFERENCES buddy_relationships(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL CHECK (activity_type IN ('quest_complete', 'streak_milestone', 'encouragement_sent')),
  activity_date DATE NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_buddy_activity_relationship ON buddy_activity(buddy_relationship_id, activity_date DESC);
CREATE INDEX idx_buddy_activity_user ON buddy_activity(user_id, activity_date DESC);

ALTER TABLE buddy_activity ENABLE ROW LEVEL SECURITY;

-- Users can see activity for their buddy relationships
CREATE POLICY "Users see own buddy activity" ON buddy_activity
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM buddy_relationships br
      WHERE br.id = buddy_activity.buddy_relationship_id
        AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
    )
  );

-- Users can insert their own activity
CREATE POLICY "Users can insert own buddy activity" ON buddy_activity
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM buddy_relationships br
      WHERE br.id = buddy_activity.buddy_relationship_id
        AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
        AND br.status = 'accepted'
    )
  );

-- =============================================================================
-- MARK: - Buddy Encouragements Table
-- Quick messages between buddies
-- =============================================================================

CREATE TABLE IF NOT EXISTS buddy_encouragements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buddy_relationship_id UUID NOT NULL REFERENCES buddy_relationships(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message_type TEXT NOT NULL DEFAULT 'encouragement' CHECK (message_type IN ('encouragement', 'celebration', 'check_in')),
  message TEXT,
  seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_encouragements_recipient ON buddy_encouragements(recipient_id, seen_at NULLS FIRST);
CREATE INDEX idx_encouragements_relationship ON buddy_encouragements(buddy_relationship_id, created_at DESC);

ALTER TABLE buddy_encouragements ENABLE ROW LEVEL SECURITY;

-- Users can send encouragements to their buddies
CREATE POLICY "Users can send encouragements" ON buddy_encouragements
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (
      SELECT 1 FROM buddy_relationships br
      WHERE br.id = buddy_encouragements.buddy_relationship_id
        AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
        AND br.status = 'accepted'
    )
  );

-- Users can see encouragements they sent or received
CREATE POLICY "Users see own encouragements" ON buddy_encouragements
  FOR SELECT USING (
    auth.uid() = sender_id OR auth.uid() = recipient_id
  );

-- Users can update their own received encouragements (mark as seen)
CREATE POLICY "Recipients can mark encouragements seen" ON buddy_encouragements
  FOR UPDATE USING (auth.uid() = recipient_id);

-- =============================================================================
-- MARK: - Accept Buddy Invite Function
-- Handles the full flow when an invited user joins
-- =============================================================================

CREATE OR REPLACE FUNCTION public.accept_buddy_invite(
  p_invite_code TEXT,
  p_user_id UUID
)
RETURNS buddy_relationships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship buddy_relationships;
  v_circle_id UUID;
  v_inviter_name TEXT;
  v_xp_reward INT := 100;
BEGIN
  -- Find and validate invite
  SELECT * INTO v_relationship
  FROM buddy_relationships
  WHERE invite_code = UPPER(p_invite_code)
    AND status = 'pending'
    AND expires_at > NOW()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite code';
  END IF;

  -- Prevent self-buddy
  IF v_relationship.inviter_id = p_user_id THEN
    RAISE EXCEPTION 'Cannot accept your own invite';
  END IF;

  -- Get inviter name for circle
  SELECT display_name INTO v_inviter_name
  FROM profiles
  WHERE id = v_relationship.inviter_id;

  -- Create buddy circle (2-person private circle)
  INSERT INTO circles (name, description, owner_id, max_members, invite_code)
  VALUES (
    'Buddies',
    'Your wellness buddy circle',
    v_relationship.inviter_id,
    2,
    'BUDDY-' || UPPER(SUBSTRING(MD5(v_relationship.id::TEXT) FROM 1 FOR 6))
  )
  RETURNING id INTO v_circle_id;

  -- Add both users as circle members
  INSERT INTO circle_members (circle_id, user_id, role, joined_at)
  VALUES
    (v_circle_id, v_relationship.inviter_id, 'owner', NOW()),
    (v_circle_id, p_user_id, 'member', NOW());

  -- Update buddy relationship
  UPDATE buddy_relationships SET
    invitee_id = p_user_id,
    status = 'accepted',
    accepted_at = NOW(),
    buddy_circle_id = v_circle_id
  WHERE id = v_relationship.id
  RETURNING * INTO v_relationship;

  -- Update invitee profile: link referral and give fresh start bonus
  UPDATE profiles SET
    referred_by = v_relationship.inviter_id,
    current_streak_days = 2  -- Fresh start bonus: Day 2 streak
  WHERE id = p_user_id;

  -- Update inviter profile: increment referral count and add XP
  UPDATE profiles SET
    total_referrals = total_referrals + 1,
    xp_total = COALESCE(xp_total, 0) + v_xp_reward
  WHERE id = v_relationship.inviter_id;

  -- Award "Good Friend" badge to inviter if first referral
  INSERT INTO user_badges (user_id, badge_id)
  SELECT v_relationship.inviter_id, b.id
  FROM badges b
  WHERE b.code = 'good_friend'
  ON CONFLICT (user_id, badge_id) DO NOTHING;

  RETURN v_relationship;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_buddy_invite(TEXT, UUID) TO authenticated;

-- =============================================================================
-- MARK: - Generate Buddy Invite Code Function
-- Creates unique 6-character codes for buddy invites
-- =============================================================================

CREATE OR REPLACE FUNCTION public.generate_buddy_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_code TEXT;
  v_chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_attempts INT := 0;
BEGIN
  LOOP
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || SUBSTR(v_chars, FLOOR(RANDOM() * LENGTH(v_chars))::INT + 1, 1);
    END LOOP;

    -- Check if code already exists
    IF NOT EXISTS (SELECT 1 FROM buddy_relationships WHERE invite_code = v_code) THEN
      RETURN v_code;
    END IF;

    v_attempts := v_attempts + 1;
    IF v_attempts > 10 THEN
      RAISE EXCEPTION 'Failed to generate unique buddy code after 10 attempts';
    END IF;
  END LOOP;
END;
$$;

-- =============================================================================
-- MARK: - Buddy Badges
-- Add buddy-specific badges
-- =============================================================================

INSERT INTO badges (code, title, description, icon_name, category)
VALUES
  ('good_friend', 'Good Friend', 'Invited a buddy who joined', 'person.2.fill', 'social'),
  ('buddy_pair', 'Buddy Pair', 'Maintained a buddy streak for 7 days', 'heart.fill', 'social'),
  ('social_butterfly', 'Social Butterfly', 'Invited 5 friends who joined', 'person.3.fill', 'social')
ON CONFLICT (code) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  icon_name = EXCLUDED.icon_name,
  category = EXCLUDED.category;

-- =============================================================================
-- MARK: - Get Buddy Widget Data Function
-- Returns data for displaying buddy status on home screen
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_buddy_widget_data(p_user_id UUID)
RETURNS TABLE(
  buddy_name TEXT,
  buddy_streak INT,
  buddy_id UUID,
  relationship_id UUID,
  has_completed_today BOOLEAN,
  needs_check_in BOOLEAN,
  last_encouragement_id UUID,
  last_encouragement_type TEXT,
  last_encouragement_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buddy_id UUID;
  v_relationship_id UUID;
  v_buddy_name TEXT;
  v_buddy_streak INT;
  v_has_completed BOOLEAN;
  v_needs_checkin BOOLEAN;
  v_last_enc_id UUID;
  v_last_enc_type TEXT;
  v_last_enc_at TIMESTAMPTZ;
  v_today DATE := CURRENT_DATE;
  v_two_days_ago DATE := CURRENT_DATE - INTERVAL '2 days';
BEGIN
  -- Find first active buddy relationship
  SELECT
    br.id,
    CASE WHEN br.inviter_id = p_user_id THEN br.invitee_id ELSE br.inviter_id END
  INTO v_relationship_id, v_buddy_id
  FROM buddy_relationships br
  WHERE (br.inviter_id = p_user_id OR br.invitee_id = p_user_id)
    AND br.status = 'accepted'
  ORDER BY br.accepted_at DESC
  LIMIT 1;

  IF v_buddy_id IS NULL THEN
    RETURN;
  END IF;

  -- Get buddy profile
  SELECT display_name, COALESCE(current_streak_days, 0)
  INTO v_buddy_name, v_buddy_streak
  FROM profiles
  WHERE id = v_buddy_id;

  -- Check if buddy completed quest today
  SELECT EXISTS (
    SELECT 1 FROM quests
    WHERE user_id = v_buddy_id
      AND local_date = TO_CHAR(v_today, 'YYYY-MM-DD')
      AND status = 'completed'
  ) INTO v_has_completed;

  -- Check if buddy needs check-in (no activity in 2+ days)
  SELECT NOT EXISTS (
    SELECT 1 FROM quests
    WHERE user_id = v_buddy_id
      AND local_date >= TO_CHAR(v_two_days_ago, 'YYYY-MM-DD')
  ) INTO v_needs_checkin;

  -- Get last encouragement
  SELECT id, message_type, created_at
  INTO v_last_enc_id, v_last_enc_type, v_last_enc_at
  FROM buddy_encouragements
  WHERE buddy_relationship_id = v_relationship_id
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN QUERY SELECT
    v_buddy_name,
    v_buddy_streak,
    v_buddy_id,
    v_relationship_id,
    v_has_completed,
    v_needs_checkin,
    v_last_enc_id,
    v_last_enc_type,
    v_last_enc_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_buddy_widget_data(UUID) TO authenticated;

-- =============================================================================
-- MARK: - Check and Award Buddy Pair Badge
-- Trigger to award badge after 7 days of buddy relationship
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_buddy_pair_badge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_relationship buddy_relationships;
  v_days_together INT;
BEGIN
  -- Get relationship details
  SELECT * INTO v_relationship
  FROM buddy_relationships
  WHERE id = NEW.buddy_relationship_id;

  IF NOT FOUND OR v_relationship.status != 'accepted' THEN
    RETURN NEW;
  END IF;

  -- Calculate days together
  v_days_together := EXTRACT(DAY FROM (NOW() - v_relationship.accepted_at));

  -- Award badge if 7+ days together
  IF v_days_together >= 7 THEN
    -- Award to inviter
    INSERT INTO user_badges (user_id, badge_id)
    SELECT v_relationship.inviter_id, b.id
    FROM badges b WHERE b.code = 'buddy_pair'
    ON CONFLICT (user_id, badge_id) DO NOTHING;

    -- Award to invitee
    IF v_relationship.invitee_id IS NOT NULL THEN
      INSERT INTO user_badges (user_id, badge_id)
      SELECT v_relationship.invitee_id, b.id
      FROM badges b WHERE b.code = 'buddy_pair'
      ON CONFLICT (user_id, badge_id) DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER check_buddy_pair_badge_trigger
  AFTER INSERT ON buddy_activity
  FOR EACH ROW
  EXECUTE FUNCTION public.check_buddy_pair_badge();

-- =============================================================================
-- MARK: - Rate Limiting for Buddy Invites
-- Prevent invite spam (max 10 invites per day)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_buddy_invite_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_today_count INT;
BEGIN
  SELECT COUNT(*) INTO v_today_count
  FROM buddy_relationships
  WHERE inviter_id = NEW.inviter_id
    AND DATE(invited_at) = CURRENT_DATE;

  IF v_today_count >= 10 THEN
    RAISE EXCEPTION 'Daily buddy invite limit reached (10 per day)'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER check_buddy_invite_limit_trigger
  BEFORE INSERT ON buddy_relationships
  FOR EACH ROW
  EXECUTE FUNCTION public.check_buddy_invite_limit();

-- =============================================================================
-- MARK: - Comments
-- =============================================================================

COMMENT ON TABLE buddy_relationships IS 'Tracks wellness buddy pairs from onboarding invites';
COMMENT ON TABLE buddy_activity IS 'Tracks daily activity for buddy streak sharing';
COMMENT ON TABLE buddy_encouragements IS 'Quick encouragement messages between buddies';
COMMENT ON FUNCTION public.accept_buddy_invite IS 'Handles accepting a buddy invite: creates circle, links profiles, awards bonuses';
COMMENT ON FUNCTION public.get_buddy_widget_data IS 'Returns buddy status data for home screen widget';
COMMENT ON FUNCTION public.generate_buddy_code IS 'Generates unique 6-character buddy invite codes';
