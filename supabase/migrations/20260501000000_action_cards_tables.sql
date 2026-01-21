-- Create action card templates table
CREATE TABLE IF NOT EXISTS action_card_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_type VARCHAR(50) NOT NULL CHECK (trigger_type IN (
        'breathing', 'meditation', 'grounding', 'journaling',
        'mood_check', 'quest_offer', 'resource', 'chat_suggestion', 'custom'
    )),
    card_title VARCHAR(255) NOT NULL,
    card_description TEXT,
    action_destination VARCHAR(100) NOT NULL CHECK (action_destination IN (
        'exercise', 'journal', 'quest', 'mood', 'resource', 'chat', 'external'
    )),
    action_destination_id VARCHAR(255),
    icon VARCHAR(100),
    estimated_minutes INTEGER CHECK (estimated_minutes >= 1 AND estimated_minutes <= 120),
    priority INTEGER DEFAULT 0 CHECK (priority >= 0 AND priority <= 100),
    is_premium BOOLEAN DEFAULT FALSE,
    conditions JSONB DEFAULT '{}',
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_action_card_templates_trigger_type
    ON action_card_templates(trigger_type) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_action_card_templates_priority
    ON action_card_templates(priority DESC) WHERE active = TRUE;

-- Create chat action cards table
CREATE TABLE IF NOT EXISTS chat_action_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES chat_sessions(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    card_type VARCHAR(50) NOT NULL CHECK (card_type IN (
        'exercise', 'journaling', 'quest', 'mood', 'resource', 'chat'
    )),
    card_data JSONB NOT NULL DEFAULT '{}',
    template_id UUID REFERENCES action_card_templates(id),
    is_dismissed BOOLEAN DEFAULT FALSE,
    dismissal_reason VARCHAR(50),
    dismissed_at TIMESTAMPTZ,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    completion_data JSONB DEFAULT '{}',
    displayed_at TIMESTAMPTZ DEFAULT NOW(),
    action_taken_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_chat_action_cards_session ON chat_action_cards(session_id);
CREATE INDEX IF NOT EXISTS idx_chat_action_cards_message ON chat_action_cards(message_id);
CREATE INDEX IF NOT EXISTS idx_chat_action_cards_displayed ON chat_action_cards(displayed_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_action_cards_active
    ON chat_action_cards(session_id) WHERE is_dismissed = FALSE AND is_completed = FALSE;

-- Create card analytics table
CREATE TABLE IF NOT EXISTS card_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID NOT NULL REFERENCES chat_action_cards(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'impression', 'click', 'dismiss', 'complete', 'conversion'
    )),
    event_data JSONB DEFAULT '{}',
    device_type VARCHAR(20),
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_card_analytics_card ON card_analytics(card_id);
CREATE INDEX IF NOT EXISTS idx_card_analytics_type ON card_analytics(event_type);
CREATE INDEX IF NOT EXISTS idx_card_analytics_created ON card_analytics(created_at DESC);

-- Insert default card templates
INSERT INTO action_card_templates (
    trigger_type, card_title, card_description, action_destination,
    action_destination_id, icon, estimated_minutes, priority, is_premium
) VALUES
    -- Breathing exercises
    ('breathing', 'Take a Deep Breath', 'A calming 4-7-8 breathing exercise', 'exercise', 'breath-4-7-8', 'wind', 3, 90, FALSE),
    ('breathing', 'Box Breathing', 'Equal inhale, hold, exhale, hold', 'exercise', 'breath-box', 'wind', 4, 85, FALSE),

    -- Meditation
    ('meditation', 'Morning Meditation', 'Start your day with mindfulness', 'exercise', 'meditation-morning', 'leaf', 5, 80, FALSE),
    ('meditation', 'Sleep Meditation', 'Wind down for restful sleep', 'exercise', 'meditation-sleep', 'moon', 10, 75, FALSE),
    ('meditation', 'Premium Meditation', 'Unlock deeper calm with this guided session', 'exercise', 'meditation-premium-1', 'crown', 15, 70, TRUE),

    -- Grounding
    ('grounding', '5-4-3-2-1 Grounding', 'Center yourself using your senses', 'exercise', 'grounding-5-4-3-2-1', 'tree', 5, 88, FALSE),
    ('grounding', 'Body Scan', 'Release tension with body awareness', 'exercise', 'grounding-body-scan', 'person', 8, 82, FALSE),

    -- Journaling
    ('journaling', 'Reflect & Write', 'Process your thoughts through journaling', 'journal', NULL, 'pencil.and.scribble', 10, 80, FALSE),
    ('journaling', 'Gratitude Journal', 'Write three things you are grateful for', 'journal', NULL, 'heart', 5, 78, FALSE),
    ('journaling', 'Prompt: What''s on Your Mind?', 'Free write about what''s occupying your thoughts', 'journal', NULL, 'bubble.left.and.bubble.right', 10, 76, FALSE),

    -- Mood
    ('mood_check', 'How Are You Feeling?', 'Take a moment to check in with yourself', 'mood', NULL, 'face.smiling', 1, 95, FALSE),

    -- Quests
    ('quest_offer', 'Daily Quest Available', 'Complete this quest to earn XP and streak points', 'quest', NULL, 'star', 15, 75, FALSE),

    -- Resources
    ('resource', 'Learn More', 'Explore this topic further', 'resource', NULL, 'book', 5, 60, FALSE),
    ('resource', 'Crisis Resources', 'Access support resources', 'resource', 'crisis-resources', 'lifepreserver', 5, 100, FALSE)
ON CONFLICT DO NOTHING;

-- Enable RLS on all tables
ALTER TABLE action_card_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_action_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE card_analytics ENABLE ROW LEVEL SECURITY;

-- RLS policies
CREATE POLICY "Anyone can view active templates" ON action_card_templates
    FOR SELECT USING (active = TRUE);

CREATE POLICY "Users can view own cards" ON chat_action_cards
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM chat_sessions
            WHERE chat_sessions.id = chat_action_cards.session_id
            AND chat_sessions.user_id = auth.uid()
        )
    );

CREATE POLICY "System can insert cards" ON chat_action_cards
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update own cards" ON chat_action_cards
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM chat_sessions
            WHERE chat_sessions.id = chat_action_cards.session_id
            AND chat_sessions.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can view own card analytics" ON card_analytics
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM chat_action_cards
            JOIN chat_sessions ON chat_sessions.id = chat_action_cards.session_id
            WHERE chat_action_cards.id = card_analytics.card_id
            AND chat_sessions.user_id = auth.uid()
        )
    );

CREATE POLICY "System can insert analytics" ON card_analytics
    FOR INSERT WITH CHECK (true);
