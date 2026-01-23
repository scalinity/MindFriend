-- Micro-Moments Feature Migration
-- Enables 15-60 second wellness interventions: breathing, check-ins, grounding, movement

-- ============================================================================
-- TABLES
-- ============================================================================

-- Micro-moment templates (breathing, grounding, movement exercises)
CREATE TABLE IF NOT EXISTS micro_moment_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL CHECK (type IN (
        'breathing', 'check_in', 'grounding',
        'movement', 'transition', 'gratitude'
    )),

    -- Content
    title TEXT NOT NULL,
    description TEXT,
    duration_seconds INTEGER NOT NULL CHECK (duration_seconds > 0 AND duration_seconds <= 120),
    instructions JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- Assets
    animation_type TEXT CHECK (animation_type IN (
        'breathing_circle', 'body_scan', 'countdown', 'pulse', 'wave'
    )),
    audio_url TEXT,
    haptic_pattern JSONB,

    -- Targeting
    suggested_contexts TEXT[] DEFAULT ARRAY[]::TEXT[],
    energy_effect TEXT CHECK (energy_effect IN ('calming', 'energizing', 'neutral')),

    -- Access
    is_premium BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- User micro-moment completions
CREATE TABLE IF NOT EXISTS micro_moment_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES micro_moment_templates(id) ON DELETE CASCADE,

    -- Context
    trigger_source TEXT CHECK (trigger_source IN (
        'manual', 'notification', 'widget', 'siri', 'watch', 'suggestion'
    )),
    context TEXT,

    -- Completion
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    duration_actual_seconds INTEGER,
    completed BOOLEAN NOT NULL DEFAULT false,

    -- Feedback
    felt_helpful BOOLEAN,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Quick check-in entries (mood, energy, gratitude, intention)
CREATE TABLE IF NOT EXISTS quick_check_ins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    -- Check-in type
    type TEXT NOT NULL CHECK (type IN (
        'mood', 'energy', 'gratitude', 'intention', 'stress_level'
    )),

    -- Values
    value_numeric INTEGER CHECK (value_numeric BETWEEN 1 AND 5),
    value_emoji TEXT,
    value_text TEXT,
    context_tags TEXT[] DEFAULT ARRAY[]::TEXT[],

    -- Metadata
    source TEXT NOT NULL DEFAULT 'app' CHECK (source IN ('app', 'widget', 'watch', 'notification')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Micro-moment streaks (separate from main quest streaks)
CREATE TABLE IF NOT EXISTS micro_streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    -- Current streak
    current_streak INTEGER NOT NULL DEFAULT 0,
    longest_streak INTEGER NOT NULL DEFAULT 0,

    -- Last activity
    last_micro_date DATE,

    -- Statistics
    total_micro_moments INTEGER NOT NULL DEFAULT 0,
    total_check_ins INTEGER NOT NULL DEFAULT 0,
    total_seconds_practiced INTEGER NOT NULL DEFAULT 0,

    -- Achievements
    achievements_unlocked TEXT[] DEFAULT ARRAY[]::TEXT[],

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id)
);

-- Smart delivery preferences
CREATE TABLE IF NOT EXISTS micro_delivery_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    -- Timing preferences
    morning_checkin_enabled BOOLEAN NOT NULL DEFAULT true,
    morning_checkin_time TIME DEFAULT '08:00',

    evening_checkin_enabled BOOLEAN NOT NULL DEFAULT true,
    evening_checkin_time TIME DEFAULT '20:00',

    -- Context triggers
    pre_meeting_reminder BOOLEAN NOT NULL DEFAULT false,
    pre_meeting_minutes INTEGER NOT NULL DEFAULT 5,

    post_meeting_suggestion BOOLEAN NOT NULL DEFAULT false,

    -- Frequency limits
    max_suggestions_per_day INTEGER NOT NULL DEFAULT 5,
    min_hours_between_suggestions NUMERIC(3,1) NOT NULL DEFAULT 2.0,

    -- Preferences
    preferred_types TEXT[] DEFAULT ARRAY[]::TEXT[],
    preferred_durations INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    silent_mode_only BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Templates
CREATE INDEX IF NOT EXISTS idx_micro_templates_type ON micro_moment_templates(type);
CREATE INDEX IF NOT EXISTS idx_micro_templates_duration ON micro_moment_templates(duration_seconds);
CREATE INDEX IF NOT EXISTS idx_micro_templates_context ON micro_moment_templates USING GIN (suggested_contexts);
CREATE INDEX IF NOT EXISTS idx_micro_templates_active ON micro_moment_templates(is_active) WHERE is_active = true;

-- Completions
CREATE INDEX IF NOT EXISTS idx_micro_completions_user ON micro_moment_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_micro_completions_date ON micro_moment_completions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_micro_completions_template ON micro_moment_completions(template_id);
CREATE INDEX IF NOT EXISTS idx_micro_completions_user_date ON micro_moment_completions(user_id, created_at DESC);

-- Check-ins
CREATE INDEX IF NOT EXISTS idx_quick_checkins_user_date ON quick_check_ins(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quick_checkins_type ON quick_check_ins(user_id, type, created_at DESC);

-- Streaks
CREATE INDEX IF NOT EXISTS idx_micro_streaks_user ON micro_streaks(user_id);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE micro_moment_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE micro_moment_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE quick_check_ins ENABLE ROW LEVEL SECURITY;
ALTER TABLE micro_streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE micro_delivery_preferences ENABLE ROW LEVEL SECURITY;

-- Templates are publicly readable (when active)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Templates are public read' AND tablename = 'micro_moment_templates') THEN
        CREATE POLICY "Templates are public read" ON micro_moment_templates
            FOR SELECT USING (is_active = true);
    END IF;
END $$;

-- Users manage own micro completions
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own micro completions' AND tablename = 'micro_moment_completions') THEN
        CREATE POLICY "Users manage own micro completions" ON micro_moment_completions
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users manage own check-ins
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own check-ins' AND tablename = 'quick_check_ins') THEN
        CREATE POLICY "Users manage own check-ins" ON quick_check_ins
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users manage own micro streaks
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own micro streaks' AND tablename = 'micro_streaks') THEN
        CREATE POLICY "Users manage own micro streaks" ON micro_streaks
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- Users manage own delivery preferences
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own delivery preferences' AND tablename = 'micro_delivery_preferences') THEN
        CREATE POLICY "Users manage own delivery preferences" ON micro_delivery_preferences
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- SEED DATA - MICRO MOMENT TEMPLATES
-- ============================================================================

-- Breathing Exercises (15-60 seconds)
INSERT INTO micro_moment_templates (name, slug, type, title, description, duration_seconds, instructions, animation_type, suggested_contexts, energy_effect, is_premium, sort_order)
VALUES
    -- Free breathing exercises
    ('3-breath-reset', '3-breath-reset', 'breathing', '3 Deep Breaths', 'Quick calming reset in 15 seconds', 15,
     '[{"id":"1","step":1,"text":"Breathe in slowly...","duration_seconds":4,"action":"inhale"},{"id":"2","step":2,"text":"Breathe out...","duration_seconds":4,"action":"exhale"},{"id":"3","step":3,"text":"Breathe in...","duration_seconds":4,"action":"inhale"},{"id":"4","step":4,"text":"And out... Great job!","duration_seconds":3,"action":"exhale"}]'::JSONB,
     'breathing_circle', ARRAY['stress', 'morning', 'pre_meeting'], 'calming', false, 1),

    ('box-breath-30', 'box-breath-30', 'breathing', 'Box Breathing', '4-count pattern: inhale-hold-exhale-hold', 30,
     '[{"id":"1","step":1,"text":"Inhale 1...2...3...4","duration_seconds":4,"action":"inhale"},{"id":"2","step":2,"text":"Hold 1...2...3...4","duration_seconds":4,"action":"hold"},{"id":"3","step":3,"text":"Exhale 1...2...3...4","duration_seconds":4,"action":"exhale"},{"id":"4","step":4,"text":"Hold 1...2...3...4","duration_seconds":4,"action":"hold"},{"id":"5","step":5,"text":"Inhale 1...2...3...4","duration_seconds":4,"action":"inhale"},{"id":"6","step":6,"text":"Hold 1...2...3...4","duration_seconds":4,"action":"hold"},{"id":"7","step":7,"text":"Exhale and relax...","duration_seconds":6,"action":"exhale"}]'::JSONB,
     'breathing_circle', ARRAY['stress', 'anxiety', 'pre_meeting'], 'calming', false, 2),

    ('calm-minute', 'calm-minute', 'breathing', 'One Minute Calm', 'Extended breathing with visual guide', 60,
     '[{"id":"1","step":1,"text":"Find a comfortable position","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Breathe in deeply...","duration_seconds":5,"action":"inhale"},{"id":"3","step":3,"text":"And slowly release...","duration_seconds":5,"action":"exhale"},{"id":"4","step":4,"text":"Again, breathe in...","duration_seconds":5,"action":"inhale"},{"id":"5","step":5,"text":"Let it go...","duration_seconds":5,"action":"exhale"},{"id":"6","step":6,"text":"Breathe in peace...","duration_seconds":5,"action":"inhale"},{"id":"7","step":7,"text":"Release tension...","duration_seconds":5,"action":"exhale"},{"id":"8","step":8,"text":"One more deep breath in...","duration_seconds":5,"action":"inhale"},{"id":"9","step":9,"text":"Exhale completely...","duration_seconds":5,"action":"exhale"},{"id":"10","step":10,"text":"Return to your day, refreshed","duration_seconds":10,"action":"observe"}]'::JSONB,
     'breathing_circle', ARRAY['evening', 'stress', 'break'], 'calming', false, 3),

    -- Premium breathing
    ('energize-breath', 'energize-breath', 'breathing', 'Energizing Breath', 'Quick breath to boost energy', 20,
     '[{"id":"1","step":1,"text":"Inhale quickly!","duration_seconds":2,"action":"inhale"},{"id":"2","step":2,"text":"Exhale sharply!","duration_seconds":2,"action":"exhale"},{"id":"3","step":3,"text":"Inhale!","duration_seconds":2,"action":"inhale"},{"id":"4","step":4,"text":"Exhale!","duration_seconds":2,"action":"exhale"},{"id":"5","step":5,"text":"Inhale!","duration_seconds":2,"action":"inhale"},{"id":"6","step":6,"text":"Exhale!","duration_seconds":2,"action":"exhale"},{"id":"7","step":7,"text":"Deep breath in...","duration_seconds":4,"action":"inhale"},{"id":"8","step":8,"text":"Slow release...","duration_seconds":4,"action":"exhale"}]'::JSONB,
     'pulse', ARRAY['morning', 'afternoon', 'energy'], 'energizing', true, 4),

    -- Grounding Exercises
    ('5-4-3-2-1-express', '5-4-3-2-1-express', 'grounding', '5-4-3-2-1 Express', 'Quick sensory grounding technique', 30,
     '[{"id":"1","step":1,"text":"Name 5 things you can see","duration_seconds":6,"action":"observe"},{"id":"2","step":2,"text":"Name 4 things you can touch","duration_seconds":6,"action":"observe"},{"id":"3","step":3,"text":"Name 3 things you can hear","duration_seconds":6,"action":"observe"},{"id":"4","step":4,"text":"Name 2 things you can smell","duration_seconds":6,"action":"observe"},{"id":"5","step":5,"text":"Name 1 thing you can taste","duration_seconds":6,"action":"observe"}]'::JSONB,
     'countdown', ARRAY['anxiety', 'stress', 'grounding'], 'calming', false, 10),

    ('name-3-things', 'name-3-things', 'grounding', 'Name 3 Things', 'Quick cognitive reset', 15,
     '[{"id":"1","step":1,"text":"Name 3 blue things around you","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Name 3 sounds you hear","duration_seconds":5,"action":"observe"},{"id":"3","step":3,"text":"Take a breath. You''re here.","duration_seconds":5,"action":"inhale"}]'::JSONB,
     'countdown', ARRAY['anxiety', 'stress', 'break'], 'calming', false, 11),

    ('body-scan-flash', 'body-scan-flash', 'grounding', 'Body Scan Flash', '15-second body awareness', 15,
     '[{"id":"1","step":1,"text":"Notice your feet on the ground","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Relax your shoulders","duration_seconds":5,"action":"observe"},{"id":"3","step":3,"text":"Soften your jaw","duration_seconds":5,"action":"observe"}]'::JSONB,
     'body_scan', ARRAY['stress', 'tension', 'break'], 'calming', false, 12),

    -- Movement Micro-Breaks
    ('desk-stretch', 'desk-stretch', 'movement', 'Desk Stretch', '30-second shoulder and neck release', 30,
     '[{"id":"1","step":1,"text":"Roll shoulders back 3 times","duration_seconds":8,"action":"move"},{"id":"2","step":2,"text":"Roll shoulders forward 3 times","duration_seconds":8,"action":"move"},{"id":"3","step":3,"text":"Gently tilt head left","duration_seconds":7,"action":"move"},{"id":"4","step":4,"text":"Gently tilt head right","duration_seconds":7,"action":"move"}]'::JSONB,
     NULL, ARRAY['break', 'afternoon', 'tension'], 'neutral', false, 20),

    ('posture-reset', 'posture-reset', 'movement', 'Posture Reset', '15-second spinal alignment', 15,
     '[{"id":"1","step":1,"text":"Sit up tall, crown toward ceiling","duration_seconds":5,"action":"move"},{"id":"2","step":2,"text":"Pull shoulders back and down","duration_seconds":5,"action":"move"},{"id":"3","step":3,"text":"Breathe and hold this posture","duration_seconds":5,"action":"inhale"}]'::JSONB,
     NULL, ARRAY['break', 'work', 'posture'], 'neutral', false, 21),

    ('hand-massage', 'hand-massage', 'movement', 'Hand Massage', '20-second tension release', 20,
     '[{"id":"1","step":1,"text":"Press thumb into opposite palm","duration_seconds":5,"action":"move"},{"id":"2","step":2,"text":"Massage in circles","duration_seconds":5,"action":"move"},{"id":"3","step":3,"text":"Switch hands","duration_seconds":5,"action":"move"},{"id":"4","step":4,"text":"Shake both hands gently","duration_seconds":5,"action":"move"}]'::JSONB,
     NULL, ARRAY['break', 'tension', 'stress'], 'calming', false, 22),

    -- Transition Rituals
    ('work-home-shift', 'work-home-shift', 'transition', 'Work → Home', '60-second mental shift exercise', 60,
     '[{"id":"1","step":1,"text":"Close your eyes. Work is done.","duration_seconds":10,"action":"observe"},{"id":"2","step":2,"text":"Take 3 deep breaths...","duration_seconds":15,"action":"inhale"},{"id":"3","step":3,"text":"Think of one good thing from today","duration_seconds":10,"action":"observe"},{"id":"4","step":4,"text":"Set one intention for your evening","duration_seconds":15,"action":"observe"},{"id":"5","step":5,"text":"Open your eyes. Welcome home.","duration_seconds":10,"action":"observe"}]'::JSONB,
     'breathing_circle', ARRAY['evening', 'transition', 'work'], 'calming', false, 30),

    ('meeting-prep', 'meeting-prep', 'transition', 'Meeting Prep', '30-second centering before calls', 30,
     '[{"id":"1","step":1,"text":"Take a centering breath","duration_seconds":8,"action":"inhale"},{"id":"2","step":2,"text":"Set your intention: Be present","duration_seconds":7,"action":"observe"},{"id":"3","step":3,"text":"Release any tension","duration_seconds":8,"action":"exhale"},{"id":"4","step":4,"text":"You''re ready. Let''s go.","duration_seconds":7,"action":"observe"}]'::JSONB,
     'pulse', ARRAY['pre_meeting', 'work', 'focus'], 'neutral', false, 31),

    ('sleep-wind-down', 'sleep-wind-down', 'transition', 'Sleep Wind-Down', '45-second pre-sleep relaxation', 45,
     '[{"id":"1","step":1,"text":"Close your eyes","duration_seconds":5,"action":"observe"},{"id":"2","step":2,"text":"Breathe in peace...","duration_seconds":8,"action":"inhale"},{"id":"3","step":3,"text":"Release the day...","duration_seconds":8,"action":"exhale"},{"id":"4","step":4,"text":"Let your body sink into the bed","duration_seconds":8,"action":"observe"},{"id":"5","step":5,"text":"Breathe in calm...","duration_seconds":8,"action":"inhale"},{"id":"6","step":6,"text":"Sleep well...","duration_seconds":8,"action":"exhale"}]'::JSONB,
     'breathing_circle', ARRAY['evening', 'sleep', 'transition'], 'calming', false, 32),

    -- Gratitude Moments
    ('gratitude-moment', 'gratitude-moment', 'gratitude', 'Gratitude Moment', 'Quick appreciation practice', 20,
     '[{"id":"1","step":1,"text":"Think of one thing you''re grateful for","duration_seconds":10,"action":"observe"},{"id":"2","step":2,"text":"Feel that gratitude in your heart","duration_seconds":5,"action":"observe"},{"id":"3","step":3,"text":"Smile. Carry this with you.","duration_seconds":5,"action":"observe"}]'::JSONB,
     'pulse', ARRAY['morning', 'evening', 'gratitude'], 'energizing', false, 40)

ON CONFLICT (slug) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    duration_seconds = EXCLUDED.duration_seconds,
    instructions = EXCLUDED.instructions,
    animation_type = EXCLUDED.animation_type,
    suggested_contexts = EXCLUDED.suggested_contexts,
    energy_effect = EXCLUDED.energy_effect,
    is_premium = EXCLUDED.is_premium,
    sort_order = EXCLUDED.sort_order,
    updated_at = NOW();

-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Function to update micro streak
CREATE OR REPLACE FUNCTION update_micro_streak()
RETURNS TRIGGER AS $$
DECLARE
    v_last_date DATE;
    v_yesterday DATE;
    v_today DATE;
    v_current_streak INTEGER;
BEGIN
    v_today := CURRENT_DATE;
    v_yesterday := v_today - INTERVAL '1 day';

    -- Get or create streak record
    SELECT last_micro_date, current_streak INTO v_last_date, v_current_streak
    FROM micro_streaks
    WHERE user_id = NEW.user_id;

    IF NOT FOUND THEN
        -- Create new streak record
        INSERT INTO micro_streaks (user_id, current_streak, longest_streak, last_micro_date, total_micro_moments, total_seconds_practiced, achievements_unlocked)
        VALUES (NEW.user_id, 1, 1, v_today, 1, COALESCE(NEW.duration_actual_seconds, 0), ARRAY['first_micro']);
    ELSIF v_last_date = v_yesterday THEN
        -- Continuing streak
        UPDATE micro_streaks
        SET current_streak = current_streak + 1,
            longest_streak = GREATEST(longest_streak, current_streak + 1),
            last_micro_date = v_today,
            total_micro_moments = total_micro_moments + 1,
            total_seconds_practiced = total_seconds_practiced + COALESCE(NEW.duration_actual_seconds, 0),
            achievements_unlocked = CASE
                WHEN current_streak + 1 = 7 AND NOT ('week_streak' = ANY(achievements_unlocked)) THEN array_append(achievements_unlocked, 'week_streak')
                WHEN current_streak + 1 = 30 AND NOT ('month_streak' = ANY(achievements_unlocked)) THEN array_append(achievements_unlocked, 'month_streak')
                ELSE achievements_unlocked
            END,
            updated_at = NOW()
        WHERE user_id = NEW.user_id;
    ELSIF v_last_date = v_today THEN
        -- Same day, just update totals
        UPDATE micro_streaks
        SET total_micro_moments = total_micro_moments + 1,
            total_seconds_practiced = total_seconds_practiced + COALESCE(NEW.duration_actual_seconds, 0),
            achievements_unlocked = CASE
                WHEN total_micro_moments + 1 = 100 AND NOT ('micro_century' = ANY(achievements_unlocked)) THEN array_append(achievements_unlocked, 'micro_century')
                ELSE achievements_unlocked
            END,
            updated_at = NOW()
        WHERE user_id = NEW.user_id;
    ELSE
        -- Streak broken, reset
        UPDATE micro_streaks
        SET current_streak = 1,
            last_micro_date = v_today,
            total_micro_moments = total_micro_moments + 1,
            total_seconds_practiced = total_seconds_practiced + COALESCE(NEW.duration_actual_seconds, 0),
            updated_at = NOW()
        WHERE user_id = NEW.user_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for micro-moment completions
DROP TRIGGER IF EXISTS trg_update_micro_streak ON micro_moment_completions;
CREATE TRIGGER trg_update_micro_streak
    AFTER INSERT ON micro_moment_completions
    FOR EACH ROW
    WHEN (NEW.completed = true)
    EXECUTE FUNCTION update_micro_streak();

-- Function to update check-in count in streak
CREATE OR REPLACE FUNCTION update_checkin_count()
RETURNS TRIGGER AS $$
BEGIN
    -- Upsert streak record with check-in count
    INSERT INTO micro_streaks (user_id, current_streak, longest_streak, total_check_ins)
    VALUES (NEW.user_id, 0, 0, 1)
    ON CONFLICT (user_id) DO UPDATE
    SET total_check_ins = micro_streaks.total_check_ins + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for quick check-ins
DROP TRIGGER IF EXISTS trg_update_checkin_count ON quick_check_ins;
CREATE TRIGGER trg_update_checkin_count
    AFTER INSERT ON quick_check_ins
    FOR EACH ROW
    EXECUTE FUNCTION update_checkin_count();
