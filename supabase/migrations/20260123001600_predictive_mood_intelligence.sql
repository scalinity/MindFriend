-- Predictive Mood Intelligence
-- Adds ML-based mood prediction and preemptive intervention system
-- Tables: mood_predictions, prediction_models, preemptive_interventions

-- =====================================================
-- Table: mood_predictions
-- Stores daily mood predictions with contributing factors
-- =====================================================
CREATE TABLE IF NOT EXISTS public.mood_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    predicted_for DATE NOT NULL,
    predicted_mood DECIMAL(3,1) NOT NULL CHECK (predicted_mood >= 1 AND predicted_mood <= 10),
    confidence DECIMAL(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    factors JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- Example factors: [{"factor": "sleep_deficit", "impact": -1.2, "description": "Poor sleep"}]
    model_version VARCHAR(32) NOT NULL DEFAULT 'v1.0-regression',
    features_used JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- Stores raw feature values used: {sleep_hours: 5.5, steps: 3200, mood_avg_7d: 3.2}
    actual_mood DECIMAL(3,1) CHECK (actual_mood IS NULL OR (actual_mood >= 1 AND actual_mood <= 10)),
    prediction_accuracy DECIMAL(3,2) CHECK (prediction_accuracy IS NULL OR (prediction_accuracy >= 0 AND prediction_accuracy <= 1)),
    notification_sent BOOLEAN NOT NULL DEFAULT false,
    notification_sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, predicted_for)
);

ALTER TABLE public.mood_predictions OWNER TO postgres;
COMMENT ON TABLE public.mood_predictions IS 'Daily mood predictions with ML-based forecasting';

-- Indexes for mood_predictions
CREATE INDEX IF NOT EXISTS idx_mood_predictions_user_date
    ON public.mood_predictions(user_id, predicted_for DESC);
CREATE INDEX IF NOT EXISTS idx_mood_predictions_pending
    ON public.mood_predictions(user_id, predicted_for)
    WHERE actual_mood IS NULL;
CREATE INDEX IF NOT EXISTS idx_mood_predictions_accuracy
    ON public.mood_predictions(user_id, prediction_accuracy)
    WHERE prediction_accuracy IS NOT NULL;

-- =====================================================
-- Table: prediction_models
-- Stores user-specific or global model weights
-- =====================================================
CREATE TABLE IF NOT EXISTS public.prediction_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    -- NULL user_id = global default model
    model_version VARCHAR(32) NOT NULL,
    feature_weights JSONB NOT NULL DEFAULT '{
        "sleep_hours": 0.25,
        "steps_yesterday": 0.15,
        "mood_avg_7d": 0.30,
        "mood_trend_7d": 0.15,
        "day_of_week": 0.10,
        "exercise_minutes": 0.05
    }'::jsonb,
    accuracy_score DECIMAL(3,2) CHECK (accuracy_score IS NULL OR (accuracy_score >= 0 AND accuracy_score <= 1)),
    predictions_count INT NOT NULL DEFAULT 0,
    last_trained_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.prediction_models OWNER TO postgres;
COMMENT ON TABLE public.prediction_models IS 'ML model weights for mood prediction (per-user or global)';

-- Insert global default model
INSERT INTO public.prediction_models (user_id, model_version, feature_weights, accuracy_score)
VALUES (
    NULL,
    'v1.0-regression',
    '{
        "sleep_hours": 0.25,
        "steps_yesterday": 0.15,
        "mood_avg_7d": 0.30,
        "mood_trend_7d": 0.15,
        "day_of_week": 0.10,
        "exercise_minutes": 0.05
    }'::jsonb,
    0.70
)
ON CONFLICT DO NOTHING;

-- Index for prediction_models
CREATE INDEX IF NOT EXISTS idx_prediction_models_user
    ON public.prediction_models(user_id);

-- =====================================================
-- Table: preemptive_interventions
-- Stores intervention suggestions when low mood predicted
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
    -- User feedback: 'helpful', 'not_helpful', 'started_exercise', etc.
    response_recorded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.preemptive_interventions OWNER TO postgres;
COMMENT ON TABLE public.preemptive_interventions IS 'Preemptive interventions for predicted low mood days';

-- Indexes for preemptive_interventions
CREATE INDEX IF NOT EXISTS idx_interventions_user_status
    ON public.preemptive_interventions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_interventions_prediction
    ON public.preemptive_interventions(prediction_id);
CREATE INDEX IF NOT EXISTS idx_interventions_pending
    ON public.preemptive_interventions(user_id, created_at DESC)
    WHERE status = 'pending';

-- =====================================================
-- RLS Policies
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE public.mood_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prediction_models ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.preemptive_interventions ENABLE ROW LEVEL SECURITY;

-- mood_predictions policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'mood_predictions' AND policyname = 'Users can read own predictions'
    ) THEN
        CREATE POLICY "Users can read own predictions"
            ON public.mood_predictions FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'mood_predictions' AND policyname = 'Service role can manage predictions'
    ) THEN
        CREATE POLICY "Service role can manage predictions"
            ON public.mood_predictions FOR ALL
            USING (auth.role() = 'service_role');
    END IF;
END $$;

-- prediction_models policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'prediction_models' AND policyname = 'Users can read own model or global'
    ) THEN
        CREATE POLICY "Users can read own model or global"
            ON public.prediction_models FOR SELECT
            USING (user_id IS NULL OR auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'prediction_models' AND policyname = 'Service role can manage models'
    ) THEN
        CREATE POLICY "Service role can manage models"
            ON public.prediction_models FOR ALL
            USING (auth.role() = 'service_role');
    END IF;
END $$;

-- preemptive_interventions policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'preemptive_interventions' AND policyname = 'Users can read own interventions'
    ) THEN
        CREATE POLICY "Users can read own interventions"
            ON public.preemptive_interventions FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'preemptive_interventions' AND policyname = 'Users can update own interventions'
    ) THEN
        CREATE POLICY "Users can update own interventions"
            ON public.preemptive_interventions FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'preemptive_interventions' AND policyname = 'Service role can manage interventions'
    ) THEN
        CREATE POLICY "Service role can manage interventions"
            ON public.preemptive_interventions FOR ALL
            USING (auth.role() = 'service_role');
    END IF;
END $$;

-- =====================================================
-- Helper Functions
-- =====================================================

-- Function to get users eligible for prediction (14+ mood entries)
CREATE OR REPLACE FUNCTION public.get_prediction_eligible_users(
    p_target_hour INT DEFAULT 6,
    p_hour_window INT DEFAULT 2
)
RETURNS TABLE (
    user_id UUID,
    timezone TEXT,
    mood_count BIGINT,
    last_mood_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.user_id,
        COALESCE(us.timezone, 'UTC') as timezone,
        COUNT(m.id) as mood_count,
        MAX(m.created_at) as last_mood_at
    FROM moods m
    LEFT JOIN user_settings us ON us.user_id = m.user_id
    WHERE m.created_at >= NOW() - INTERVAL '90 days'
    GROUP BY m.user_id, us.timezone
    HAVING COUNT(m.id) >= 14
    -- Filter by local time (users whose local hour is within target window)
    AND EXTRACT(HOUR FROM NOW() AT TIME ZONE COALESCE(us.timezone, 'UTC'))
        BETWEEN p_target_hour AND p_target_hour + p_hour_window;
END;
$$;

-- Function to get prediction features for a user
CREATE OR REPLACE FUNCTION public.get_prediction_features(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_features JSONB := '{}'::jsonb;
    v_mood_avg_7d DECIMAL;
    v_mood_avg_14d DECIMAL;
    v_mood_trend_7d DECIMAL;
    v_prev_mood INT;
    v_sleep_hours DECIMAL;
    v_steps_yesterday INT;
    v_exercise_minutes INT;
    v_day_of_week INT;
    v_hour_of_day INT;
    v_streak_days INT;
    v_timezone TEXT;
BEGIN
    -- Get user timezone
    SELECT COALESCE(timezone, 'UTC') INTO v_timezone
    FROM user_settings
    WHERE user_settings.user_id = p_user_id;

    -- 7-day mood average (moods are 1-5, we'll normalize later)
    SELECT AVG(mood_score) INTO v_mood_avg_7d
    FROM moods
    WHERE moods.user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '7 days';

    -- 14-day mood average
    SELECT AVG(mood_score) INTO v_mood_avg_14d
    FROM moods
    WHERE moods.user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '14 days';

    -- Mood trend (7-day slope using linear regression)
    SELECT
        COALESCE(
            regr_slope(
                mood_score::float,
                EXTRACT(EPOCH FROM created_at)::float
            ) * 86400 * 7, -- Scale to weekly change
            0
        ) INTO v_mood_trend_7d
    FROM moods
    WHERE moods.user_id = p_user_id
    AND created_at >= NOW() - INTERVAL '7 days';

    -- Previous mood (yesterday or most recent)
    SELECT mood_score INTO v_prev_mood
    FROM moods
    WHERE moods.user_id = p_user_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Sleep hours from biometric_daily_summaries (if available)
    SELECT sleep_total_hours INTO v_sleep_hours
    FROM biometric_daily_summaries
    WHERE biometric_daily_summaries.user_id = p_user_id
    AND summary_date = ((NOW() AT TIME ZONE v_timezone) - INTERVAL '1 day')::date
    LIMIT 1;

    -- Steps yesterday from biometric_daily_summaries (if available)
    SELECT step_count INTO v_steps_yesterday
    FROM biometric_daily_summaries
    WHERE biometric_daily_summaries.user_id = p_user_id
    AND summary_date = ((NOW() AT TIME ZONE v_timezone) - INTERVAL '1 day')::date
    LIMIT 1;

    -- Exercise minutes in last 7 days
    SELECT COALESCE(SUM(duration_minutes), 0) INTO v_exercise_minutes
    FROM exercise_sessions
    WHERE exercise_sessions.user_id = p_user_id
    AND completed_at >= NOW() - INTERVAL '7 days';

    -- Day of week (0 = Sunday, 6 = Saturday)
    SELECT EXTRACT(DOW FROM NOW() AT TIME ZONE v_timezone)::int INTO v_day_of_week;

    -- Hour of day
    SELECT EXTRACT(HOUR FROM NOW() AT TIME ZONE v_timezone)::int INTO v_hour_of_day;

    -- Get streak from profiles
    SELECT COALESCE(streak_days, 0) INTO v_streak_days
    FROM profiles
    WHERE profiles.id = p_user_id;

    -- Build features JSON
    v_features := jsonb_build_object(
        'mood_avg_7d', COALESCE(v_mood_avg_7d, 3),
        'mood_avg_14d', COALESCE(v_mood_avg_14d, 3),
        'mood_trend_7d', COALESCE(v_mood_trend_7d, 0),
        'previous_mood', COALESCE(v_prev_mood, 3),
        'sleep_hours', v_sleep_hours,
        'steps_yesterday', v_steps_yesterday,
        'exercise_minutes_7d', COALESCE(v_exercise_minutes, 0),
        'day_of_week', v_day_of_week,
        'hour_of_day', v_hour_of_day,
        'streak_days', COALESCE(v_streak_days, 0),
        'has_sleep_data', v_sleep_hours IS NOT NULL,
        'has_steps_data', v_steps_yesterday IS NOT NULL,
        'timezone', v_timezone
    );

    RETURN v_features;
END;
$$;

-- Function to update prediction accuracy after mood is logged
CREATE OR REPLACE FUNCTION public.update_prediction_accuracy()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_predicted_mood DECIMAL;
    v_actual_mood_scaled DECIMAL;
    v_accuracy DECIMAL;
BEGIN
    -- Convert actual mood from 1-5 scale to 1-10 scale
    v_actual_mood_scaled := NEW.mood_score * 2;

    -- Find today's prediction for this user
    SELECT predicted_mood INTO v_predicted_mood
    FROM mood_predictions
    WHERE mood_predictions.user_id = NEW.user_id
    AND predicted_for = NEW.local_date
    AND actual_mood IS NULL
    LIMIT 1;

    IF v_predicted_mood IS NOT NULL THEN
        -- Calculate accuracy: 1 - (|predicted - actual| / 9)
        -- 9 is max possible error on 1-10 scale
        v_accuracy := GREATEST(0, 1 - (ABS(v_predicted_mood - v_actual_mood_scaled) / 9));

        -- Update prediction with actual mood and accuracy
        UPDATE mood_predictions
        SET
            actual_mood = v_actual_mood_scaled,
            prediction_accuracy = v_accuracy,
            updated_at = NOW()
        WHERE mood_predictions.user_id = NEW.user_id
        AND predicted_for = NEW.local_date
        AND actual_mood IS NULL;
    END IF;

    RETURN NEW;
END;
$$;

-- Trigger to update prediction accuracy when mood is logged
DROP TRIGGER IF EXISTS trigger_update_prediction_accuracy ON public.moods;
CREATE TRIGGER trigger_update_prediction_accuracy
    AFTER INSERT ON public.moods
    FOR EACH ROW
    EXECUTE FUNCTION public.update_prediction_accuracy();

-- =====================================================
-- Cron job setup (requires pg_cron extension)
-- Runs predict-mood function every day at 6 AM UTC
-- =====================================================
-- Note: Actual cron is set up in Edge Function, this is for reference
-- SELECT cron.schedule(
--     'predict-mood-daily',
--     '0 6 * * *',
--     $$SELECT net.http_post(
--         url := 'https://<project>.supabase.co/functions/v1/predict-mood',
--         headers := '{"Authorization": "Bearer <service_role_key>"}'::jsonb
--     )$$
-- );
