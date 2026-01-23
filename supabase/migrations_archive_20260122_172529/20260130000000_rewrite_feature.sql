-- Create rewrite types reference table
CREATE TABLE IF NOT EXISTS rewrite_types (
    type_key VARCHAR(50) PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    system_prompt_suffix TEXT NOT NULL,
    icon_name VARCHAR(100) NOT NULL DEFAULT 'text.bubble',
    is_premium BOOLEAN NOT NULL DEFAULT FALSE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create rewrite history table
CREATE TABLE IF NOT EXISTS rewrite_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL,
    message_id UUID NOT NULL,
    original_message TEXT NOT NULL,
    rewrite_type VARCHAR(50) NOT NULL REFERENCES rewrite_types(type_key),
    rewritten_message TEXT,
    was_applied BOOLEAN NOT NULL DEFAULT FALSE,
    feedback_rating SMALLINT CHECK (feedback_rating IS NULL OR (feedback_rating >= 1 AND feedback_rating <= 5)),
    feedback_comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    applied_at TIMESTAMPTZ
);

-- Create indexes for rewrite_history
CREATE INDEX IF NOT EXISTS idx_rewrite_history_user_id ON rewrite_history(user_id);
CREATE INDEX IF NOT EXISTS idx_rewrite_history_created_at ON rewrite_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rewrite_history_conversation_id ON rewrite_history(conversation_id);

-- Create rewrite quota tracking table
CREATE TABLE IF NOT EXISTS rewrite_quota (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    daily_count INTEGER NOT NULL DEFAULT 0,
    last_reset_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed rewrite types
INSERT INTO rewrite_types (type_key, display_name, description, system_prompt_suffix, icon_name, is_premium, display_order) VALUES
    ('less_catastrophic', 'Less Catastrophic', 'See situations more proportionally without worst-case thinking',
     'Rewrite to reduce catastrophizing language, extreme words, and worst-case scenarios while keeping the core message. Focus on proportion and reality-testing.',
     'exclamationmark.triangle', FALSE, 1),
    ('more_balanced', 'More Balanced', 'Consider both positive and negative aspects',
     'Rewrite to balance negative thoughts with realistic positive or neutral perspectives. Include what is going well or what could be neutral.',
     'scale.3d', FALSE, 2),
    ('more_actionable', 'More Actionable', 'Focus on steps you can take',
     'Rewrite to emphasize agency, choices, and concrete actions the user can take. Frame as opportunities rather than obligations.',
     'figure.walk', TRUE, 3),
    ('more_compassionate', 'More Self-Compassionate', 'Be kind to yourself about this',
     'Rewrite with self-kindness language, reducing self-criticism. Add gentle, supportive tone. Acknowledge difficulty while offering understanding.',
     'heart', TRUE, 4)
ON CONFLICT (type_key) DO NOTHING;

-- Enable RLS
ALTER TABLE rewrite_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE rewrite_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE rewrite_quota ENABLE ROW LEVEL SECURITY;

-- RLS policies for rewrite_types
CREATE POLICY "Anyone can read rewrite types" ON rewrite_types FOR SELECT USING (true);

-- RLS policies for rewrite_history
CREATE POLICY "Users can read own rewrite history" ON rewrite_history FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own rewrite history" ON rewrite_history FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own rewrite history" ON rewrite_history FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- RLS policies for rewrite_quota
CREATE POLICY "Users can read own quota" ON rewrite_quota FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own quota" ON rewrite_quota FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can insert own quota" ON rewrite_quota FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Create atomic quota check function with advisory lock
CREATE OR REPLACE FUNCTION check_and_increment_rewrite_quota(
  p_user_id UUID,
  max_daily INTEGER DEFAULT 5
)
RETURNS BOOLEAN AS $$
DECLARE
  v_daily_count INTEGER;
  v_result BOOLEAN;
BEGIN
  -- Use advisory lock to prevent race conditions
  IF pg_try_advisory_xact_lock(hashtext(p_user_id::text)) THEN
    SELECT daily_count INTO v_daily_count
    FROM rewrite_quota
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
      -- First rewrite of the day - insert new record
      INSERT INTO rewrite_quota (user_id, daily_count, last_reset_at, updated_at)
      VALUES (p_user_id, 1, NOW(), NOW());
      RETURN TRUE;
    END IF;

    -- Check if we need to reset (new day)
    IF v_daily_count < max_daily THEN
      UPDATE rewrite_quota
      SET daily_count = v_daily_count + 1,
          updated_at = NOW()
      WHERE user_id = p_user_id;
      RETURN TRUE;
    ELSE
      -- Quota exceeded
      RETURN FALSE;
    END IF;
  ELSE
    -- Could not acquire lock
    RETURN FALSE;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add columns to messages table for rewrite tracking
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_rewritten BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS rewritten_from_message_id UUID;
