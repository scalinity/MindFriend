-- MindFriend Initial Schema
-- Creates all tables for the MVP

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- MARK: - Profiles (extends auth.users)

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
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- MARK: - User Settings

CREATE TABLE IF NOT EXISTS user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  daily_quest_time_local TEXT NOT NULL DEFAULT '09:00',
  quiet_hours_start_local TEXT,
  quiet_hours_end_local TEXT,
  reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  nudge_after_days_inactive INT NOT NULL DEFAULT 3,
  share_mood_in_circles BOOLEAN NOT NULL DEFAULT true,
  ai_tone TEXT NOT NULL DEFAULT 'friendly' CHECK (ai_tone IN ('friendly', 'professional', 'motivational', 'gentle')),
  privacy_mode TEXT NOT NULL DEFAULT 'standard' CHECK (privacy_mode IN ('standard', 'enhanced')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own settings" ON user_settings
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own settings" ON user_settings
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own settings" ON user_settings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- MARK: - Quest Templates

CREATE TABLE IF NOT EXISTS quest_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('breathing', 'walk', 'journal', 'focus', 'gratitude', 'stretch')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  estimated_minutes INT NOT NULL,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  tags TEXT[] NOT NULL DEFAULT '{}',
  instructions JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE quest_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view quest templates" ON quest_templates
  FOR SELECT TO authenticated USING (true);

-- MARK: - Quests

CREATE TABLE IF NOT EXISTS quests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  template_id UUID NOT NULL REFERENCES quest_templates(id),
  local_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'completed', 'skipped')),
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_quests_user_date ON quests(user_id, local_date);

ALTER TABLE quests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own quests" ON quests
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own quests" ON quests
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own quests" ON quests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- MARK: - Moods

CREATE TABLE IF NOT EXISTS moods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_date TEXT NOT NULL,
  mood_score INT NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
  anxiety_score INT CHECK (anxiety_score BETWEEN 1 AND 5),
  energy_score INT CHECK (energy_score BETWEEN 1 AND 5),
  note TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'post_quest', 'post_exercise')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_moods_user_date ON moods(user_id, local_date DESC);

ALTER TABLE moods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own moods" ON moods
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own moods" ON moods
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own moods" ON moods
  FOR UPDATE USING (auth.uid() = user_id);

-- MARK: - Conversations

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id, updated_at DESC);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Note: Conversation RLS policies are added in chat_security_hardening migration

-- MARK: - Messages

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  blocked BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at ASC);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Note: Message RLS policies are added in chat_security_hardening migration

-- MARK: - Circles

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

-- MARK: - Circle Members

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

-- Basic circle_members policies (SELECT policy enhanced in fix_circle_members_rls_recursion migration)
CREATE POLICY "Users can insert own membership" ON circle_members
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own membership" ON circle_members
  FOR DELETE USING (auth.uid() = user_id);

-- Note: circles SELECT policy is created in fix_circle_members_rls_recursion migration to avoid recursion

-- MARK: - Circle Posts

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

-- MARK: - Exercises

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

CREATE POLICY "Anyone can view exercises" ON exercises
  FOR SELECT TO authenticated USING (true);

-- MARK: - Exercise Sessions

CREATE TABLE IF NOT EXISTS exercise_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  exercise_id UUID NOT NULL REFERENCES exercises(id),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  completed BOOLEAN NOT NULL DEFAULT false,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user ON exercise_sessions(user_id, created_at DESC);

ALTER TABLE exercise_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own sessions" ON exercise_sessions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sessions" ON exercise_sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sessions" ON exercise_sessions
  FOR UPDATE USING (auth.uid() = user_id);

-- MARK: - Badges

CREATE TABLE IF NOT EXISTS badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  icon_name TEXT,
  category TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view badges" ON badges
  FOR SELECT TO authenticated USING (true);

-- MARK: - User Badges

CREATE TABLE IF NOT EXISTS user_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id UUID NOT NULL REFERENCES badges(id),
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, badge_id)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);

ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own badges" ON user_badges
  FOR SELECT USING (auth.uid() = user_id);

-- MARK: - Subscriptions

CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'cancelled', 'grace_period')),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own subscription" ON subscriptions
  FOR SELECT USING (auth.uid() = user_id);

-- MARK: - Crisis Events (for safety monitoring)

CREATE TABLE IF NOT EXISTS crisis_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  trigger_content TEXT,
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_crisis_events_user ON crisis_events(user_id, detected_at DESC);

ALTER TABLE crisis_events ENABLE ROW LEVEL SECURITY;

-- Note: Crisis events RLS policies are added in chat_security_hardening migration

-- MARK: - User Stats (denormalized for performance)

CREATE TABLE IF NOT EXISTS user_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  current_streak_days INT NOT NULL DEFAULT 0,
  longest_streak_days INT NOT NULL DEFAULT 0,
  total_quests_completed INT NOT NULL DEFAULT 0,
  total_exercises_completed INT NOT NULL DEFAULT 0,
  last_quest_date TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own stats" ON user_stats
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own stats" ON user_stats
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own stats" ON user_stats
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- MARK: - Push Notification Tokens

CREATE TABLE IF NOT EXISTS push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, token)
);

ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own tokens" ON push_tokens
  FOR ALL USING (auth.uid() = user_id);

-- MARK: - Helper Functions

-- Function to create profile and settings on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  random_handle TEXT;
BEGIN
  -- Generate random handle
  random_handle := 'user_' || substr(md5(random()::text), 1, 8);

  -- Create profile
  INSERT INTO public.profiles (id, handle, display_name, email)
  VALUES (
    NEW.id,
    random_handle,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'MindFriend User'),
    NEW.email
  );

  -- Create settings
  INSERT INTO public.user_settings (user_id)
  VALUES (NEW.id);

  -- Create stats
  INSERT INTO public.user_stats (user_id)
  VALUES (NEW.id);

  RETURN NEW;
END;
$$;

-- Trigger for new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- MARK: - Seed Data: Badges

INSERT INTO badges (code, title, description, icon_name, category) VALUES
  -- Getting Started
  ('first_steps', 'First Steps', 'Complete your first quest', 'star.fill', 'getting_started'),
  ('opening_up', 'Opening Up', 'Have your first AI chat', 'bubble.left.fill', 'getting_started'),
  ('mood_tracker', 'Mood Tracker', 'Log your first mood', 'chart.bar.fill', 'getting_started'),
  ('moving_forward', 'Moving Forward', 'Complete your first exercise', 'figure.walk', 'getting_started'),
  ('all_set', 'All Set', 'Complete your profile', 'person.crop.circle.badge.checkmark', 'getting_started'),

  -- Quest Milestones
  ('consistent', 'Consistent', 'Complete 10 quests', 'checkmark.circle.fill', 'quest_milestones'),
  ('committed', 'Committed', 'Complete 25 quests', 'checkmark.seal.fill', 'quest_milestones'),
  ('mindful_master', 'Mindful Master', 'Complete 50 quests', 'brain.head.profile', 'quest_milestones'),
  ('century_seeker', 'Century Seeker', 'Complete 100 quests', 'star.circle.fill', 'quest_milestones'),
  ('wellness_warrior', 'Wellness Warrior', 'Complete 250 quests', 'shield.fill', 'quest_milestones'),
  ('enlightened', 'Enlightened', 'Complete 500 quests', 'sun.max.fill', 'quest_milestones'),

  -- Streak Achievements
  ('streak_3', 'On a Roll', '3-day streak', 'flame', 'streak'),
  ('week_warrior', 'Week Warrior', '7-day streak', 'flame.fill', 'streak'),
  ('fortnight_focus', 'Fortnight Focus', '14-day streak', 'flame.circle', 'streak'),
  ('monthly_master', 'Monthly Master', '30-day streak', 'calendar', 'streak'),
  ('two_month_titan', 'Two Month Titan', '60-day streak', 'calendar.badge.clock', 'streak'),
  ('century_club', 'Century Club', '100-day streak', 'trophy.fill', 'streak'),
  ('year_of_growth', 'Year of Growth', '365-day streak', 'crown.fill', 'streak'),

  -- Exercise Achievements
  ('exercise_explorer', 'Exercise Explorer', 'Complete 5 exercises', 'figure.walk', 'exercise'),
  ('active_mind', 'Active Mind', 'Complete 25 exercises', 'figure.mind.and.body', 'exercise'),
  ('body_and_soul', 'Body and Soul', 'Complete 50 exercises', 'heart.circle.fill', 'exercise'),
  ('wellness_champion', 'Wellness Champion', 'Complete 100 exercises', 'medal.fill', 'exercise'),
  ('well_rounded', 'Well-Rounded', 'Try all exercise types', 'circle.grid.3x3.fill', 'exercise'),

  -- Social
  ('circle_joiner', 'Circle Joiner', 'Join your first circle', 'person.2.fill', 'social'),
  ('circle_creator', 'Circle Creator', 'Create a circle', 'person.3.fill', 'social'),
  ('community_spirit', 'Community Spirit', 'Post 10 check-ins', 'hand.wave.fill', 'social'),
  ('spreading_wellness', 'Spreading Wellness', 'Invite a friend', 'gift.fill', 'social'),

  -- Special
  ('night_owl', 'Night Owl', 'Complete a quest after 10 PM', 'moon.fill', 'special'),
  ('early_bird', 'Early Bird', 'Complete a quest before 6 AM', 'sunrise.fill', 'special'),
  ('perfect_week', 'Perfect Week', 'Complete all quests for 7 days', 'sparkles', 'special'),
  ('mood_master', 'Mood Master', 'Log mood for 7 consecutive days', 'chart.line.uptrend.xyaxis', 'special'),
  ('comeback', 'Comeback', 'Return after 7+ days away', 'arrow.counterclockwise', 'special')
ON CONFLICT (code) DO NOTHING;

-- MARK: - Seed Data: Quest Templates

INSERT INTO quest_templates (type, title, description, estimated_minutes, difficulty, tags, instructions) VALUES
  ('breathing', 'Box Breathing', 'A calming 4-4-4-4 breathing exercise used by Navy SEALs', 5, 'easy', ARRAY['stress', 'anxiety', 'focus'],
   '[{"step": 1, "text": "Find a comfortable seated position", "durationSeconds": 10}, {"step": 2, "text": "Inhale slowly for 4 seconds", "durationSeconds": 4}, {"step": 3, "text": "Hold your breath for 4 seconds", "durationSeconds": 4}, {"step": 4, "text": "Exhale slowly for 4 seconds", "durationSeconds": 4}, {"step": 5, "text": "Hold empty for 4 seconds", "durationSeconds": 4}, {"step": 6, "text": "Repeat 5 times", "durationSeconds": 80}]'),

  ('walk', 'Mindful Walk', 'A short walk focusing on your surroundings', 10, 'easy', ARRAY['movement', 'mindfulness', 'nature'],
   '[{"step": 1, "text": "Step outside or find a safe walking path", "durationSeconds": 30}, {"step": 2, "text": "Walk slowly, noticing your feet touching the ground", "durationSeconds": 180}, {"step": 3, "text": "Notice 5 things you can see around you", "durationSeconds": 120}, {"step": 4, "text": "Notice 3 sounds you can hear", "durationSeconds": 90}, {"step": 5, "text": "Take a deep breath and return", "durationSeconds": 30}]'),

  ('journal', 'Gratitude List', 'Write down three things you are grateful for today', 5, 'easy', ARRAY['gratitude', 'reflection', 'positivity'],
   '[{"step": 1, "text": "Find a quiet moment", "durationSeconds": 20}, {"step": 2, "text": "Think about your day so far", "durationSeconds": 30}, {"step": 3, "text": "Write three things you are grateful for", "durationSeconds": 180}, {"step": 4, "text": "For each, write why it matters to you", "durationSeconds": 60}]'),

  ('focus', 'Single-Task Focus', 'Practice focusing on one task without distractions', 15, 'medium', ARRAY['productivity', 'focus', 'mindfulness'],
   '[{"step": 1, "text": "Choose one task to focus on", "durationSeconds": 30}, {"step": 2, "text": "Put away your phone and close other tabs", "durationSeconds": 30}, {"step": 3, "text": "Set a timer for 15 minutes", "durationSeconds": 10}, {"step": 4, "text": "Work on only this task until the timer ends", "durationSeconds": 840}, {"step": 5, "text": "Notice how it felt to focus deeply", "durationSeconds": 30}]'),

  ('gratitude', 'Appreciation Message', 'Send a message of appreciation to someone', 5, 'easy', ARRAY['gratitude', 'connection', 'kindness'],
   '[{"step": 1, "text": "Think of someone who has helped you recently", "durationSeconds": 60}, {"step": 2, "text": "Write a short message thanking them", "durationSeconds": 180}, {"step": 3, "text": "Send the message", "durationSeconds": 30}]'),

  ('stretch', 'Morning Stretch', 'A gentle stretching routine to start your day', 7, 'easy', ARRAY['movement', 'flexibility', 'morning'],
   '[{"step": 1, "text": "Stand tall and reach arms overhead", "durationSeconds": 30}, {"step": 2, "text": "Slowly roll down to touch your toes", "durationSeconds": 30}, {"step": 3, "text": "Hold for 20 seconds, breathing deeply", "durationSeconds": 20}, {"step": 4, "text": "Roll up slowly, one vertebra at a time", "durationSeconds": 20}, {"step": 5, "text": "Reach arms wide and twist gently left", "durationSeconds": 30}, {"step": 6, "text": "Twist gently right", "durationSeconds": 30}, {"step": 7, "text": "Roll shoulders back 5 times", "durationSeconds": 30}, {"step": 8, "text": "Roll shoulders forward 5 times", "durationSeconds": 30}, {"step": 9, "text": "Finish with 3 deep breaths", "durationSeconds": 30}]')
ON CONFLICT DO NOTHING;

-- MARK: - Seed Data: Exercises

INSERT INTO exercises (type, title, description, duration_seconds, content_kind, content_text, premium_only) VALUES
  -- Breathing exercises
  ('breathing', '4-7-8 Relaxing Breath', 'A calming breathing technique to reduce anxiety and promote sleep', 180, 'guided', 'Inhale through your nose for 4 counts. Hold your breath for 7 counts. Exhale completely through your mouth for 8 counts. Repeat 4 times.', false),
  ('breathing', 'Energizing Breath', 'Quick breathing to increase alertness and energy', 120, 'guided', 'Take 30 quick, powerful breaths through your nose. After the last exhale, hold your breath as long as comfortable. Inhale deeply and hold for 15 seconds. Repeat 3 rounds.', false),
  ('breathing', 'Calm Body Scan', 'Combine breathing with body awareness for deep relaxation', 300, 'guided', 'Breathe slowly while mentally scanning from your toes to your head. Notice any tension and breathe into those areas.', true),

  -- Meditation exercises
  ('meditation', 'Loving Kindness', 'Cultivate compassion for yourself and others', 300, 'guided', 'Start by directing kind wishes to yourself: "May I be happy, may I be healthy, may I be safe." Then extend these wishes to loved ones, acquaintances, and eventually all beings.', false),
  ('meditation', 'Body Scan Meditation', 'A progressive relaxation through body awareness', 600, 'guided', 'Lie down comfortably. Starting from your toes, bring attention to each body part, noticing sensations without judgment. Gradually move up through your body to the crown of your head.', false),
  ('meditation', 'Breath Awareness', 'Simple meditation focusing on natural breathing', 300, 'guided', 'Sit comfortably and close your eyes. Notice your natural breath without changing it. When thoughts arise, gently return focus to breathing.', false),
  ('meditation', 'Visualization Journey', 'A guided imagery meditation for peace', 480, 'guided', 'Imagine yourself in a peaceful natural setting. Engage all senses - see the colors, hear the sounds, feel the temperature. Let this place fill you with calm.', true),
  ('meditation', 'Mindful Awareness', 'Present-moment awareness meditation', 420, 'guided', 'Notice your thoughts like clouds passing in the sky. Do not engage or judge them. Simply observe and let them pass.', true),

  -- Grounding exercises
  ('grounding', '5-4-3-2-1 Senses', 'Ground yourself using your five senses', 180, 'text', 'Name 5 things you can see, 4 things you can touch, 3 things you can hear, 2 things you can smell, and 1 thing you can taste.', false),
  ('grounding', 'Cold Water Reset', 'Use cold water to reset your nervous system', 60, 'text', 'Run cold water over your wrists for 30 seconds. Notice the sensation fully. This activates your dive reflex and calms your nervous system.', false),
  ('grounding', 'Feet on Ground', 'Connect with the earth beneath you', 120, 'text', 'Remove your shoes if possible. Feel the ground beneath your feet. Notice the texture, temperature, and support of the earth.', false),
  ('grounding', 'Object Focus', 'Ground through detailed object observation', 180, 'text', 'Pick up an object near you. Examine it closely - its weight, texture, color, temperature. Describe it in detail as if explaining to someone who has never seen it.', true),

  -- Journaling exercises
  ('journaling', 'Morning Pages', 'Free-write your thoughts to clear your mind', 600, 'text', 'Write continuously for 10 minutes without stopping. Do not worry about grammar or making sense. Let your thoughts flow onto the page.', false),
  ('journaling', 'Worry Dump', 'Get anxious thoughts out of your head', 300, 'text', 'Write down everything worrying you right now. Do not solve the problems - just list them. Getting them on paper takes away their power.', false),
  ('journaling', 'Success Log', 'Document your daily wins, big and small', 300, 'text', 'Write down 3 things you accomplished today, no matter how small. Acknowledge your effort and progress.', false),
  ('journaling', 'Letter to Self', 'Write encouragement to yourself', 420, 'text', 'Write a compassionate letter to yourself as you would to a dear friend going through the same situation.', true),
  ('journaling', 'Future Vision', 'Visualize and write about your ideal future', 480, 'text', 'Describe your life one year from now as if everything went perfectly. Be specific about what you see, feel, and have accomplished.', true),

  -- Movement exercises
  ('movement', 'Desk Stretches', 'Quick stretches you can do at your desk', 180, 'text', 'Neck rolls, shoulder shrugs, wrist circles, and seated spinal twist. Perfect for work breaks.', false),
  ('movement', 'Stress Shake-Off', 'Shake out tension from your body', 120, 'text', 'Stand and shake your hands vigorously. Then shake your arms, legs, and whole body. Let the movement be spontaneous and release tension.', false),
  ('movement', 'Walking Meditation', 'Combine gentle walking with mindfulness', 600, 'text', 'Walk slowly and deliberately. Feel each step - heel, ball, toe. Match your breath to your steps. Be fully present in the movement.', false),
  ('movement', 'Progressive Muscle Relaxation', 'Tense and release muscle groups', 480, 'guided', 'Systematically tense each muscle group for 5 seconds, then release. Start with feet and work up to face. Notice the contrast between tension and relaxation.', true),
  ('movement', 'Energy Flow', 'Gentle movements to increase energy', 300, 'guided', 'Flowing arm circles, gentle twists, and reaching movements to wake up your body and increase circulation.', true)
ON CONFLICT DO NOTHING;
