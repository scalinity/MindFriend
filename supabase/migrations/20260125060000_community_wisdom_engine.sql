-- Migration: Community Wisdom Engine
-- Privacy-preserving anonymous aggregation and personalized recommendations
-- Created: 2026-01-25

-- ============================================================================
-- SECTION 1: Drop legacy table
-- ============================================================================

-- Drop legacy community_wisdom table (superseded by new schema)
DROP TABLE IF EXISTS public.community_wisdom CASCADE;

-- ============================================================================
-- SECTION 2: Core Tables
-- ============================================================================

-- User consent for wisdom engine participation
CREATE TABLE IF NOT EXISTS public.wisdom_consent (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    contribute_anonymous_data BOOLEAN NOT NULL DEFAULT false,
    receive_recommendations BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.wisdom_consent IS 'User consent preferences for community wisdom participation';

-- Anonymized contributions (SHA-256 hashed user_id)
CREATE TABLE IF NOT EXISTS public.wisdom_contributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_hash TEXT NOT NULL, -- SHA-256 hash of (user_id + salt)
    contribution_type TEXT NOT NULL CHECK (contribution_type IN (
        'mood_pattern', 'exercise_effectiveness', 'pathway_progress', 'strategy_success'
    )),
    context_tags TEXT[] NOT NULL DEFAULT '{}',
    data_json JSONB NOT NULL,
    contributed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Enforce hash format (64-char hex string)
    CONSTRAINT wisdom_contributions_hash_format CHECK (length(user_hash) = 64 AND user_hash ~ '^[a-f0-9]+$')
);

COMMENT ON TABLE public.wisdom_contributions IS 'Anonymized user contributions for aggregation (SHA-256 hashed user IDs)';

-- Precomputed insights from aggregation
CREATE TABLE IF NOT EXISTS public.wisdom_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    insight_type TEXT NOT NULL CHECK (insight_type IN (
        'not_alone', 'trend', 'strategy_highlight', 'milestone', 'exercise_effectiveness'
    )),
    context_tags TEXT[] NOT NULL DEFAULT '{}',
    insight_content TEXT NOT NULL,
    confidence_score DECIMAL(3,2) NOT NULL DEFAULT 0.50 CHECK (confidence_score >= 0.0 AND confidence_score <= 1.0),
    sample_size INTEGER NOT NULL CHECK (sample_size >= 10), -- Minimum 10 for MVP, 100 for production
    aggregate_data JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ -- NULL = no expiration
);

COMMENT ON TABLE public.wisdom_insights IS 'Aggregated insights with minimum sample size enforcement';

-- Recommendations shown to users (for feedback tracking)
CREATE TABLE IF NOT EXISTS public.wisdom_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    insight_id UUID NOT NULL REFERENCES public.wisdom_insights(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    relevance_score DECIMAL(3,2) NOT NULL DEFAULT 0.50 CHECK (relevance_score >= 0.0 AND relevance_score <= 1.0),
    context_tags TEXT[] DEFAULT '{}',
    shown_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    helpful BOOLEAN -- NULL = no feedback, true = helpful, false = not helpful
);

COMMENT ON TABLE public.wisdom_recommendations IS 'Track which insights were shown to users for feedback analysis';

-- Community-submitted coping strategies
CREATE TABLE IF NOT EXISTS public.community_strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN (
        'anxiety', 'depression', 'stress', 'grief', 'anger',
        'loneliness', 'overwhelm', 'sleep', 'motivation', 'general'
    )),
    subcategory TEXT,
    strategy_text TEXT NOT NULL CHECK (char_length(strategy_text) >= 10 AND char_length(strategy_text) <= 500),
    context TEXT CHECK (context IS NULL OR char_length(context) <= 200),

    -- Anonymized metadata (opt-in only)
    contributor_demographic TEXT CHECK (contributor_demographic IN (
        'teen', 'young_adult', 'adult', 'senior', NULL
    )),
    transition_context TEXT,

    -- Stats (updated by trigger)
    helpful_count INTEGER NOT NULL DEFAULT 0,
    not_helpful_count INTEGER NOT NULL DEFAULT 0,
    view_count INTEGER NOT NULL DEFAULT 0,

    -- Moderation
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'approved', 'rejected', 'flagged'
    )),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id),
    rejection_reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.community_strategies IS 'User-submitted coping strategies with moderation workflow';

-- Strategy votes (one vote per user per strategy)
CREATE TABLE IF NOT EXISTS public.strategy_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_id UUID NOT NULL REFERENCES public.community_strategies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    vote_type TEXT NOT NULL CHECK (vote_type IN ('helpful', 'not_helpful')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(strategy_id, user_id) -- One vote per user per strategy
);

COMMENT ON TABLE public.strategy_votes IS 'User votes on community strategies (deduplication enforced)';

-- Daily aggregated statistics (privacy-safe summaries)
CREATE TABLE IF NOT EXISTS public.community_aggregate_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stat_date DATE NOT NULL,
    stat_type TEXT NOT NULL CHECK (stat_type IN (
        'daily_mood', 'mood_by_day_of_week', 'mood_by_time',
        'common_emotions', 'exercise_effectiveness', 'pathway_stats'
    )),
    category TEXT,
    stat_data JSONB NOT NULL,
    sample_size INTEGER NOT NULL CHECK (sample_size >= 10), -- Minimum sample
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(stat_date, stat_type, category)
);

COMMENT ON TABLE public.community_aggregate_stats IS 'Daily aggregated community statistics';

-- ============================================================================
-- SECTION 3: Indexes
-- ============================================================================

-- wisdom_consent
CREATE INDEX IF NOT EXISTS idx_wisdom_consent_user ON public.wisdom_consent(user_id);
CREATE INDEX IF NOT EXISTS idx_wisdom_consent_contribute ON public.wisdom_consent(contribute_anonymous_data)
    WHERE contribute_anonymous_data = true;

-- wisdom_contributions
CREATE INDEX IF NOT EXISTS idx_wisdom_contributions_type_date ON public.wisdom_contributions(contribution_type, contributed_at DESC);
CREATE INDEX IF NOT EXISTS idx_wisdom_contributions_tags ON public.wisdom_contributions USING GIN (context_tags);
CREATE INDEX IF NOT EXISTS idx_wisdom_contributions_date ON public.wisdom_contributions(contributed_at DESC);

-- wisdom_insights
CREATE INDEX IF NOT EXISTS idx_wisdom_insights_type_tags ON public.wisdom_insights(insight_type);
CREATE INDEX IF NOT EXISTS idx_wisdom_insights_tags ON public.wisdom_insights USING GIN (context_tags);
CREATE INDEX IF NOT EXISTS idx_wisdom_insights_valid ON public.wisdom_insights(valid_until) WHERE valid_until IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_wisdom_insights_sample_size ON public.wisdom_insights(sample_size DESC);

-- wisdom_recommendations
CREATE INDEX IF NOT EXISTS idx_wisdom_recommendations_user ON public.wisdom_recommendations(user_id, shown_at DESC);
CREATE INDEX IF NOT EXISTS idx_wisdom_recommendations_insight ON public.wisdom_recommendations(insight_id);
CREATE INDEX IF NOT EXISTS idx_wisdom_recommendations_feedback ON public.wisdom_recommendations(helpful) WHERE helpful IS NOT NULL;

-- community_strategies
CREATE INDEX IF NOT EXISTS idx_strategies_category_status ON public.community_strategies(category, status);
CREATE INDEX IF NOT EXISTS idx_strategies_approved ON public.community_strategies(status, helpful_count DESC)
    WHERE status = 'approved';
CREATE INDEX IF NOT EXISTS idx_strategies_pending ON public.community_strategies(created_at DESC)
    WHERE status = 'pending';

-- strategy_votes
CREATE INDEX IF NOT EXISTS idx_strategy_votes_strategy ON public.strategy_votes(strategy_id);
CREATE INDEX IF NOT EXISTS idx_strategy_votes_user ON public.strategy_votes(user_id);

-- community_aggregate_stats
CREATE INDEX IF NOT EXISTS idx_aggregate_stats_date_type ON public.community_aggregate_stats(stat_date DESC, stat_type);

-- ============================================================================
-- SECTION 4: Triggers
-- ============================================================================

-- Function to update strategy vote counts atomically
CREATE OR REPLACE FUNCTION public.update_strategy_vote_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.vote_type = 'helpful' THEN
            UPDATE public.community_strategies
            SET helpful_count = helpful_count + 1
            WHERE id = NEW.strategy_id;
        ELSE
            UPDATE public.community_strategies
            SET not_helpful_count = not_helpful_count + 1
            WHERE id = NEW.strategy_id;
        END IF;
    ELSIF TG_OP = 'UPDATE' AND OLD.vote_type != NEW.vote_type THEN
        -- User changed vote
        IF NEW.vote_type = 'helpful' THEN
            UPDATE public.community_strategies
            SET helpful_count = helpful_count + 1, not_helpful_count = not_helpful_count - 1
            WHERE id = NEW.strategy_id;
        ELSE
            UPDATE public.community_strategies
            SET helpful_count = helpful_count - 1, not_helpful_count = not_helpful_count + 1
            WHERE id = NEW.strategy_id;
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.vote_type = 'helpful' THEN
            UPDATE public.community_strategies
            SET helpful_count = GREATEST(0, helpful_count - 1)
            WHERE id = OLD.strategy_id;
        ELSE
            UPDATE public.community_strategies
            SET not_helpful_count = GREATEST(0, not_helpful_count - 1)
            WHERE id = OLD.strategy_id;
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for vote count updates
DROP TRIGGER IF EXISTS strategy_vote_counts_trigger ON public.strategy_votes;
CREATE TRIGGER strategy_vote_counts_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.strategy_votes
FOR EACH ROW EXECUTE FUNCTION public.update_strategy_vote_counts();

-- Function to update wisdom_consent.updated_at
CREATE OR REPLACE FUNCTION public.update_wisdom_consent_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS wisdom_consent_updated_at ON public.wisdom_consent;
CREATE TRIGGER wisdom_consent_updated_at
BEFORE UPDATE ON public.wisdom_consent
FOR EACH ROW EXECUTE FUNCTION public.update_wisdom_consent_timestamp();

-- Function to update strategy_votes.updated_at
CREATE OR REPLACE FUNCTION public.update_strategy_votes_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS strategy_votes_updated_at ON public.strategy_votes;
CREATE TRIGGER strategy_votes_updated_at
BEFORE UPDATE ON public.strategy_votes
FOR EACH ROW EXECUTE FUNCTION public.update_strategy_votes_timestamp();

-- ============================================================================
-- SECTION 5: Row Level Security
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.wisdom_consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wisdom_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wisdom_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wisdom_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_strategies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.strategy_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_aggregate_stats ENABLE ROW LEVEL SECURITY;

-- wisdom_consent: Users manage own consent only
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own consent' AND tablename = 'wisdom_consent') THEN
        CREATE POLICY "Users manage own consent" ON public.wisdom_consent
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- wisdom_contributions: Service role only (no individual access)
-- Users cannot read/write contributions directly; only aggregation functions access this
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role only for contributions' AND tablename = 'wisdom_contributions') THEN
        CREATE POLICY "Service role only for contributions" ON public.wisdom_contributions
            FOR ALL TO service_role USING (true);
    END IF;
END $$;

-- wisdom_insights: Anyone authenticated can read valid insights
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can view valid insights' AND tablename = 'wisdom_insights') THEN
        CREATE POLICY "Anyone can view valid insights" ON public.wisdom_insights
            FOR SELECT TO authenticated USING (valid_until IS NULL OR valid_until > now());
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages insights' AND tablename = 'wisdom_insights') THEN
        CREATE POLICY "Service role manages insights" ON public.wisdom_insights
            FOR ALL TO service_role USING (true);
    END IF;
END $$;

-- wisdom_recommendations: Users see own recommendations
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users view own recommendations' AND tablename = 'wisdom_recommendations') THEN
        CREATE POLICY "Users view own recommendations" ON public.wisdom_recommendations
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users update own feedback' AND tablename = 'wisdom_recommendations') THEN
        CREATE POLICY "Users update own feedback" ON public.wisdom_recommendations
            FOR UPDATE USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role inserts recommendations' AND tablename = 'wisdom_recommendations') THEN
        CREATE POLICY "Service role inserts recommendations" ON public.wisdom_recommendations
            FOR INSERT TO service_role WITH CHECK (true);
    END IF;
END $$;

-- community_strategies: Approved strategies visible to all; users can submit
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can view approved strategies' AND tablename = 'community_strategies') THEN
        CREATE POLICY "Anyone can view approved strategies" ON public.community_strategies
            FOR SELECT TO authenticated USING (status = 'approved');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages strategies' AND tablename = 'community_strategies') THEN
        CREATE POLICY "Service role manages strategies" ON public.community_strategies
            FOR ALL TO service_role USING (true);
    END IF;
END $$;

-- strategy_votes: Users manage own votes
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own votes' AND tablename = 'strategy_votes') THEN
        CREATE POLICY "Users manage own votes" ON public.strategy_votes
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- community_aggregate_stats: Anyone can view
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can view aggregate stats' AND tablename = 'community_aggregate_stats') THEN
        CREATE POLICY "Anyone can view aggregate stats" ON public.community_aggregate_stats
            FOR SELECT TO authenticated USING (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service role manages aggregate stats' AND tablename = 'community_aggregate_stats') THEN
        CREATE POLICY "Service role manages aggregate stats" ON public.community_aggregate_stats
            FOR ALL TO service_role USING (true);
    END IF;
END $$;

-- ============================================================================
-- SECTION 6: Helper Functions
-- ============================================================================

-- Function to check user consent
CREATE OR REPLACE FUNCTION public.check_wisdom_consent(p_user_id UUID, p_type TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_consent RECORD;
BEGIN
    SELECT contribute_anonymous_data, receive_recommendations
    INTO v_consent
    FROM public.wisdom_consent
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN false;
    END IF;

    IF p_type = 'contribute' THEN
        RETURN v_consent.contribute_anonymous_data;
    ELSIF p_type = 'receive' THEN
        RETURN v_consent.receive_recommendations;
    END IF;

    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to record recommendation feedback
CREATE OR REPLACE FUNCTION public.record_wisdom_feedback(
    p_recommendation_id UUID,
    p_helpful BOOLEAN
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE public.wisdom_recommendations
    SET helpful = p_helpful
    WHERE id = p_recommendation_id AND user_id = v_user_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get strategy helpful percentage
CREATE OR REPLACE FUNCTION public.get_strategy_helpful_percentage(p_strategy_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_helpful INTEGER;
    v_not_helpful INTEGER;
    v_total INTEGER;
BEGIN
    SELECT helpful_count, not_helpful_count
    INTO v_helpful, v_not_helpful
    FROM public.community_strategies
    WHERE id = p_strategy_id;

    v_total := v_helpful + v_not_helpful;

    IF v_total = 0 THEN
        RETURN 0;
    END IF;

    RETURN (v_helpful * 100 / v_total);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.check_wisdom_consent(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_wisdom_feedback(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_strategy_helpful_percentage(UUID) TO authenticated;

-- ============================================================================
-- SECTION 7: Initial Seed Data (sample insights for testing)
-- ============================================================================

-- Note: Real insights will be generated by the aggregation cron job
-- This seed data is for development/testing only

-- DO $$
-- BEGIN
--     INSERT INTO public.wisdom_insights (
--         insight_type, context_tags, insight_content, confidence_score, sample_size, aggregate_data, valid_from
--     ) VALUES
--     (
--         'not_alone',
--         ARRAY['mood:low', 'time:morning'],
--         '2,340+ others are feeling anxious this morning too',
--         0.95,
--         2340,
--         '{"average_mood": 2.3, "distribution": {"low": 2340, "medium": 1500, "high": 800}}'::jsonb,
--         NOW()
--     ),
--     (
--         'trend',
--         ARRAY['day:monday'],
--         'Many find Mondays hardest. It often eases after noon.',
--         0.82,
--         5200,
--         '{"monday_avg": 2.5, "friday_avg": 3.8}'::jsonb,
--         NOW()
--     ),
--     (
--         'exercise_effectiveness',
--         ARRAY['exercise:breathing', 'category:anxiety'],
--         '87% of users found 4-7-8 breathing helpful for anxiety',
--         0.91,
--         1850,
--         '{"exercise_id": "breathing_4_7_8", "helpful_rate": 0.87}'::jsonb,
--         NOW()
--     )
--     ON CONFLICT DO NOTHING;
-- END $$;
