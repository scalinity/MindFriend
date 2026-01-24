-- Wellness Time Capsule Feature
-- Enables users to create encrypted messages for their future selves

-- ============================================================================
-- TABLES
-- ============================================================================

-- Time capsules (main table)
CREATE TABLE IF NOT EXISTS time_capsules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Content
    title TEXT,
    content_encrypted TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN ('text', 'audio', 'photo', 'mixed')),
    theme TEXT CHECK (theme IN ('milestone', 'goal', 'gratitude', 'advice', 'encouragement', 'anniversary', 'custom')),

    -- Scheduling
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deliver_at TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,

    -- Status
    status TEXT NOT NULL DEFAULT 'sealed' CHECK (status IN ('sealed', 'delivered', 'opened')),

    -- AI Commentary
    companion_letter TEXT,
    companion_letter_generated_at TIMESTAMPTZ,

    -- Metadata
    word_count INTEGER,
    media_count INTEGER DEFAULT 0,
    encryption_key_id TEXT NOT NULL,

    -- Soft delete
    deleted_at TIMESTAMPTZ,

    -- Validation
    CONSTRAINT valid_delivery_date CHECK (deliver_at > created_at),
    CONSTRAINT valid_status_transition CHECK (
        (status = 'sealed' AND delivered_at IS NULL AND opened_at IS NULL) OR
        (status = 'delivered' AND delivered_at IS NOT NULL AND opened_at IS NULL) OR
        (status = 'opened' AND delivered_at IS NOT NULL AND opened_at IS NOT NULL)
    )
);

-- Media attachments (audio, photos, video)
CREATE TABLE IF NOT EXISTS capsule_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id UUID NOT NULL REFERENCES time_capsules(id) ON DELETE CASCADE,
    media_type TEXT NOT NULL CHECK (media_type IN ('audio', 'photo', 'video')),
    storage_path TEXT NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    duration_seconds INTEGER, -- For audio/video
    transcription TEXT, -- For audio (searchable)
    thumbnail_path TEXT, -- For video/photo
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT valid_duration CHECK (
        (media_type IN ('audio', 'video') AND duration_seconds > 0) OR
        (media_type = 'photo' AND duration_seconds IS NULL)
    )
);

-- Prompt templates for guided creation
CREATE TABLE IF NOT EXISTS capsule_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme TEXT NOT NULL,
    title TEXT NOT NULL,
    prompts JSONB NOT NULL, -- Array of prompt strings
    suggested_duration TEXT, -- e.g., "6 months", "1 year"
    is_premium BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Wellness snapshot at capsule creation
CREATE TABLE IF NOT EXISTS capsule_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id UUID NOT NULL REFERENCES time_capsules(id) ON DELETE CASCADE,

    -- User stats at creation time
    current_streak INTEGER NOT NULL DEFAULT 0,
    total_quests_completed INTEGER NOT NULL DEFAULT 0,
    total_exercises INTEGER NOT NULL DEFAULT 0,
    total_moods_logged INTEGER NOT NULL DEFAULT 0,
    average_mood_30d DECIMAL(3,2),
    badges_earned INTEGER NOT NULL DEFAULT 0,
    level INTEGER NOT NULL DEFAULT 1,
    total_xp INTEGER NOT NULL DEFAULT 0,
    top_emotions TEXT[], -- Most common in past 30 days

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(capsule_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_time_capsules_user ON time_capsules(user_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_time_capsules_deliver ON time_capsules(deliver_at) WHERE status = 'sealed' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_time_capsules_status ON time_capsules(user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_capsule_media_capsule ON capsule_media(capsule_id);
CREATE INDEX IF NOT EXISTS idx_capsule_snapshots_capsule ON capsule_snapshots(capsule_id);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE time_capsules ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsule_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsule_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsule_snapshots ENABLE ROW LEVEL SECURITY;

-- time_capsules policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'time_capsules' AND policyname = 'Users can read own capsules'
    ) THEN
        CREATE POLICY "Users can read own capsules" ON time_capsules
            FOR SELECT USING (auth.uid() = user_id AND deleted_at IS NULL);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'time_capsules' AND policyname = 'Service role can insert capsules'
    ) THEN
        CREATE POLICY "Service role can insert capsules" ON time_capsules
            FOR INSERT WITH CHECK (auth.role() = 'service_role');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'time_capsules' AND policyname = 'Users can update own unopened capsules'
    ) THEN
        CREATE POLICY "Users can update own unopened capsules" ON time_capsules
            FOR UPDATE USING (
                auth.uid() = user_id AND status IN ('sealed', 'delivered') AND deleted_at IS NULL
            )
            WITH CHECK (
                auth.uid() = user_id AND status IN ('sealed', 'delivered', 'opened') AND deleted_at IS NULL
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'time_capsules' AND policyname = 'Service role can update capsules'
    ) THEN
        CREATE POLICY "Service role can update capsules" ON time_capsules
            FOR UPDATE USING (auth.role() = 'service_role')
            WITH CHECK (auth.role() = 'service_role');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'time_capsules' AND policyname = 'Users can soft delete own capsules'
    ) THEN
        CREATE POLICY "Users can soft delete own capsules" ON time_capsules
            FOR UPDATE USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id AND deleted_at IS NOT NULL);
    END IF;
END $$;

-- capsule_media policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capsule_media' AND policyname = 'Users can read own capsule media'
    ) THEN
        CREATE POLICY "Users can read own capsule media" ON capsule_media
            FOR SELECT USING (
                capsule_id IN (
                    SELECT id FROM time_capsules WHERE user_id = auth.uid() AND deleted_at IS NULL
                )
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capsule_media' AND policyname = 'Service role can manage capsule media'
    ) THEN
        CREATE POLICY "Service role can manage capsule media" ON capsule_media
            FOR ALL USING (auth.role() = 'service_role')
            WITH CHECK (auth.role() = 'service_role');
    END IF;
END $$;

-- capsule_templates policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capsule_templates' AND policyname = 'Anyone can view templates'
    ) THEN
        CREATE POLICY "Anyone can view templates" ON capsule_templates
            FOR SELECT USING (true);
    END IF;
END $$;

-- capsule_snapshots policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capsule_snapshots' AND policyname = 'Users can view own snapshots'
    ) THEN
        CREATE POLICY "Users can view own snapshots" ON capsule_snapshots
            FOR SELECT USING (
                capsule_id IN (
                    SELECT id FROM time_capsules WHERE user_id = auth.uid() AND deleted_at IS NULL
                )
            );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'capsule_snapshots' AND policyname = 'Service role can manage snapshots'
    ) THEN
        CREATE POLICY "Service role can manage snapshots" ON capsule_snapshots
            FOR ALL USING (auth.role() = 'service_role')
            WITH CHECK (auth.role() = 'service_role');
    END IF;
END $$;

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Check capsule quota for user (atomic operation)
CREATE OR REPLACE FUNCTION check_capsule_quota(p_user_id UUID, p_file_size_bytes INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_is_premium BOOLEAN;
    v_capsule_count INTEGER;
    v_storage_used BIGINT;
    v_max_capsules INTEGER;
    v_max_storage BIGINT;
BEGIN
    -- Check if user has premium subscription
    SELECT EXISTS (
        SELECT 1 FROM subscriptions
        WHERE user_id = p_user_id
        AND status IN ('active', 'trialing')
        AND current_period_end > now()
    ) INTO v_is_premium;

    -- Set limits based on tier
    IF v_is_premium THEN
        v_max_capsules := 999999; -- Effectively unlimited
        v_max_storage := 10737418240; -- 10GB in bytes
    ELSE
        v_max_capsules := 5;
        v_max_storage := 104857600; -- 100MB in bytes
    END IF;

    -- Count active capsules (not deleted)
    SELECT COUNT(*) INTO v_capsule_count
    FROM time_capsules
    WHERE user_id = p_user_id AND deleted_at IS NULL;

    -- Calculate storage used
    SELECT COALESCE(SUM(cm.file_size_bytes), 0) INTO v_storage_used
    FROM capsule_media cm
    JOIN time_capsules tc ON cm.capsule_id = tc.id
    WHERE tc.user_id = p_user_id AND tc.deleted_at IS NULL;

    -- Check quota
    IF v_capsule_count >= v_max_capsules THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'capsule_count_exceeded',
            'message', format('You have reached your limit of %s capsules. Upgrade to Premium for unlimited capsules.', v_max_capsules),
            'current_count', v_capsule_count,
            'max_count', v_max_capsules
        );
    END IF;

    IF (v_storage_used + p_file_size_bytes) > v_max_storage THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'reason', 'storage_exceeded',
            'message', format('Storage limit exceeded. Used: %s MB, Limit: %s MB',
                (v_storage_used / 1048576)::INTEGER,
                (v_max_storage / 1048576)::INTEGER
            ),
            'current_storage', v_storage_used,
            'max_storage', v_max_storage
        );
    END IF;

    RETURN jsonb_build_object(
        'allowed', true,
        'is_premium', v_is_premium,
        'current_count', v_capsule_count,
        'max_count', v_max_capsules,
        'current_storage', v_storage_used,
        'max_storage', v_max_storage
    );
END;
$$;
