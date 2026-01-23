-- Content Creator Platform Migration
-- Spec 13: Creator profiles, content, earnings, and revenue sharing

-- ============================================================================
-- TABLES
-- ============================================================================

-- Creator profiles
CREATE TABLE IF NOT EXISTS creators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Profile
    display_name TEXT NOT NULL,
    bio TEXT,
    profile_image_url TEXT,
    website_url TEXT,
    social_links JSONB DEFAULT '{}',

    -- Verification
    verification_level TEXT DEFAULT 'pending', -- pending, verified, expert, partner
    verified_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id),

    -- Credentials
    credentials JSONB DEFAULT '[]', -- Array of credential objects
    credential_documents TEXT[], -- Storage paths

    -- Status
    status TEXT DEFAULT 'pending', -- pending, approved, suspended, rejected
    status_reason TEXT,
    suspended_at TIMESTAMPTZ,

    -- Settings
    payout_enabled BOOLEAN DEFAULT false,
    stripe_account_id TEXT,
    tax_info_complete BOOLEAN DEFAULT false,

    -- Metrics (denormalized for performance)
    follower_count INTEGER DEFAULT 0,
    content_count INTEGER DEFAULT 0,
    total_plays INTEGER DEFAULT 0,
    total_minutes INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_creator_user UNIQUE (user_id)
);

-- Creator applications
CREATE TABLE IF NOT EXISTS creator_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),

    -- Application data
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    location TEXT,
    professional_background TEXT NOT NULL,
    teaching_philosophy TEXT,
    experience_years INTEGER,

    -- Credentials
    credentials JSONB NOT NULL, -- Array of credential claims
    credential_documents TEXT[], -- Uploaded document paths

    -- Portfolio
    portfolio_links TEXT[],
    sample_content_urls TEXT[],

    -- Status
    status TEXT DEFAULT 'pending', -- pending, under_review, approved, rejected
    reviewer_id UUID REFERENCES auth.users(id),
    review_notes TEXT,
    reviewed_at TIMESTAMPTZ,

    -- Rejection
    rejection_reason TEXT,
    rejection_category TEXT, -- credentials, quality, other

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Content series (must be created before creator_content due to FK)
CREATE TABLE IF NOT EXISTS content_series (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES creators(id) ON DELETE CASCADE,

    title TEXT NOT NULL,
    description TEXT,
    cover_image_url TEXT,

    content_count INTEGER DEFAULT 0,
    total_duration_seconds INTEGER DEFAULT 0,

    status TEXT DEFAULT 'draft', -- draft, published
    published_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Creator content
CREATE TABLE IF NOT EXISTS creator_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES creators(id) ON DELETE CASCADE,

    -- Content type
    content_type TEXT NOT NULL, -- meditation, breathing, journaling, educational, movement
    format TEXT NOT NULL, -- audio, video, text

    -- Basic info
    title TEXT NOT NULL,
    description TEXT,
    duration_seconds INTEGER,
    difficulty TEXT, -- beginner, intermediate, advanced

    -- Media
    media_url TEXT, -- Main content file
    cover_image_url TEXT,
    thumbnail_url TEXT,

    -- Metadata
    category TEXT NOT NULL,
    tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    target_audience JSONB DEFAULT '{}', -- age_range, experience_level, etc.

    -- Accessibility
    transcript TEXT,
    transcript_url TEXT,
    has_captions BOOLEAN DEFAULT false,
    captions_url TEXT,

    -- Content warnings
    trigger_warnings TEXT[],
    age_rating TEXT DEFAULT 'all_ages',

    -- Series
    series_id UUID REFERENCES content_series(id),
    series_order INTEGER,

    -- Review
    status TEXT DEFAULT 'draft', -- draft, submitted, in_review, approved, rejected, published
    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewer_id UUID REFERENCES auth.users(id),
    review_feedback TEXT,
    published_at TIMESTAMPTZ,

    -- Metrics
    play_count INTEGER DEFAULT 0,
    unique_listeners INTEGER DEFAULT 0,
    completion_count INTEGER DEFAULT 0,
    average_completion_rate DECIMAL(5,4) DEFAULT 0,
    total_minutes_played INTEGER DEFAULT 0,
    rating_count INTEGER DEFAULT 0,
    average_rating DECIMAL(3,2),

    -- Settings
    is_premium BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    allow_download BOOLEAN DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Content reviews
CREATE TABLE IF NOT EXISTS content_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL REFERENCES creator_content(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES auth.users(id),

    -- Review details
    decision TEXT NOT NULL, -- approved, needs_changes, rejected
    feedback TEXT,
    feedback_categories TEXT[], -- audio_quality, content_safety, accuracy, etc.

    -- Checklist
    audio_quality_ok BOOLEAN,
    content_safety_ok BOOLEAN,
    accuracy_ok BOOLEAN,
    originality_ok BOOLEAN,
    metadata_ok BOOLEAN,
    accessibility_ok BOOLEAN,

    -- Notes
    internal_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Creator followers
CREATE TABLE IF NOT EXISTS creator_followers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES creators(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    notify_new_content BOOLEAN DEFAULT true,
    followed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_follower UNIQUE (creator_id, user_id)
);

-- Content engagement (for revenue calculation)
CREATE TABLE IF NOT EXISTS content_engagement (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL REFERENCES creator_content(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Session data
    session_id UUID NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER,

    -- Completion
    completed BOOLEAN DEFAULT false,
    completion_percentage DECIMAL(5,2),

    -- User status (for revenue)
    user_is_premium BOOLEAN NOT NULL,

    -- Period (for aggregation)
    engagement_date DATE NOT NULL,
    engagement_month TEXT NOT NULL, -- YYYY-MM

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Revenue periods
CREATE TABLE IF NOT EXISTS revenue_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    period_month TEXT NOT NULL UNIQUE, -- YYYY-MM
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    -- Pool
    total_subscription_revenue DECIMAL(12,2),
    creator_pool_percentage DECIMAL(5,4) DEFAULT 0.30,
    total_creator_pool DECIMAL(12,2),

    -- Engagement totals
    total_premium_minutes INTEGER DEFAULT 0,

    -- Status
    status TEXT DEFAULT 'open', -- open, calculating, finalized, paid
    finalized_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Creator earnings
CREATE TABLE IF NOT EXISTS creator_earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES creators(id) ON DELETE CASCADE,
    period_id UUID NOT NULL REFERENCES revenue_periods(id) ON DELETE CASCADE,

    -- Engagement
    total_minutes INTEGER DEFAULT 0,
    premium_minutes INTEGER DEFAULT 0, -- Only premium user engagement counts

    -- Revenue share
    share_percentage DECIMAL(8,6), -- Of total pool
    gross_earnings DECIMAL(10,2),
    platform_fee DECIMAL(10,2),
    net_earnings DECIMAL(10,2),

    -- Payout
    payout_status TEXT DEFAULT 'pending', -- pending, processing, paid, failed, below_threshold
    payout_id TEXT, -- Stripe transfer ID
    paid_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_creator_period UNIQUE (creator_id, period_id)
);

-- Content by creator (for earnings breakdown)
CREATE TABLE IF NOT EXISTS creator_earnings_by_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    earnings_id UUID NOT NULL REFERENCES creator_earnings(id) ON DELETE CASCADE,
    content_id UUID NOT NULL REFERENCES creator_content(id) ON DELETE CASCADE,

    minutes INTEGER DEFAULT 0,
    earnings DECIMAL(10,2),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_earnings_content UNIQUE (earnings_id, content_id)
);

-- Payouts
CREATE TABLE IF NOT EXISTS creator_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES creators(id) ON DELETE CASCADE,

    -- Amount
    amount DECIMAL(10,2) NOT NULL,
    currency TEXT DEFAULT 'USD',

    -- Stripe
    stripe_transfer_id TEXT,
    stripe_payout_id TEXT,

    -- Status
    status TEXT DEFAULT 'pending', -- pending, processing, succeeded, failed
    failure_reason TEXT,

    -- Periods included
    period_ids UUID[],

    initiated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User content ratings
CREATE TABLE IF NOT EXISTS content_ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL REFERENCES creator_content(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    review TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_content_rating UNIQUE (content_id, user_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_creators_status ON creators(status);
CREATE INDEX IF NOT EXISTS idx_creators_verification ON creators(verification_level);
CREATE INDEX IF NOT EXISTS idx_creator_applications_status ON creator_applications(status);
CREATE INDEX IF NOT EXISTS idx_creator_content_creator ON creator_content(creator_id);
CREATE INDEX IF NOT EXISTS idx_creator_content_status ON creator_content(status);
CREATE INDEX IF NOT EXISTS idx_creator_content_category ON creator_content(category, status);
CREATE INDEX IF NOT EXISTS idx_creator_followers_creator ON creator_followers(creator_id);
CREATE INDEX IF NOT EXISTS idx_creator_followers_user ON creator_followers(user_id);
CREATE INDEX IF NOT EXISTS idx_content_engagement_content ON content_engagement(content_id, engagement_month);
CREATE INDEX IF NOT EXISTS idx_content_engagement_user ON content_engagement(user_id, engagement_date);
CREATE INDEX IF NOT EXISTS idx_creator_earnings_creator ON creator_earnings(creator_id);
CREATE INDEX IF NOT EXISTS idx_creator_earnings_period ON creator_earnings(period_id);
CREATE INDEX IF NOT EXISTS idx_content_series_creator ON content_series(creator_id);
CREATE INDEX IF NOT EXISTS idx_content_ratings_content ON content_ratings(content_id);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE creators ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_series ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_followers ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_engagement ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE revenue_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_earnings_by_content ENABLE ROW LEVEL SECURITY;

-- Creators policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creators' AND policyname = 'Anyone can view approved creators') THEN
        CREATE POLICY "Anyone can view approved creators"
            ON creators FOR SELECT
            USING (status = 'approved');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creators' AND policyname = 'Creators can manage own profile') THEN
        CREATE POLICY "Creators can manage own profile"
            ON creators FOR ALL
            USING (user_id = auth.uid());
    END IF;
END $$;

-- Creator applications policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_applications' AND policyname = 'Users can view own applications') THEN
        CREATE POLICY "Users can view own applications"
            ON creator_applications FOR SELECT
            USING (user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_applications' AND policyname = 'Users can submit applications') THEN
        CREATE POLICY "Users can submit applications"
            ON creator_applications FOR INSERT
            WITH CHECK (user_id = auth.uid());
    END IF;
END $$;

-- Creator content policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_content' AND policyname = 'Anyone can view published content') THEN
        CREATE POLICY "Anyone can view published content"
            ON creator_content FOR SELECT
            USING (status = 'published');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_content' AND policyname = 'Creators can manage own content') THEN
        CREATE POLICY "Creators can manage own content"
            ON creator_content FOR ALL
            USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));
    END IF;
END $$;

-- Content series policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_series' AND policyname = 'Anyone can view published series') THEN
        CREATE POLICY "Anyone can view published series"
            ON content_series FOR SELECT
            USING (status = 'published');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_series' AND policyname = 'Creators can manage own series') THEN
        CREATE POLICY "Creators can manage own series"
            ON content_series FOR ALL
            USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));
    END IF;
END $$;

-- Content reviews policies (admin only via service role)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_reviews' AND policyname = 'Creators can view reviews of own content') THEN
        CREATE POLICY "Creators can view reviews of own content"
            ON content_reviews FOR SELECT
            USING (
                content_id IN (
                    SELECT id FROM creator_content
                    WHERE creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid())
                )
            );
    END IF;
END $$;

-- Creator followers policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_followers' AND policyname = 'Users can manage follows') THEN
        CREATE POLICY "Users can manage follows"
            ON creator_followers FOR ALL
            USING (user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_followers' AND policyname = 'Creators can view their followers') THEN
        CREATE POLICY "Creators can view their followers"
            ON creator_followers FOR SELECT
            USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));
    END IF;
END $$;

-- Content engagement policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_engagement' AND policyname = 'Users can record own engagement') THEN
        CREATE POLICY "Users can record own engagement"
            ON content_engagement FOR INSERT
            WITH CHECK (user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_engagement' AND policyname = 'Creators can view own engagement') THEN
        CREATE POLICY "Creators can view own engagement"
            ON content_engagement FOR SELECT
            USING (
                content_id IN (
                    SELECT id FROM creator_content
                    WHERE creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid())
                )
            );
    END IF;
END $$;

-- Creator earnings policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_earnings' AND policyname = 'Creators can view own earnings') THEN
        CREATE POLICY "Creators can view own earnings"
            ON creator_earnings FOR SELECT
            USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));
    END IF;
END $$;

-- Creator earnings by content policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_earnings_by_content' AND policyname = 'Creators can view own earnings breakdown') THEN
        CREATE POLICY "Creators can view own earnings breakdown"
            ON creator_earnings_by_content FOR SELECT
            USING (
                earnings_id IN (
                    SELECT id FROM creator_earnings
                    WHERE creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid())
                )
            );
    END IF;
END $$;

-- Creator payouts policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'creator_payouts' AND policyname = 'Creators can view own payouts') THEN
        CREATE POLICY "Creators can view own payouts"
            ON creator_payouts FOR SELECT
            USING (creator_id IN (SELECT id FROM creators WHERE user_id = auth.uid()));
    END IF;
END $$;

-- Revenue periods policies (read-only for creators)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'revenue_periods' AND policyname = 'Creators can view revenue periods') THEN
        CREATE POLICY "Creators can view revenue periods"
            ON revenue_periods FOR SELECT
            USING (
                EXISTS (SELECT 1 FROM creators WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- Content ratings policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_ratings' AND policyname = 'Users can rate content') THEN
        CREATE POLICY "Users can rate content"
            ON content_ratings FOR ALL
            USING (user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'content_ratings' AND policyname = 'Anyone can view ratings') THEN
        CREATE POLICY "Anyone can view ratings"
            ON content_ratings FOR SELECT
            USING (true);
    END IF;
END $$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger to update creator content count
CREATE OR REPLACE FUNCTION update_creator_content_metrics()
RETURNS TRIGGER AS $$
DECLARE
    target_creator_id UUID;
BEGIN
    -- Determine which creator_id to update
    IF TG_OP = 'DELETE' THEN
        target_creator_id := OLD.creator_id;
    ELSE
        target_creator_id := NEW.creator_id;
    END IF;

    -- Update the creator's content count
    UPDATE creators
    SET
        content_count = (
            SELECT COUNT(*)
            FROM creator_content
            WHERE creator_id = target_creator_id AND status = 'published'
        ),
        updated_at = NOW()
    WHERE id = target_creator_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_creator_content_count ON creator_content;
CREATE TRIGGER trigger_update_creator_content_count
    AFTER INSERT OR UPDATE OR DELETE ON creator_content
    FOR EACH ROW
    EXECUTE FUNCTION update_creator_content_metrics();

-- Trigger to update follower count
CREATE OR REPLACE FUNCTION update_creator_follower_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE creators SET follower_count = follower_count + 1, updated_at = NOW() WHERE id = NEW.creator_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE creators SET follower_count = follower_count - 1, updated_at = NOW() WHERE id = OLD.creator_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_follower_count ON creator_followers;
CREATE TRIGGER trigger_update_follower_count
    AFTER INSERT OR DELETE ON creator_followers
    FOR EACH ROW
    EXECUTE FUNCTION update_creator_follower_count();

-- Trigger to update content rating average
CREATE OR REPLACE FUNCTION update_content_rating_average()
RETURNS TRIGGER AS $$
DECLARE
    target_content_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_content_id := OLD.content_id;
    ELSE
        target_content_id := NEW.content_id;
    END IF;

    UPDATE creator_content
    SET
        average_rating = (
            SELECT AVG(rating)::DECIMAL(3,2)
            FROM content_ratings
            WHERE content_id = target_content_id
        ),
        rating_count = (
            SELECT COUNT(*)
            FROM content_ratings
            WHERE content_id = target_content_id
        ),
        updated_at = NOW()
    WHERE id = target_content_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_content_rating ON content_ratings;
CREATE TRIGGER trigger_update_content_rating
    AFTER INSERT OR UPDATE OR DELETE ON content_ratings
    FOR EACH ROW
    EXECUTE FUNCTION update_content_rating_average();

-- Trigger to update series content count
CREATE OR REPLACE FUNCTION update_series_content_count()
RETURNS TRIGGER AS $$
DECLARE
    target_series_id UUID;
BEGIN
    -- Get the series_id that needs updating
    IF TG_OP = 'DELETE' THEN
        target_series_id := OLD.series_id;
    ELSIF TG_OP = 'UPDATE' THEN
        -- If series_id changed, update both old and new
        IF OLD.series_id IS DISTINCT FROM NEW.series_id THEN
            IF OLD.series_id IS NOT NULL THEN
                UPDATE content_series
                SET
                    content_count = (SELECT COUNT(*) FROM creator_content WHERE series_id = OLD.series_id AND status = 'published'),
                    total_duration_seconds = COALESCE((SELECT SUM(duration_seconds) FROM creator_content WHERE series_id = OLD.series_id AND status = 'published'), 0),
                    updated_at = NOW()
                WHERE id = OLD.series_id;
            END IF;
        END IF;
        target_series_id := NEW.series_id;
    ELSE
        target_series_id := NEW.series_id;
    END IF;

    -- Update target series if it exists
    IF target_series_id IS NOT NULL THEN
        UPDATE content_series
        SET
            content_count = (SELECT COUNT(*) FROM creator_content WHERE series_id = target_series_id AND status = 'published'),
            total_duration_seconds = COALESCE((SELECT SUM(duration_seconds) FROM creator_content WHERE series_id = target_series_id AND status = 'published'), 0),
            updated_at = NOW()
        WHERE id = target_series_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_series_content_count ON creator_content;
CREATE TRIGGER trigger_update_series_content_count
    AFTER INSERT OR UPDATE OR DELETE ON creator_content
    FOR EACH ROW
    EXECUTE FUNCTION update_series_content_count();

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Function to get period subscription revenue (placeholder for actual implementation)
CREATE OR REPLACE FUNCTION get_period_subscription_revenue(period_start DATE, period_end DATE)
RETURNS TABLE(total DECIMAL) AS $$
BEGIN
    -- This would integrate with your actual subscription/payment tracking
    -- For now, return sum of premium subscriptions during the period
    RETURN QUERY
    SELECT COALESCE(SUM(
        CASE
            WHEN tier = 'monthly' THEN 9.99
            WHEN tier = 'yearly' THEN 79.99 / 12
            ELSE 0
        END
    ), 0)::DECIMAL
    FROM subscriptions
    WHERE status = 'active'
    AND created_at >= period_start
    AND created_at <= period_end;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get content analytics
CREATE OR REPLACE FUNCTION get_content_analytics(p_content_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
    creator_user_id UUID;
BEGIN
    -- Verify ownership
    SELECT c.user_id INTO creator_user_id
    FROM creators c
    JOIN creator_content cc ON cc.creator_id = c.id
    WHERE cc.id = p_content_id;

    IF creator_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Not authorized to view this content''s analytics';
    END IF;

    SELECT jsonb_build_object(
        'totalPlays', COALESCE(cc.play_count, 0),
        'uniqueListeners', COALESCE(cc.unique_listeners, 0),
        'completionRate', COALESCE(cc.average_completion_rate, 0),
        'averageRating', cc.average_rating,
        'ratingCount', COALESCE(cc.rating_count, 0),
        'totalMinutesPlayed', COALESCE(cc.total_minutes_played, 0),
        'dailyPlays', (
            SELECT jsonb_agg(jsonb_build_object('date', engagement_date, 'count', cnt))
            FROM (
                SELECT engagement_date, COUNT(*) as cnt
                FROM content_engagement
                WHERE content_id = p_content_id
                AND engagement_date >= CURRENT_DATE - INTERVAL '30 days'
                GROUP BY engagement_date
                ORDER BY engagement_date
            ) daily
        )
    ) INTO result
    FROM creator_content cc
    WHERE cc.id = p_content_id;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_period_subscription_revenue TO authenticated;
GRANT EXECUTE ON FUNCTION get_content_analytics TO authenticated;
