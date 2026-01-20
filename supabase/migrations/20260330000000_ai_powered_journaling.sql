-- AI-Powered Journaling Feature
-- Tables: journal_entries, journal_analyses, journal_prompts, journal_settings,
--         journal_streaks, journal_drafts, journal_daily_usage, journal_distortion_feedback
-- Created: 2026-01-19

-- =============================================================================
-- JOURNAL ENTRIES TABLE
-- Stores user journal entries with mood tracking
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    content TEXT NOT NULL,
    word_count INTEGER NOT NULL DEFAULT 0,
    mood_before INTEGER CHECK (mood_before IS NULL OR (mood_before BETWEEN 1 AND 5)),
    mood_after INTEGER CHECK (mood_after IS NULL OR (mood_after BETWEEN 1 AND 5)),
    is_analyzed BOOLEAN NOT NULL DEFAULT false,
    prompt_id UUID,  -- Optional reference to prompt that inspired this entry
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_journal_entries_user ON journal_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_user_created ON journal_entries(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_journal_entries_analyzed ON journal_entries(user_id, is_analyzed);
-- Note: Cannot index on (created_at::date) as timestamptz cast depends on timezone
-- Using created_at DESC index instead for date-based queries

-- =============================================================================
-- JOURNAL ANALYSES TABLE
-- Stores AI-generated insights for journal entries
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_analyses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    emotional_themes JSONB NOT NULL DEFAULT '[]',
    suggested_reframes JSONB NOT NULL DEFAULT '[]',
    patterns_identified JSONB NOT NULL DEFAULT '[]',
    cognitive_distortions JSONB NOT NULL DEFAULT '[]',
    supportive_summary TEXT NOT NULL,
    ai_model TEXT NOT NULL DEFAULT 'grok-4-1-fast-reasoning',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(entry_id)  -- One analysis per entry
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_journal_analyses_user ON journal_analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_journal_analyses_entry ON journal_analyses(entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_analyses_user_created ON journal_analyses(user_id, created_at DESC);

-- =============================================================================
-- JOURNAL PROMPTS TABLE
-- Reference data for writing prompts
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,
    prompt_text TEXT NOT NULL,
    mood_affinity INTEGER[] DEFAULT '{}',  -- Array of mood scores (1-5) this prompt suits
    is_premium BOOLEAN NOT NULL DEFAULT false,
    usage_count INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_prompt_category CHECK (category IN (
        'gratitude', 'reflection', 'growth', 'emotions', 'relationships',
        'self_compassion', 'goals', 'challenges', 'mindfulness', 'creativity'
    ))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_journal_prompts_category ON journal_prompts(category);
CREATE INDEX IF NOT EXISTS idx_journal_prompts_premium ON journal_prompts(is_premium);
CREATE INDEX IF NOT EXISTS idx_journal_prompts_active ON journal_prompts(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_journal_prompts_mood ON journal_prompts USING GIN(mood_affinity);

-- =============================================================================
-- JOURNAL SETTINGS TABLE
-- User preferences for journaling feature
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    daily_reminder_enabled BOOLEAN NOT NULL DEFAULT false,
    reminder_time TIME DEFAULT '20:00',
    preferred_prompt_categories TEXT[] DEFAULT '{}',
    auto_analyze BOOLEAN NOT NULL DEFAULT false,
    show_word_count BOOLEAN NOT NULL DEFAULT true,
    default_mood_tracking BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- JOURNAL STREAKS TABLE
-- Tracks journaling consistency
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_streaks (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    current_streak INTEGER NOT NULL DEFAULT 0,
    longest_streak INTEGER NOT NULL DEFAULT 0,
    last_entry_date DATE,
    streak_started_at DATE,
    total_entries INTEGER NOT NULL DEFAULT 0,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- JOURNAL DRAFTS TABLE
-- Auto-saved drafts (one per user)
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_drafts (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    content TEXT NOT NULL DEFAULT '',
    mood_before INTEGER CHECK (mood_before IS NULL OR (mood_before BETWEEN 1 AND 5)),
    prompt_id UUID,
    last_saved_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- JOURNAL DAILY USAGE TABLE
-- Tracks daily usage for rate limiting
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_daily_usage (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    entries_created INTEGER NOT NULL DEFAULT 0,
    analyses_used INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (user_id, date)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_journal_daily_usage_user_date ON journal_daily_usage(user_id, date DESC);

-- =============================================================================
-- JOURNAL DISTORTION FEEDBACK TABLE
-- Tracks user feedback on AI-detected cognitive distortions
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_distortion_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    analysis_id UUID NOT NULL REFERENCES journal_analyses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    distortion_type TEXT NOT NULL,
    user_action TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_distortion_type CHECK (distortion_type IN (
        'all_or_nothing', 'catastrophizing', 'emotional_reasoning',
        'fortune_telling', 'labeling', 'magnification', 'mind_reading',
        'mental_filter', 'overgeneralization', 'should_statements'
    )),
    CONSTRAINT valid_feedback_action CHECK (user_action IN (
        'helpful', 'not_helpful', 'dismissed'
    ))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_journal_distortion_feedback_analysis ON journal_distortion_feedback(analysis_id);
CREATE INDEX IF NOT EXISTS idx_journal_distortion_feedback_user ON journal_distortion_feedback(user_id);

-- =============================================================================
-- JOURNAL PROMPT HISTORY TABLE
-- Tracks which prompts users have used
-- =============================================================================

CREATE TABLE IF NOT EXISTS journal_prompt_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    prompt_id UUID NOT NULL REFERENCES journal_prompts(id) ON DELETE CASCADE,
    entry_id UUID REFERENCES journal_entries(id) ON DELETE SET NULL,
    used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_date DATE NOT NULL DEFAULT CURRENT_DATE,  -- For uniqueness per day
    UNIQUE(user_id, prompt_id, used_date)  -- One use per prompt per day
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_journal_prompt_history_user ON journal_prompt_history(user_id);
CREATE INDEX IF NOT EXISTS idx_journal_prompt_history_user_recent ON journal_prompt_history(user_id, used_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_daily_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_distortion_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_prompt_history ENABLE ROW LEVEL SECURITY;

-- Journal entries: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_entries' AND policyname = 'Users can read own journal entries'
    ) THEN
        CREATE POLICY "Users can read own journal entries"
            ON journal_entries FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_entries' AND policyname = 'Users can insert own journal entries'
    ) THEN
        CREATE POLICY "Users can insert own journal entries"
            ON journal_entries FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_entries' AND policyname = 'Users can update own journal entries'
    ) THEN
        CREATE POLICY "Users can update own journal entries"
            ON journal_entries FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_entries' AND policyname = 'Users can delete own journal entries'
    ) THEN
        CREATE POLICY "Users can delete own journal entries"
            ON journal_entries FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Journal analyses: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_analyses' AND policyname = 'Users can read own journal analyses'
    ) THEN
        CREATE POLICY "Users can read own journal analyses"
            ON journal_analyses FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_analyses' AND policyname = 'Service role can insert journal analyses'
    ) THEN
        CREATE POLICY "Service role can insert journal analyses"
            ON journal_analyses FOR INSERT
            WITH CHECK (true);  -- Edge function uses service role
    END IF;
END $$;

-- Journal prompts: readable by all authenticated users
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_prompts' AND policyname = 'Journal prompts readable by authenticated users'
    ) THEN
        CREATE POLICY "Journal prompts readable by authenticated users"
            ON journal_prompts FOR SELECT
            USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- Journal settings: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_settings' AND policyname = 'Users can read own journal settings'
    ) THEN
        CREATE POLICY "Users can read own journal settings"
            ON journal_settings FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_settings' AND policyname = 'Users can insert own journal settings'
    ) THEN
        CREATE POLICY "Users can insert own journal settings"
            ON journal_settings FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_settings' AND policyname = 'Users can update own journal settings'
    ) THEN
        CREATE POLICY "Users can update own journal settings"
            ON journal_settings FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Journal streaks: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_streaks' AND policyname = 'Users can read own journal streaks'
    ) THEN
        CREATE POLICY "Users can read own journal streaks"
            ON journal_streaks FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_streaks' AND policyname = 'Users can insert own journal streaks'
    ) THEN
        CREATE POLICY "Users can insert own journal streaks"
            ON journal_streaks FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_streaks' AND policyname = 'Users can update own journal streaks'
    ) THEN
        CREATE POLICY "Users can update own journal streaks"
            ON journal_streaks FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Journal drafts: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_drafts' AND policyname = 'Users can read own journal drafts'
    ) THEN
        CREATE POLICY "Users can read own journal drafts"
            ON journal_drafts FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_drafts' AND policyname = 'Users can insert own journal drafts'
    ) THEN
        CREATE POLICY "Users can insert own journal drafts"
            ON journal_drafts FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_drafts' AND policyname = 'Users can update own journal drafts'
    ) THEN
        CREATE POLICY "Users can update own journal drafts"
            ON journal_drafts FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_drafts' AND policyname = 'Users can delete own journal drafts'
    ) THEN
        CREATE POLICY "Users can delete own journal drafts"
            ON journal_drafts FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Journal daily usage: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_daily_usage' AND policyname = 'Users can read own journal daily usage'
    ) THEN
        CREATE POLICY "Users can read own journal daily usage"
            ON journal_daily_usage FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_daily_usage' AND policyname = 'Users can insert own journal daily usage'
    ) THEN
        CREATE POLICY "Users can insert own journal daily usage"
            ON journal_daily_usage FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_daily_usage' AND policyname = 'Users can update own journal daily usage'
    ) THEN
        CREATE POLICY "Users can update own journal daily usage"
            ON journal_daily_usage FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Journal distortion feedback: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_distortion_feedback' AND policyname = 'Users can read own distortion feedback'
    ) THEN
        CREATE POLICY "Users can read own distortion feedback"
            ON journal_distortion_feedback FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_distortion_feedback' AND policyname = 'Users can insert own distortion feedback'
    ) THEN
        CREATE POLICY "Users can insert own distortion feedback"
            ON journal_distortion_feedback FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Journal prompt history: users can only access their own
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_prompt_history' AND policyname = 'Users can read own prompt history'
    ) THEN
        CREATE POLICY "Users can read own prompt history"
            ON journal_prompt_history FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'journal_prompt_history' AND policyname = 'Users can insert own prompt history'
    ) THEN
        CREATE POLICY "Users can insert own prompt history"
            ON journal_prompt_history FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Function to update journal streak when a new entry is created
CREATE OR REPLACE FUNCTION update_journal_streak()
RETURNS TRIGGER AS $$
DECLARE
    user_tz TEXT;
    user_today DATE;
    last_date DATE;
    curr_streak INTEGER;
    long_streak INTEGER;
    total INTEGER;
BEGIN
    -- Get user's timezone (default to UTC)
    SELECT COALESCE(timezone, 'UTC') INTO user_tz
    FROM journal_streaks
    WHERE user_id = NEW.user_id;

    IF user_tz IS NULL THEN
        user_tz := 'UTC';
    END IF;

    -- Calculate today in user's timezone
    user_today := (NOW() AT TIME ZONE user_tz)::date;

    -- Get current streak data
    SELECT last_entry_date, current_streak, longest_streak, total_entries
    INTO last_date, curr_streak, long_streak, total
    FROM journal_streaks
    WHERE user_id = NEW.user_id;

    -- If no streak record exists, create one
    IF NOT FOUND THEN
        INSERT INTO journal_streaks (user_id, current_streak, longest_streak, last_entry_date, streak_started_at, total_entries, timezone)
        VALUES (NEW.user_id, 1, 1, user_today, user_today, 1, user_tz);
        RETURN NEW;
    END IF;

    -- If already journaled today, just increment total if this is a new entry
    IF last_date = user_today THEN
        UPDATE journal_streaks
        SET total_entries = total + 1,
            updated_at = NOW()
        WHERE user_id = NEW.user_id;
        RETURN NEW;
    END IF;

    -- Check if streak continues (journaled yesterday)
    IF last_date = user_today - 1 THEN
        curr_streak := curr_streak + 1;
    ELSE
        -- Streak broken, start new
        curr_streak := 1;
        UPDATE journal_streaks
        SET streak_started_at = user_today
        WHERE user_id = NEW.user_id;
    END IF;

    -- Update longest streak if needed
    IF curr_streak > long_streak THEN
        long_streak := curr_streak;
    END IF;

    -- Update streak record
    UPDATE journal_streaks
    SET current_streak = curr_streak,
        longest_streak = long_streak,
        last_entry_date = user_today,
        total_entries = total + 1,
        updated_at = NOW()
    WHERE user_id = NEW.user_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for streak updates
DROP TRIGGER IF EXISTS trigger_update_journal_streak ON journal_entries;
CREATE TRIGGER trigger_update_journal_streak
    AFTER INSERT ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_journal_streak();

-- Function to update journal_daily_usage when entry is created
CREATE OR REPLACE FUNCTION update_journal_daily_usage_on_entry()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO journal_daily_usage (user_id, date, entries_created)
    VALUES (NEW.user_id, CURRENT_DATE, 1)
    ON CONFLICT (user_id, date)
    DO UPDATE SET entries_created = journal_daily_usage.entries_created + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for daily usage tracking
DROP TRIGGER IF EXISTS trigger_update_journal_daily_usage ON journal_entries;
CREATE TRIGGER trigger_update_journal_daily_usage
    AFTER INSERT ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION update_journal_daily_usage_on_entry();

-- Function to increment prompt usage count
CREATE OR REPLACE FUNCTION increment_prompt_usage()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE journal_prompts
    SET usage_count = usage_count + 1
    WHERE id = NEW.prompt_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger for prompt usage tracking
DROP TRIGGER IF EXISTS trigger_increment_prompt_usage ON journal_prompt_history;
CREATE TRIGGER trigger_increment_prompt_usage
    AFTER INSERT ON journal_prompt_history
    FOR EACH ROW
    EXECUTE FUNCTION increment_prompt_usage();

-- Function to clear draft after entry is saved
CREATE OR REPLACE FUNCTION clear_journal_draft_on_entry()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM journal_drafts WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create trigger to clear draft
DROP TRIGGER IF EXISTS trigger_clear_journal_draft ON journal_entries;
CREATE TRIGGER trigger_clear_journal_draft
    AFTER INSERT ON journal_entries
    FOR EACH ROW
    EXECUTE FUNCTION clear_journal_draft_on_entry();

-- Function to get suggested prompts based on mood
CREATE OR REPLACE FUNCTION get_journal_prompts_for_mood(
    p_user_id UUID,
    p_mood INTEGER,
    p_limit INTEGER DEFAULT 5
)
RETURNS SETOF journal_prompts AS $$
BEGIN
    RETURN QUERY
    SELECT p.*
    FROM journal_prompts p
    LEFT JOIN journal_prompt_history h ON h.prompt_id = p.id
        AND h.user_id = p_user_id
        AND h.used_at > NOW() - INTERVAL '7 days'
    WHERE p.is_active = true
        AND h.id IS NULL  -- Not used in last 7 days
        AND (p.mood_affinity IS NULL OR p_mood = ANY(p.mood_affinity))
    ORDER BY
        CASE WHEN p_mood = ANY(p.mood_affinity) THEN 0 ELSE 1 END,
        p.usage_count ASC,
        RANDOM()
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- SEED DATA: Journal Prompts
-- =============================================================================

INSERT INTO journal_prompts (category, prompt_text, mood_affinity, is_premium) VALUES
-- Gratitude prompts (good for all moods, especially low)
('gratitude', 'What are three small things that brought you comfort today?', '{1,2,3}', false),
('gratitude', 'Who made a positive difference in your life recently, and how?', '{1,2,3,4,5}', false),
('gratitude', 'What is something you often take for granted that you''re thankful for?', '{3,4,5}', false),
('gratitude', 'Describe a challenge that helped you grow stronger.', '{2,3,4}', false),
('gratitude', 'What ability or skill are you grateful to have?', '{3,4,5}', true),

-- Reflection prompts
('reflection', 'What lesson did today teach you?', '{1,2,3,4,5}', false),
('reflection', 'How have you changed in the past year?', '{3,4,5}', false),
('reflection', 'What would you tell your younger self about this moment in your life?', '{2,3,4}', false),
('reflection', 'What patterns do you notice in your thoughts lately?', '{1,2,3}', true),
('reflection', 'When do you feel most like yourself?', '{3,4,5}', false),

-- Growth prompts
('growth', 'What small step can you take tomorrow toward a goal you care about?', '{2,3,4}', false),
('growth', 'What fear would you like to overcome, and why?', '{1,2,3}', false),
('growth', 'Describe a time you surprised yourself with your own strength.', '{2,3,4,5}', false),
('growth', 'What new habit would make the biggest difference in your life?', '{3,4,5}', true),
('growth', 'How do you want to feel more often, and what might help?', '{1,2,3}', false),

-- Emotions prompts (especially for low moods)
('emotions', 'What emotions are you carrying right now? Where do you feel them in your body?', '{1,2,3}', false),
('emotions', 'If your mood today were weather, what would it be and why?', '{1,2,3,4,5}', false),
('emotions', 'What do you need most right now? How might you give that to yourself?', '{1,2}', false),
('emotions', 'What would help you feel a little lighter today?', '{1,2,3}', false),
('emotions', 'Write a compassionate letter to yourself about what you''re going through.', '{1,2}', true),

-- Relationships prompts
('relationships', 'Who do you want to connect with more, and what''s holding you back?', '{2,3,4}', false),
('relationships', 'Describe a meaningful conversation you had recently.', '{3,4,5}', false),
('relationships', 'What qualities do you value most in your closest relationships?', '{3,4,5}', false),
('relationships', 'How can you show appreciation to someone important to you this week?', '{3,4,5}', true),
('relationships', 'What boundary would help protect your peace?', '{1,2,3}', false),

-- Self-compassion prompts (especially for low moods)
('self_compassion', 'What would you say to a friend going through what you''re experiencing?', '{1,2}', false),
('self_compassion', 'What do you need to forgive yourself for?', '{1,2,3}', false),
('self_compassion', 'List five things you like about yourself.', '{1,2,3}', false),
('self_compassion', 'How can you be gentler with yourself today?', '{1,2}', false),
('self_compassion', 'What criticism do you tell yourself that you wouldn''t say to a loved one?', '{1,2}', true),

-- Mindfulness prompts
('mindfulness', 'Describe this moment using all five senses.', '{1,2,3,4,5}', false),
('mindfulness', 'What are you noticing in your body right now?', '{1,2,3}', false),
('mindfulness', 'What thought keeps coming back today? Observe it without judgment.', '{1,2,3}', false),
('mindfulness', 'What simple pleasure did you experience today?', '{3,4,5}', false),
('mindfulness', 'Take three deep breaths, then write what comes to mind.', '{1,2,3}', true),

-- Goals prompts
('goals', 'What does your ideal day look like?', '{3,4,5}', false),
('goals', 'What would you do if you knew you couldn''t fail?', '{3,4,5}', false),
('goals', 'What progress have you made that you haven''t acknowledged?', '{2,3,4}', false),
('goals', 'What''s one thing you''ve been putting off that you could start today?', '{3,4,5}', true),
('goals', 'How do you want to feel at the end of this week?', '{2,3,4}', false),

-- Challenges prompts (for processing difficulties)
('challenges', 'What''s weighing on you? Write it all out.', '{1,2}', false),
('challenges', 'What''s one thing you can control about this situation?', '{1,2,3}', false),
('challenges', 'What has helped you get through difficult times before?', '{1,2}', false),
('challenges', 'If this challenge were a chapter in your life story, what would you title it?', '{1,2,3}', true),
('challenges', 'What might be possible on the other side of this difficulty?', '{1,2,3}', false),

-- Creativity prompts
('creativity', 'If you could create anything without limitations, what would it be?', '{3,4,5}', false),
('creativity', 'Describe your perfect peaceful place, real or imagined.', '{1,2,3,4,5}', false),
('creativity', 'Write a short story about someone who overcomes your biggest fear.', '{2,3,4}', true),
('creativity', 'What colors represent your current emotional state?', '{1,2,3}', false),
('creativity', 'If your emotions were music, what would they sound like?', '{1,2,3,4,5}', true)

ON CONFLICT DO NOTHING;

-- =============================================================================
-- ENTITLEMENTS CONFIGURATION
-- Add journal analysis quota to entitlements table if it exists
-- =============================================================================

DO $$
BEGIN
    -- Check if entitlements table exists and add journal quota
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'entitlements') THEN
        -- Add journal_analysis_daily_quota if not exists
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'entitlements' AND column_name = 'journal_analysis_daily_quota'
        ) THEN
            ALTER TABLE entitlements ADD COLUMN journal_analysis_daily_quota INTEGER;

            -- Update existing rows: free tier gets 3/day, premium unlimited (NULL = unlimited)
            UPDATE entitlements SET journal_analysis_daily_quota = 3 WHERE tier = 'free';
            UPDATE entitlements SET journal_analysis_daily_quota = NULL WHERE tier IN ('premium', 'premium_annual');
        END IF;
    END IF;
END $$;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE journal_entries IS 'User journal entries with optional mood tracking';
COMMENT ON TABLE journal_analyses IS 'AI-generated insights and cognitive distortion analysis';
COMMENT ON TABLE journal_prompts IS 'Writing prompts categorized by type and mood affinity';
COMMENT ON TABLE journal_settings IS 'User preferences for journaling feature';
COMMENT ON TABLE journal_streaks IS 'Tracks journaling consistency and streaks';
COMMENT ON TABLE journal_drafts IS 'Auto-saved draft entries (one per user)';
COMMENT ON TABLE journal_daily_usage IS 'Daily usage tracking for rate limiting';
COMMENT ON TABLE journal_distortion_feedback IS 'User feedback on AI-detected cognitive distortions';
COMMENT ON TABLE journal_prompt_history IS 'Tracks which prompts users have used';
COMMENT ON FUNCTION update_journal_streak IS 'Updates user streak when a new journal entry is created';
COMMENT ON FUNCTION get_journal_prompts_for_mood IS 'Returns personalized prompts based on mood affinity';

-- =============================================================================
-- RPC FUNCTIONS FOR EDGE FUNCTIONS
-- =============================================================================

-- Function to increment journal analysis usage (called by analyze-journal Edge Function)
CREATE OR REPLACE FUNCTION increment_journal_analysis_usage(
    p_user_id UUID,
    p_date DATE
)
RETURNS TABLE(analyses_today INTEGER, quota_remaining INTEGER) AS $$
DECLARE
    current_count INTEGER;
    user_quota INTEGER;
BEGIN
    -- Get user's quota (NULL means unlimited for premium)
    SELECT e.journal_analysis_daily_quota INTO user_quota
    FROM subscriptions s
    LEFT JOIN entitlements e ON e.tier = s.tier
    WHERE s.user_id = p_user_id;

    -- Default to free tier quota if no subscription found
    IF user_quota IS NULL AND NOT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE user_id = p_user_id AND tier IN ('premium', 'premium_annual')
    ) THEN
        user_quota := 3;
    END IF;

    -- Upsert the daily usage count
    INSERT INTO journal_daily_usage (user_id, date, analyses_requested)
    VALUES (p_user_id, p_date, 1)
    ON CONFLICT (user_id, date)
    DO UPDATE SET analyses_requested = journal_daily_usage.analyses_requested + 1
    RETURNING journal_daily_usage.analyses_requested INTO current_count;

    -- Return the current count and remaining quota
    RETURN QUERY SELECT
        current_count,
        CASE
            WHEN user_quota IS NULL THEN -1  -- Unlimited
            ELSE GREATEST(0, user_quota - current_count)
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION increment_journal_analysis_usage(UUID, DATE) TO authenticated;

COMMENT ON FUNCTION increment_journal_analysis_usage IS 'Atomically increments journal analysis usage count and returns current usage';
