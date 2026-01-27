-- Progressive Disclosure: Activation Tracking
-- This migration adds columns to track user activation (magic moment)
-- and control which features are unlocked for each user.

-- Activation tracking columns
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS activation_completed_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS first_quest_completed_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS first_mood_logged_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS first_chat_message_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS unlocked_features TEXT[] DEFAULT ARRAY['home', 'chat', 'profile'];

-- Create index for activation queries
CREATE INDEX IF NOT EXISTS idx_profiles_activation ON profiles (activation_completed_at) WHERE activation_completed_at IS NOT NULL;

-- Function to record first quest completion
-- SECURITY: Uses auth.uid() directly to prevent IDOR attacks
CREATE OR REPLACE FUNCTION record_first_quest_completion(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot modify another user''s activation state';
  END IF;

  UPDATE profiles
  SET first_quest_completed_at = COALESCE(first_quest_completed_at, NOW())
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Function to record first mood log
-- SECURITY: Uses auth.uid() directly to prevent IDOR attacks
CREATE OR REPLACE FUNCTION record_first_mood_log(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot modify another user''s activation state';
  END IF;

  UPDATE profiles
  SET first_mood_logged_at = COALESCE(first_mood_logged_at, NOW())
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Function to record first chat message
-- SECURITY: Uses auth.uid() directly to prevent IDOR attacks
CREATE OR REPLACE FUNCTION record_first_chat_message(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot modify another user''s activation state';
  END IF;

  UPDATE profiles
  SET first_chat_message_at = COALESCE(first_chat_message_at, NOW())
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Function to check and complete activation
-- Magic moment: (quest OR mood) AND chat
-- SECURITY: Uses auth.uid() validation to prevent IDOR attacks
CREATE OR REPLACE FUNCTION check_activation_status(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_profile RECORD;
BEGIN
  -- Authorization check: caller must own this profile
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: cannot read another user''s activation state';
  END IF;

  SELECT
    activation_completed_at,
    first_quest_completed_at,
    first_mood_logged_at,
    first_chat_message_at,
    unlocked_features
  INTO v_profile
  FROM profiles
  WHERE id = p_user_id;

  -- Check if profile exists using NOT FOUND (more idiomatic than IS NULL)
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found for user %', p_user_id;
  END IF;

  -- Already activated
  IF v_profile.activation_completed_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'activated', TRUE,
      'already_activated', TRUE,
      'unlocked_features', v_profile.unlocked_features
    );
  END IF;

  -- Check magic moment: (quest OR mood) AND chat
  IF (v_profile.first_quest_completed_at IS NOT NULL OR v_profile.first_mood_logged_at IS NOT NULL)
     AND v_profile.first_chat_message_at IS NOT NULL THEN
    -- Complete activation
    UPDATE profiles SET
      activation_completed_at = NOW(),
      unlocked_features = ARRAY['home', 'chat', 'profile', 'programs', 'outcomes']
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
      'activated', TRUE,
      'just_activated', TRUE,
      'unlocked_features', ARRAY['home', 'chat', 'profile', 'programs', 'outcomes']
    );
  END IF;

  -- Not yet activated
  RETURN jsonb_build_object(
    'activated', FALSE,
    'has_quest', v_profile.first_quest_completed_at IS NOT NULL,
    'has_mood', v_profile.first_mood_logged_at IS NOT NULL,
    'has_chat', v_profile.first_chat_message_at IS NOT NULL,
    'unlocked_features', v_profile.unlocked_features
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION record_first_quest_completion(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION record_first_mood_log(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION record_first_chat_message(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION check_activation_status(UUID) TO authenticated;

-- Set existing users who have activity as activated (backfill)
-- Magic moment: (quest OR mood) AND chat
-- Users with (completed quest OR mood log) AND chat message are considered activated
UPDATE profiles p
SET
  activation_completed_at = COALESCE(p.activation_completed_at, NOW()),
  unlocked_features = ARRAY['home', 'chat', 'profile', 'programs', 'outcomes']
WHERE p.activation_completed_at IS NULL
  AND (
    EXISTS (SELECT 1 FROM quests q WHERE q.user_id = p.id AND q.completed_at IS NOT NULL)
    OR EXISTS (SELECT 1 FROM moods m WHERE m.user_id = p.id)
  )
  AND EXISTS (SELECT 1 FROM messages msg JOIN conversations c ON msg.conversation_id = c.id WHERE c.user_id = p.id AND msg.role = 'user');
