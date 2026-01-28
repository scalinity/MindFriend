-- Fix missing predictive mood tables and get_home_context RPC bug
-- Issue: Tables return 404, RPC references non-existent column 'posted_at'

-- =====================================================
-- 1. Ensure mood_predictions table exists
-- =====================================================
CREATE TABLE IF NOT EXISTS public.mood_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    predicted_for DATE NOT NULL,
    predicted_mood DECIMAL(3,1) NOT NULL CHECK (predicted_mood >= 1 AND predicted_mood <= 10),
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    factors JSONB NOT NULL DEFAULT '[]'::jsonb,
    model_version VARCHAR(32) NOT NULL DEFAULT 'v1.0-regression',
    features_used JSONB NOT NULL DEFAULT '{}'::jsonb,
    actual_mood DECIMAL(3,1) CHECK (actual_mood IS NULL OR (actual_mood >= 1 AND actual_mood <= 10)),
    prediction_accuracy DECIMAL(3,2) CHECK (prediction_accuracy IS NULL OR (prediction_accuracy >= 0 AND prediction_accuracy <= 1)),
    notification_sent BOOLEAN NOT NULL DEFAULT false,
    notification_sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, predicted_for)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_mood_predictions_user_date ON public.mood_predictions(user_id, predicted_for DESC);
CREATE INDEX IF NOT EXISTS idx_mood_predictions_pending ON public.mood_predictions(user_id, predicted_for) WHERE actual_mood IS NULL;

-- RLS
ALTER TABLE public.mood_predictions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own predictions" ON public.mood_predictions;
CREATE POLICY "Users can read own predictions" ON public.mood_predictions FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage predictions" ON public.mood_predictions;
CREATE POLICY "Service role can manage predictions" ON public.mood_predictions FOR ALL USING (auth.role() = 'service_role');

-- =====================================================
-- 2. Ensure preemptive_interventions table exists
-- =====================================================
CREATE TABLE IF NOT EXISTS public.preemptive_interventions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    prediction_id UUID NOT NULL REFERENCES public.mood_predictions(id) ON DELETE CASCADE,
    intervention_type VARCHAR(32) NOT NULL CHECK (
        intervention_type IN ('rest_suggestion', 'movement_suggestion', 'pattern_break', 'general_support')
    ),
    content TEXT NOT NULL,
    suggested_exercise_id UUID REFERENCES public.exercises(id) ON DELETE SET NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (
        status IN ('pending', 'delivered', 'accepted', 'dismissed', 'expired')
    ),
    delivered_at TIMESTAMPTZ,
    user_response TEXT,
    response_recorded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes (using full table name prefix to avoid collision with interventions table indexes)
CREATE INDEX IF NOT EXISTS idx_preemptive_interventions_user_status ON public.preemptive_interventions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_preemptive_interventions_prediction ON public.preemptive_interventions(prediction_id);
CREATE INDEX IF NOT EXISTS idx_preemptive_interventions_pending ON public.preemptive_interventions(user_id, created_at DESC) WHERE status = 'pending';

-- RLS
ALTER TABLE public.preemptive_interventions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own interventions" ON public.preemptive_interventions;
CREATE POLICY "Users can read own interventions" ON public.preemptive_interventions FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own interventions" ON public.preemptive_interventions;
CREATE POLICY "Users can update own interventions" ON public.preemptive_interventions FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage interventions" ON public.preemptive_interventions;
CREATE POLICY "Service role can manage interventions" ON public.preemptive_interventions FOR ALL USING (auth.role() = 'service_role');

-- =====================================================
-- 3. Fix get_home_context function (posted_at -> created_at)
-- SECURITY: Added auth check to prevent IDOR (CWE-639)
-- CORRECTNESS: Fixed date calculations to use date subtraction
-- =====================================================
CREATE OR REPLACE FUNCTION public.get_home_context(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_today_mood INT;
    v_mood_trend TEXT;
    v_low_mood_days INT;
    v_days_since_exercise INT;
    v_days_since_circle INT;
    v_quest_done BOOLEAN;
    v_mood_context TEXT;
    v_show_crisis BOOLEAN;
    v_message TEXT;
    v_actions JSONB;
    v_exercise_ids UUID[];
BEGIN
    -- SECURITY CHECK: Prevent IDOR - caller must be the user or service_role
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF v_caller_id != p_user_id AND (SELECT auth.role()) != 'service_role' THEN
        RAISE EXCEPTION 'Access denied: cannot view another user''s home context';
    END IF;

    -- Get today's mood
    SELECT mood_score INTO v_today_mood
    FROM moods
    WHERE user_id = p_user_id AND local_date = CURRENT_DATE::TEXT
    ORDER BY created_at DESC LIMIT 1;

    -- Calculate mood trend (last 7 days)
    SELECT CASE
        WHEN AVG(CASE WHEN created_at > NOW() - INTERVAL '3 days' THEN mood_score END) >
             AVG(CASE WHEN created_at <= NOW() - INTERVAL '3 days' THEN mood_score END) THEN 'improving'
        WHEN AVG(CASE WHEN created_at > NOW() - INTERVAL '3 days' THEN mood_score END) <
             AVG(CASE WHEN created_at <= NOW() - INTERVAL '3 days' THEN mood_score END) THEN 'declining'
        ELSE 'stable'
    END INTO v_mood_trend
    FROM moods
    WHERE user_id = p_user_id AND created_at > NOW() - INTERVAL '7 days';

    -- Count consecutive low mood days
    SELECT COUNT(*) INTO v_low_mood_days
    FROM (
        SELECT local_date, AVG(mood_score) as avg_mood
        FROM moods
        WHERE user_id = p_user_id AND created_at > NOW() - INTERVAL '7 days'
        GROUP BY local_date
        HAVING AVG(mood_score) <= 2
    ) low_days;

    -- Days since last exercise (using date subtraction for accuracy)
    SELECT COALESCE(
        (CURRENT_DATE - MAX(completed_at)::date)::INT,
        999
    ) INTO v_days_since_exercise
    FROM exercise_sessions
    WHERE user_id = p_user_id;

    -- Days since last circle check-in (FIXED: use created_at, not posted_at)
    -- Using date subtraction instead of EXTRACT(DAY FROM interval) for accuracy
    SELECT COALESCE(
        (CURRENT_DATE - MAX(created_at)::date)::INT,
        999
    ) INTO v_days_since_circle
    FROM circle_posts
    WHERE user_id = p_user_id;

    -- Check if quest completed today
    SELECT EXISTS(
        SELECT 1 FROM quests
        WHERE user_id = p_user_id
            AND local_date = CURRENT_DATE::TEXT
            AND status = 'completed'
    ) INTO v_quest_done;

    -- Determine mood context
    v_mood_context := CASE
        WHEN v_today_mood IS NULL THEN 'neutral'
        WHEN v_today_mood <= 2 THEN 'low'
        WHEN v_today_mood >= 4 THEN 'high'
        ELSE 'neutral'
    END;

    -- Show crisis support if 3+ consecutive low mood days
    v_show_crisis := v_low_mood_days >= 3;

    -- Generate supportive message
    v_message := CASE
        WHEN v_mood_context = 'low' THEN 'It''s okay to have tough days. We''re here for you.'
        WHEN v_mood_context = 'high' THEN 'Great to see you''re doing well!'
        ELSE 'How are you feeling today?'
    END;

    -- Build recommended actions
    v_actions := '[]'::jsonb;
    IF NOT v_quest_done THEN
        v_actions := v_actions || '[{"type": "quest", "title": "Complete your daily quest", "priority": 1}]'::jsonb;
    END IF;
    IF v_days_since_exercise > 2 THEN
        v_actions := v_actions || '[{"type": "exercise", "title": "Try a quick exercise", "priority": 2}]'::jsonb;
    END IF;
    IF v_days_since_circle > 3 THEN
        v_actions := v_actions || '[{"type": "circle", "title": "Check in with your circle", "priority": 3}]'::jsonb;
    END IF;

    -- Get recommended exercise IDs (breathing/grounding for low mood, any for others)
    SELECT ARRAY_AGG(id) INTO v_exercise_ids
    FROM (
        SELECT id FROM exercises
        WHERE CASE
            WHEN v_mood_context = 'low' THEN type IN ('breathing', 'grounding')
            ELSE TRUE
        END
        AND NOT is_premium
        ORDER BY RANDOM()
        LIMIT 3
    ) e;

    RETURN jsonb_build_object(
        'today_mood', v_today_mood,
        'mood_trend', v_mood_trend,
        'consecutive_low_mood_days', COALESCE(v_low_mood_days, 0),
        'days_since_exercise', COALESCE(v_days_since_exercise, 999),
        'days_since_circle_checkin', COALESCE(v_days_since_circle, 999),
        'quest_completed_today', COALESCE(v_quest_done, false),
        'mood_context', v_mood_context,
        'show_crisis_support', COALESCE(v_show_crisis, false),
        'supportive_message', v_message,
        'recommended_actions', COALESCE(v_actions, '[]'::jsonb),
        'recommended_exercise_ids', COALESCE(v_exercise_ids, ARRAY[]::uuid[])
    );
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_home_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_home_context(uuid) TO service_role;
