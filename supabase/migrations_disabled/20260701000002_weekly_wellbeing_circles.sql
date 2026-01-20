-- Weekly Wellbeing Check + Circle Habits Feature Migration
-- Feature: Weekly Wellbeing Check, Circle Templates, Recaps, Nudges
-- Created: 2026-01-20
-- Note: Tables may already exist from previous features - we add missing objects

-- ============================================
-- Weekly Wellbeing Checks (add missing objects)
-- ============================================

-- RLS if not already enabled
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'weekly_wellbeing_checks') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'weekly_wellbeing_checks' AND rowsecurity = true) THEN
            ALTER TABLE weekly_wellbeing_checks ENABLE ROW LEVEL SECURITY;
        END IF;
    END IF;
END;
$body$;

-- Create policy if not exists
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'weekly_wellbeing_checks') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'weekly_wellbeing_checks' AND policyname = 'Users manage own weekly checks') THEN
            CREATE POLICY "Users manage own weekly checks"
                ON weekly_wellbeing_checks FOR ALL
                USING (auth.uid() = user_id);
        END IF;
    END IF;
END;
$body$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_weekly_wellbeing_user_week ON weekly_wellbeing_checks(user_id, week_start DESC);
CREATE INDEX IF NOT EXISTS idx_weekly_wellbeing_created_at ON weekly_wellbeing_checks(created_at DESC);

-- ============================================
-- Circle Templates (add missing objects)
-- ============================================

-- RLS if not already enabled
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_templates') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'circle_templates' AND rowsecurity = true) THEN
            ALTER TABLE circle_templates ENABLE ROW LEVEL SECURITY;
        END IF;
    END IF;
END;
$body$;

-- Only create policies if they don't exist
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_templates') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_templates' AND policyname = 'Circle admins can manage templates') THEN
            CREATE POLICY "Circle admins can manage templates"
                ON circle_templates FOR ALL
                USING (
                    EXISTS (
                        SELECT 1 FROM circles
                        WHERE id = circle_templates.circle_id
                        AND created_by = auth.uid()
                    )
                );
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_templates' AND policyname = 'Circle members can view templates') THEN
            CREATE POLICY "Circle members can view templates"
                ON circle_templates FOR SELECT
                USING (
                    EXISTS (
                        SELECT 1 FROM circle_members
                        WHERE circle_id = circle_templates.circle_id
                        AND user_id = auth.uid()
                    )
                );
        END IF;
    END IF;
END;
$body$;

-- Index
CREATE INDEX IF NOT EXISTS idx_circle_templates_circle_id ON circle_templates(circle_id);

-- ============================================
-- Circle Nudges (add missing objects)
-- ============================================

-- RLS if not already enabled
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_nudges') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'circle_nudges' AND rowsecurity = true) THEN
            ALTER TABLE circle_nudges ENABLE ROW LEVEL SECURITY;
        END IF;
    END IF;
END;
$body$;

-- Only create policies if they don't exist
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_nudges') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_nudges' AND policyname = 'Users can view own nudges') THEN
            CREATE POLICY "Users can view own nudges"
                ON circle_nudges FOR SELECT
                USING (auth.uid() = recipient_id OR auth.uid() = sender_id);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_nudges' AND policyname = 'Circle members can send nudges') THEN
            CREATE POLICY "Circle members can send nudges"
                ON circle_nudges FOR INSERT
                WITH CHECK (
                    EXISTS (
                        SELECT 1 FROM circle_members
                        WHERE circle_id = circle_nudges.circle_id
                        AND user_id = auth.uid()
                    )
                    AND sender_id = auth.uid()
                    AND sender_id != recipient_id
                );
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_nudges' AND policyname = 'Users can update own nudges') THEN
            CREATE POLICY "Users can update own nudges (mark read)"
                ON circle_nudges FOR UPDATE
                USING (auth.uid() = recipient_id);
        END IF;
    END IF;
END;
$body$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_circle_nudges_recipient ON circle_nudges(recipient_id, is_read);
CREATE INDEX IF NOT EXISTS idx_circle_nudges_circle ON circle_nudges(circle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_circle_nudges_sender ON circle_nudges(sender_id, created_at DESC);

-- ============================================
-- Circle Nudge Settings (add missing objects)
-- ============================================

DO $body$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_nudge_settings') THEN
        CREATE TABLE circle_nudge_settings (
            circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
            can_send BOOLEAN DEFAULT true,
            can_receive BOOLEAN DEFAULT true,
            muted_until TIMESTAMPTZ,
            UNIQUE (circle_id, user_id)
        );
    END IF;
END;
$body$;

-- RLS
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_nudge_settings') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'circle_nudge_settings' AND rowsecurity = true) THEN
            ALTER TABLE circle_nudge_settings ENABLE ROW LEVEL SECURITY;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_nudge_settings' AND policyname = 'Users can manage own nudge settings') THEN
            CREATE POLICY "Users can manage own nudge settings"
                ON circle_nudge_settings FOR ALL
                USING (auth.uid() = user_id);
        END IF;
    END IF;
END;
$body$;

-- ============================================
-- Circle Recaps (add missing objects)
-- ============================================

DO $body$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_recaps') THEN
        CREATE TABLE circle_recaps (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
            week_start DATE NOT NULL,
            check_in_count INT NOT NULL DEFAULT 0,
            check_in_change INT NOT NULL DEFAULT 0,
            average_mood DECIMAL(3,2),
            mood_change DECIMAL(3,2),
            top_tags JSONB NOT NULL DEFAULT '[]'::jsonb,
            posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            UNIQUE (circle_id, week_start)
        );
    END IF;
END;
$body$;

-- RLS
DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_recaps') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'circle_recaps' AND rowsecurity = true) THEN
            ALTER TABLE circle_recaps ENABLE ROW LEVEL SECURITY;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_recaps' AND policyname = 'Circle members can view recaps') THEN
            CREATE POLICY "Circle members can view recaps"
                ON circle_recaps FOR SELECT
                USING (
                    EXISTS (
                        SELECT 1 FROM circle_members
                        WHERE circle_id = circle_recaps.circle_id
                        AND user_id = auth.uid()
                    )
                );
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_recaps' AND policyname = 'System can create recaps') THEN
            CREATE POLICY "System can create recaps"
                ON circle_recaps FOR INSERT
                WITH CHECK (true);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'circle_recaps' AND policyname = 'System can update recaps') THEN
            CREATE POLICY "System can update recaps"
                ON circle_recaps FOR UPDATE
                USING (true);
        END IF;
    END IF;
END;
$body$;

-- Index
CREATE INDEX IF NOT EXISTS idx_circle_recaps_circle_week ON circle_recaps(circle_id, week_start DESC);

-- ============================================
-- Updated_at triggers
-- ============================================
CREATE OR REPLACE FUNCTION update_weekly_wellbeing_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'weekly_wellbeing_checks') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trigger_weekly_wellbeing_updated_at') THEN
            CREATE TRIGGER trigger_weekly_wellbeing_updated_at
                BEFORE UPDATE ON weekly_wellbeing_checks
                FOR EACH ROW
                EXECUTE FUNCTION update_weekly_wellbeing_updated_at();
        END IF;
    END IF;
END;
$body$;

CREATE OR REPLACE FUNCTION update_circle_templates_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DO $body$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_templates') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trigger_circle_templates_updated_at') THEN
            CREATE TRIGGER trigger_circle_templates_updated_at
                BEFORE UPDATE ON circle_templates
                FOR EACH ROW
                EXECUTE FUNCTION update_circle_templates_updated_at();
        END IF;
    END IF;
END;
$body$;

-- ============================================
-- Seed default circle templates for existing circles without templates
-- ============================================
DO $body$
DECLARE
    c_id UUID;
    c_created_by UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'circle_templates') THEN
        FOR c_id, c_created_by IN SELECT id, created_by FROM circles LOOP
            -- Check if circle has no templates
            IF NOT EXISTS (SELECT 1 FROM circle_templates WHERE circle_id = c_id) THEN
                -- Template 1: 1 Win, 1 Worry, 1 Need
                INSERT INTO circle_templates (circle_id, template_type, is_active, display_order, created_by)
                VALUES (c_id, 'win_worry_need', true, 0, c_created_by);

                -- Template 2: Energy + Sentence
                INSERT INTO circle_templates (circle_id, template_type, is_active, display_order, created_by)
                VALUES (c_id, 'energy_sentence', true, 1, c_created_by);

                -- Template 3: Gratitude + Intention
                INSERT INTO circle_templates (circle_id, template_type, is_active, display_order, created_by)
                VALUES (c_id, 'gratitude_intention', true, 2, c_created_by);
            END IF;
        END LOOP;
    END IF;
END;
$body$;
