-- N006: Wellbeing Debt Calculator - Performance Indexes
-- Add foreign key indexes and query optimization indexes
-- Migration created: 2026-01-24

-- Indexes for wellbeing_transactions table
-- These prevent N+1 queries and improve lookup performance

-- Index on user_id for filtering by user (most common query pattern)
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_user_id 
  ON wellbeing_transactions(user_id);

-- Index on date for temporal queries
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_date 
  ON wellbeing_transactions(date DESC);

-- Composite index for user + date range queries (most frequent pattern)
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_user_date 
  ON wellbeing_transactions(user_id, date DESC);

-- Index on type for filtering deposits vs withdrawals
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_type 
  ON wellbeing_transactions(type);

-- Index on category for category analysis
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_category 
  ON wellbeing_transactions(category);

-- Index on source for data source tracking
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_source 
  ON wellbeing_transactions(source);

-- Composite index for top drains/deposits analysis (user + category + date)
CREATE INDEX IF NOT EXISTS idx_wellbeing_transactions_analysis 
  ON wellbeing_transactions(user_id, category, date DESC) 
  INCLUDE (amount, type);

-- Indexes for wellbeing_debt_scores table

-- Index on user_id (foreign key)
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_scores_user_id 
  ON wellbeing_debt_scores(user_id);

-- Index on date for temporal lookups
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_scores_date 
  ON wellbeing_debt_scores(date DESC);

-- Composite index for user + date queries (primary access pattern)
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_scores_user_date 
  ON wellbeing_debt_scores(user_id, date DESC);

-- Removed partial index - CURRENT_DATE is not immutable
-- For recent scores queries, use regular index with WHERE clause

-- Indexes for wellbeing_debt_profiles table

-- Index on user_id (foreign key)
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_profiles_user_id 
  ON wellbeing_debt_profiles(user_id);

-- Index on last_crash_date for crash detection queries
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_profiles_last_crash 
  ON wellbeing_debt_profiles(last_crash_date DESC) 
  WHERE last_crash_date IS NOT NULL;

-- GIN index on top_drains JSONB for fast category lookups
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_profiles_top_drains 
  ON wellbeing_debt_profiles USING GIN (top_drains);

-- GIN index on top_deposits JSONB for fast category lookups
CREATE INDEX IF NOT EXISTS idx_wellbeing_debt_profiles_top_deposits 
  ON wellbeing_debt_profiles USING GIN (top_deposits);

-- Add helpful comments
COMMENT ON INDEX idx_wellbeing_transactions_user_date IS 
  'Optimize user + date range queries (most frequent access pattern)';
COMMENT ON INDEX idx_wellbeing_transactions_analysis IS 
  'Optimize category analysis queries with included columns';

-- Log successful creation
DO $$
DECLARE
  index_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO index_count
  FROM pg_indexes
  WHERE schemaname = 'public' 
    AND (tablename LIKE 'wellbeing_%')
    AND (indexname LIKE 'idx_wellbeing_%');

  RAISE NOTICE 'N006: Created % performance indexes for wellbeing debt tables', index_count;
END $$;
