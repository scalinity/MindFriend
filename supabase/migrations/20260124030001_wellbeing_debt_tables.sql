-- N006: Wellbeing Debt Calculator - Core Database Schema
-- Creates tables for tracking wellbeing transactions, debt scores, and user profiles
-- Based on allostatic load theory and 10th percentile threshold learning

-- Table 1: Wellbeing Transactions
-- Stores all deposits (positive activities) and withdrawals (stressors)
CREATE TABLE IF NOT EXISTS wellbeing_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('deposit', 'withdrawal')),
  category TEXT NOT NULL CHECK (category IN (
    'sleep_quality', 'poor_sleep', 'exercise', 'social_connection',
    'social_isolation', 'quest_completion', 'mood_negative', 'circadian_misalignment'
  )),
  amount DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
  source TEXT NOT NULL CHECK (source IN (
    'healthkit', 'mood_log', 'exercise_session', 'circle', 'quest', 
    'circadian_engine', 'user_logged', 'auto_detected'
  )),
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Ensure no duplicate transactions for same user/date/source/category
  CONSTRAINT unique_transaction UNIQUE (user_id, date, source, category)
);

-- Table 2: Wellbeing Debt Scores
-- Daily aggregated scores with rolling windows and trend analysis
CREATE TABLE IF NOT EXISTS wellbeing_debt_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  daily_balance DECIMAL(10,2) NOT NULL CHECK (daily_balance BETWEEN -100 AND 100),
  rolling_debt_7day DECIMAL(10,2) NOT NULL CHECK (rolling_debt_7day >= 0),
  rolling_debt_14day DECIMAL(10,2) NOT NULL CHECK (rolling_debt_14day >= 0),
  rolling_debt_30day DECIMAL(10,2) NOT NULL CHECK (rolling_debt_30day >= 0),
  trend JSONB NOT NULL,  -- {direction: "improving"|"worsening"|"stable", velocity: number, projection_7day: number}
  threshold_status JSONB NOT NULL,  -- {current_debt: number, threshold: number|null, severity: "safe"|"warning"|"danger", days_until_crash: number|null, confidence: number}
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- One score per user per day
  CONSTRAINT unique_score_per_day UNIQUE (user_id, date)
);

-- Table 3: Wellbeing Debt Profiles
-- User-level aggregates and personalized thresholds
CREATE TABLE IF NOT EXISTS wellbeing_debt_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  learned_threshold DECIMAL(10,2),  -- 10th percentile of crash debts (null until 3+ crashes)
  last_crash_date DATE,  -- Most recent mood ≤2 event
  crash_history JSONB DEFAULT '[]'::jsonb,  -- [{date: string, debt_at_crash: number}]
  top_drains JSONB NOT NULL DEFAULT '{"categories": []}'::jsonb,  -- {categories: [{category: string, total_amount: number, frequency: number}]}
  top_deposits JSONB NOT NULL DEFAULT '{"categories": []}'::jsonb,  -- {categories: [{category: string, total_amount: number, frequency: number}]}
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Row Level Security Policies
ALTER TABLE wellbeing_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_debt_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_debt_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for wellbeing_transactions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_transactions' AND policyname = 'Users can read own transactions'
  ) THEN
    CREATE POLICY "Users can read own transactions" 
      ON wellbeing_transactions FOR SELECT 
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_transactions' AND policyname = 'Users can insert own transactions'
  ) THEN
    CREATE POLICY "Users can insert own transactions" 
      ON wellbeing_transactions FOR INSERT 
      WITH CHECK (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_transactions' AND policyname = 'Service role can manage all transactions'
  ) THEN
    CREATE POLICY "Service role can manage all transactions" 
      ON wellbeing_transactions FOR ALL 
      USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- RLS Policies for wellbeing_debt_scores
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_debt_scores' AND policyname = 'Users can read own scores'
  ) THEN
    CREATE POLICY "Users can read own scores" 
      ON wellbeing_debt_scores FOR SELECT 
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_debt_scores' AND policyname = 'Service role can manage all scores'
  ) THEN
    CREATE POLICY "Service role can manage all scores" 
      ON wellbeing_debt_scores FOR ALL 
      USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- RLS Policies for wellbeing_debt_profiles
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_debt_profiles' AND policyname = 'Users can read own profile'
  ) THEN
    CREATE POLICY "Users can read own profile" 
      ON wellbeing_debt_profiles FOR SELECT 
      USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'wellbeing_debt_profiles' AND policyname = 'Service role can manage all profiles'
  ) THEN
    CREATE POLICY "Service role can manage all profiles" 
      ON wellbeing_debt_profiles FOR ALL 
      USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- Add helpful comments
COMMENT ON TABLE wellbeing_transactions IS 'N006: Individual deposits and withdrawals from all data sources';
COMMENT ON TABLE wellbeing_debt_scores IS 'N006: Daily aggregated debt scores with rolling windows';
COMMENT ON TABLE wellbeing_debt_profiles IS 'N006: User-level profiles with personalized thresholds';

-- Log successful creation
DO $$
DECLARE
  trans_count INTEGER;
  score_count INTEGER;
  profile_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO trans_count FROM pg_tables WHERE tablename = 'wellbeing_transactions';
  SELECT COUNT(*) INTO score_count FROM pg_tables WHERE tablename = 'wellbeing_debt_scores';
  SELECT COUNT(*) INTO profile_count FROM pg_tables WHERE tablename = 'wellbeing_debt_profiles';

  IF trans_count > 0 AND score_count > 0 AND profile_count > 0 THEN
    RAISE NOTICE 'N006 wellbeing debt tables created successfully';
  ELSE
    RAISE WARNING 'N006 some tables may not have been created';
  END IF;
END $$;
