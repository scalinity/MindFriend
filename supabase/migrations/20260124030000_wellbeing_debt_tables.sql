-- N006: Wellbeing Debt Calculator - Database Schema
-- Created: 2026-01-24
-- Description: Tables for tracking wellbeing transactions, debt scores, and user profiles

-- =============================================================================
-- 1. WELLBEING TRANSACTIONS TABLE
-- =============================================================================
-- Stores daily deposits (positive activities) and withdrawals (stressors)

CREATE TABLE IF NOT EXISTS wellbeing_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('deposit', 'withdrawal')),
  category TEXT NOT NULL CHECK (category IN (
    -- Deposits
    'sleep_quality',
    'exercise_completion',
    'social_connection',
    'meditation',
    'outdoor_time',
    'quest_completion',
    'positive_event',
    -- Withdrawals
    'poor_sleep',
    'missed_sleep',
    'work_stress',
    'conflict',
    'social_isolation',
    'negative_mood',
    'health_issue',
    'circadian_disruption'
  )),
  amount DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
  source TEXT NOT NULL CHECK (source IN (
    'healthkit',
    'mood_log',
    'exercise_sessions',
    'circle_posts',
    'quests',
    'circadian_shield',
    'user_logged',
    'inferred'
  )),
  description TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Idempotency constraint: one transaction per (user, date, source, category)
  CONSTRAINT unique_transaction UNIQUE (user_id, date, source, category)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_transactions_user_date
  ON wellbeing_transactions(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_category
  ON wellbeing_transactions(category);
CREATE INDEX IF NOT EXISTS idx_transactions_type
  ON wellbeing_transactions(type);

-- =============================================================================
-- 2. WELLBEING DEBT SCORES TABLE
-- =============================================================================
-- Stores daily calculated debt scores with rolling totals and threshold status

CREATE TABLE IF NOT EXISTS wellbeing_debt_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  daily_balance DECIMAL(10,2) NOT NULL CHECK (daily_balance BETWEEN -100 AND 100),
  rolling_debt_7day DECIMAL(10,2) NOT NULL DEFAULT 0,
  rolling_debt_14day DECIMAL(10,2) NOT NULL DEFAULT 0,
  rolling_debt_30day DECIMAL(10,2) NOT NULL DEFAULT 0,

  -- Trend data (JSONB)
  -- Schema: { direction: 'improving'|'worsening'|'stable', velocity: number, projection_7day: number }
  trend JSONB NOT NULL DEFAULT '{"direction": "stable", "velocity": 0, "projection_7day": 0}',

  -- Threshold status (JSONB)
  -- Schema: { current_debt: number, threshold: number|null, severity: 'safe'|'warning'|'danger', days_until_crash: number|null, confidence: number }
  threshold_status JSONB NOT NULL DEFAULT '{"current_debt": 0, "threshold": null, "severity": "safe", "days_until_crash": null, "confidence": 0}',

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One score per user per day
  CONSTRAINT unique_score_per_day UNIQUE (user_id, date)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_scores_user_date
  ON wellbeing_debt_scores(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_scores_threshold_severity
  ON wellbeing_debt_scores(user_id, ((threshold_status->>'severity')::TEXT));

-- JSONB validation constraints
ALTER TABLE wellbeing_debt_scores
  ADD CONSTRAINT trend_has_required_keys
  CHECK (
    trend ? 'direction' AND
    trend ? 'velocity' AND
    trend ? 'projection_7day'
  );

ALTER TABLE wellbeing_debt_scores
  ADD CONSTRAINT threshold_status_has_required_keys
  CHECK (
    threshold_status ? 'current_debt' AND
    threshold_status ? 'severity' AND
    threshold_status ? 'confidence'
  );

-- =============================================================================
-- 3. WELLBEING DEBT PROFILES TABLE
-- =============================================================================
-- Stores personalized thresholds, crash history, and top drains/deposits

CREATE TABLE IF NOT EXISTS wellbeing_debt_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Personal threshold (10th percentile of crash debts, minimum 3 crashes)
  -- Assumption #3: Default -50 until learned from crash history
  personal_threshold DECIMAL(10,2) DEFAULT -50 CHECK (personal_threshold <= 0),

  -- Crash history (JSONB)
  -- Schema: { crashes: Array<{ date: string, debt_at_crash: number, mood_score: number }>, last_updated: string|null }
  crash_history JSONB DEFAULT '{"crashes": [], "last_updated": null}',

  -- Top drains (JSONB)
  -- Schema: { categories: Array<{ category: string, total_amount: number, frequency: number }>, last_updated: string|null }
  top_drains JSONB DEFAULT '{"categories": [], "last_updated": null}',

  -- Top deposits (JSONB)
  -- Schema: { categories: Array<{ category: string, total_amount: number, frequency: number }>, last_updated: string|null }
  top_deposits JSONB DEFAULT '{"categories": [], "last_updated": null}',

  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One profile per user
  CONSTRAINT unique_profile_per_user UNIQUE (user_id)
);

-- Index for user lookup
CREATE INDEX IF NOT EXISTS idx_profiles_user ON wellbeing_debt_profiles(user_id);

-- JSONB validation constraints (Assumption #5)
ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT crash_history_is_object
  CHECK (jsonb_typeof(crash_history) = 'object');

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT crash_history_has_crashes_array
  CHECK (
    crash_history ? 'crashes' AND
    jsonb_typeof(crash_history->'crashes') = 'array'
  );

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT top_drains_is_object
  CHECK (jsonb_typeof(top_drains) = 'object');

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT top_drains_has_categories_array
  CHECK (
    top_drains ? 'categories' AND
    jsonb_typeof(top_drains->'categories') = 'array'
  );

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT top_drains_max_3_categories
  CHECK (jsonb_array_length(top_drains->'categories') <= 3);

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT top_deposits_is_object
  CHECK (jsonb_typeof(top_deposits) = 'object');

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT top_deposits_has_categories_array
  CHECK (
    top_deposits ? 'categories' AND
    jsonb_typeof(top_deposits->'categories') = 'array'
  );

ALTER TABLE wellbeing_debt_profiles
  ADD CONSTRAINT top_deposits_max_3_categories
  CHECK (jsonb_array_length(top_deposits->'categories') <= 3);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE wellbeing_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_debt_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_debt_profiles ENABLE ROW LEVEL SECURITY;

-- Transactions policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wellbeing_transactions'
    AND policyname = 'Users read own transactions'
  ) THEN
    CREATE POLICY "Users read own transactions"
      ON wellbeing_transactions
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wellbeing_transactions'
    AND policyname = 'Service role manages transactions'
  ) THEN
    CREATE POLICY "Service role manages transactions"
      ON wellbeing_transactions
      FOR ALL
      USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- Debt scores policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wellbeing_debt_scores'
    AND policyname = 'Users read own debt scores'
  ) THEN
    CREATE POLICY "Users read own debt scores"
      ON wellbeing_debt_scores
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wellbeing_debt_scores'
    AND policyname = 'Service role manages debt scores'
  ) THEN
    CREATE POLICY "Service role manages debt scores"
      ON wellbeing_debt_scores
      FOR ALL
      USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- Debt profiles policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wellbeing_debt_profiles'
    AND policyname = 'Users read own debt profile'
  ) THEN
    CREATE POLICY "Users read own debt profile"
      ON wellbeing_debt_profiles
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'wellbeing_debt_profiles'
    AND policyname = 'Service role manages debt profiles'
  ) THEN
    CREATE POLICY "Service role manages debt profiles"
      ON wellbeing_debt_profiles
      FOR ALL
      USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to auto-create profile when user first accesses wellbeing debt feature
CREATE OR REPLACE FUNCTION ensure_wellbeing_debt_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO wellbeing_debt_profiles (user_id)
  VALUES (NEW.user_id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Auto-create profile on first transaction
DROP TRIGGER IF EXISTS auto_create_profile_on_transaction ON wellbeing_transactions;
CREATE TRIGGER auto_create_profile_on_transaction
  AFTER INSERT ON wellbeing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION ensure_wellbeing_debt_profile();

-- Trigger: Auto-create profile on first score
DROP TRIGGER IF EXISTS auto_create_profile_on_score ON wellbeing_debt_scores;
CREATE TRIGGER auto_create_profile_on_score
  AFTER INSERT ON wellbeing_debt_scores
  FOR EACH ROW
  EXECUTE FUNCTION ensure_wellbeing_debt_profile();

-- =============================================================================
-- COMMENTS FOR DOCUMENTATION
-- =============================================================================

COMMENT ON TABLE wellbeing_transactions IS
  'N006: Tracks daily wellbeing deposits (positive activities) and withdrawals (stressors)';

COMMENT ON TABLE wellbeing_debt_scores IS
  'N006: Daily calculated debt scores with rolling totals and threshold status';

COMMENT ON TABLE wellbeing_debt_profiles IS
  'N006: User-specific thresholds, crash history, and category insights';

COMMENT ON COLUMN wellbeing_debt_profiles.personal_threshold IS
  'Learned crash threshold (10th percentile of crash debts). Default -50 until min 3 crashes recorded.';

COMMENT ON COLUMN wellbeing_debt_profiles.crash_history IS
  'JSONB: { crashes: [{date, debt_at_crash, mood_score}], last_updated } (Assumption #1: crash = mood ≤2)';

COMMENT ON COLUMN wellbeing_debt_profiles.top_drains IS
  'JSONB: { categories: [{category, total_amount, frequency}], last_updated } (max 3 categories)';

COMMENT ON COLUMN wellbeing_debt_profiles.top_deposits IS
  'JSONB: { categories: [{category, total_amount, frequency}], last_updated } (max 3 categories)';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

-- Allow authenticated users to read their own data
GRANT SELECT ON wellbeing_transactions TO authenticated;
GRANT SELECT ON wellbeing_debt_scores TO authenticated;
GRANT SELECT ON wellbeing_debt_profiles TO authenticated;

-- Service role has full access (for Edge Functions)
GRANT ALL ON wellbeing_transactions TO service_role;
GRANT ALL ON wellbeing_debt_scores TO service_role;
GRANT ALL ON wellbeing_debt_profiles TO service_role;
