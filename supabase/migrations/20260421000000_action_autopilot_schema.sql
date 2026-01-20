-- Action Autopilot schema (Action plans + items + feedback)

CREATE TABLE IF NOT EXISTS action_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK (source_type IN ('mood_checkin', 'weekly_summary', 'manual')),
  plan_size TEXT NOT NULL CHECK (plan_size IN ('quick', 'standard')),
  local_date TEXT NOT NULL,
  timezone TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'in_progress', 'completed', 'cancelled')),
  scheduled_for TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_action_plans_user_date ON action_plans(user_id, local_date);
CREATE INDEX IF NOT EXISTS idx_action_plans_user_created ON action_plans(user_id, created_at DESC);

ALTER TABLE action_plans ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plans' AND policyname = 'Users can view own action plans'
  ) THEN
    CREATE POLICY "Users can view own action plans"
      ON action_plans FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plans' AND policyname = 'Users can insert own action plans'
  ) THEN
    CREATE POLICY "Users can insert own action plans"
      ON action_plans FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plans' AND policyname = 'Users can update own action plans'
  ) THEN
    CREATE POLICY "Users can update own action plans"
      ON action_plans FOR UPDATE
      USING (auth.uid() = user_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS action_plan_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES action_plans(id) ON DELETE CASCADE,
  item_type TEXT NOT NULL CHECK (item_type IN ('quest', 'exercise', 'chat')),
  reference_id UUID,
  title TEXT NOT NULL,
  duration_minutes INT NOT NULL CHECK (duration_minutes > 0),
  sort_order INT NOT NULL DEFAULT 0,
  item_status TEXT NOT NULL DEFAULT 'pending' CHECK (item_status IN ('pending', 'completed', 'skipped')),
  completed_at TIMESTAMPTZ,
  skipped_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_action_plan_items_plan_order ON action_plan_items(plan_id, sort_order);

ALTER TABLE action_plan_items ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plan_items' AND policyname = 'Users can view own action plan items'
  ) THEN
    CREATE POLICY "Users can view own action plan items"
      ON action_plan_items FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM action_plans ap
          WHERE ap.id = action_plan_items.plan_id
          AND ap.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plan_items' AND policyname = 'Users can insert own action plan items'
  ) THEN
    CREATE POLICY "Users can insert own action plan items"
      ON action_plan_items FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM action_plans ap
          WHERE ap.id = action_plan_items.plan_id
          AND ap.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plan_items' AND policyname = 'Users can update own action plan items'
  ) THEN
    CREATE POLICY "Users can update own action plan items"
      ON action_plan_items FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM action_plans ap
          WHERE ap.id = action_plan_items.plan_id
          AND ap.user_id = auth.uid()
        )
      );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS action_plan_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id UUID NOT NULL REFERENCES action_plans(id) ON DELETE CASCADE,
  rating INT CHECK (rating IN (0, 1)),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_action_plan_feedback_plan ON action_plan_feedback(plan_id, created_at DESC);

ALTER TABLE action_plan_feedback ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plan_feedback' AND policyname = 'Users can view own action plan feedback'
  ) THEN
    CREATE POLICY "Users can view own action plan feedback"
      ON action_plan_feedback FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM action_plans ap
          WHERE ap.id = action_plan_feedback.plan_id
          AND ap.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'action_plan_feedback' AND policyname = 'Users can insert own action plan feedback'
  ) THEN
    CREATE POLICY "Users can insert own action plan feedback"
      ON action_plan_feedback FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM action_plans ap
          WHERE ap.id = action_plan_feedback.plan_id
          AND ap.user_id = auth.uid()
        )
      );
  END IF;
END $$;
