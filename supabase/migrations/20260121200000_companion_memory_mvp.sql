-- Companion Memory MVP
-- Curated user-managed memories with 20-item limit per user
-- Daily intents that expire after 24 hours

-- ============================================================================
-- Table: companion_memory
-- ============================================================================

CREATE TABLE IF NOT EXISTS companion_memory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN (
    'boundaries',
    'preferences',
    'triggers',
    'avoid_topics',
    'positive_reinforcement',
    'life_context'
  )),
  content TEXT NOT NULL CHECK (char_length(content) > 0 AND char_length(content) <= 500),
  last_used_at TIMESTAMPTZ,
  usage_count INT NOT NULL DEFAULT 0 CHECK (usage_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

COMMENT ON TABLE companion_memory IS 'Curated memories managed by user (max 20 per user)';
COMMENT ON COLUMN companion_memory.category IS 'Memory type: boundaries, preferences, triggers, avoid_topics, positive_reinforcement, life_context';
COMMENT ON COLUMN companion_memory.content IS 'Memory content (max 500 chars)';
COMMENT ON COLUMN companion_memory.last_used_at IS 'Last time this memory was included in a chat prompt';
COMMENT ON COLUMN companion_memory.usage_count IS 'Number of times this memory was used';
COMMENT ON COLUMN companion_memory.deleted_at IS 'Soft delete timestamp';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_companion_memory_user_active
  ON companion_memory(user_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_companion_memory_category
  ON companion_memory(user_id, category)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_companion_memory_usage
  ON companion_memory(user_id, last_used_at DESC NULLS LAST)
  WHERE deleted_at IS NULL;

-- RLS Policies
ALTER TABLE companion_memory ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'companion_memory' AND policyname = 'Users can view own memories'
  ) THEN
    CREATE POLICY "Users can view own memories"
      ON companion_memory FOR SELECT
      USING (auth.uid() = user_id AND deleted_at IS NULL);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'companion_memory' AND policyname = 'Users can insert own memories'
  ) THEN
    CREATE POLICY "Users can insert own memories"
      ON companion_memory FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'companion_memory' AND policyname = 'Users can update own memories'
  ) THEN
    CREATE POLICY "Users can update own memories"
      ON companion_memory FOR UPDATE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Trigger: Auto-update updated_at
CREATE OR REPLACE FUNCTION update_companion_memory_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS companion_memory_updated_at ON companion_memory;
CREATE TRIGGER companion_memory_updated_at
  BEFORE UPDATE ON companion_memory
  FOR EACH ROW
  EXECUTE FUNCTION update_companion_memory_updated_at();

-- Trigger: Enforce 20-memory limit per user (with row locking to prevent race conditions)
CREATE OR REPLACE FUNCTION enforce_memory_limit()
RETURNS TRIGGER AS $$
DECLARE
  memory_count INT;
BEGIN
  -- Count active memories for this user with FOR UPDATE lock to prevent race conditions
  -- This ensures concurrent inserts don't bypass the limit
  SELECT COUNT(*) INTO memory_count
  FROM companion_memory
  WHERE user_id = NEW.user_id AND deleted_at IS NULL
  FOR UPDATE;

  -- Block if limit reached
  IF memory_count >= 20 THEN
    RAISE EXCEPTION 'Memory limit reached (20/20). Delete a memory before adding a new one.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_memory_limit_trigger ON companion_memory;
CREATE TRIGGER enforce_memory_limit_trigger
  BEFORE INSERT ON companion_memory
  FOR EACH ROW
  EXECUTE FUNCTION enforce_memory_limit();

-- ============================================================================
-- Table: daily_intents
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  intent TEXT NOT NULL CHECK (char_length(intent) > 0 AND char_length(intent) <= 140),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
);

COMMENT ON TABLE daily_intents IS 'Daily user intents that expire after 24 hours';
COMMENT ON COLUMN daily_intents.intent IS 'Short daily intention or focus (max 140 chars)';
COMMENT ON COLUMN daily_intents.expires_at IS 'Automatically set to 24 hours after creation';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_daily_intents_user
  ON daily_intents(user_id);

CREATE INDEX IF NOT EXISTS idx_daily_intents_expires
  ON daily_intents(expires_at);

CREATE INDEX IF NOT EXISTS idx_daily_intents_user_active
  ON daily_intents(user_id, expires_at)
  WHERE expires_at > NOW();

-- RLS Policies
ALTER TABLE daily_intents ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'daily_intents' AND policyname = 'Users can view own intents'
  ) THEN
    CREATE POLICY "Users can view own intents"
      ON daily_intents FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'daily_intents' AND policyname = 'Users can insert own intents'
  ) THEN
    CREATE POLICY "Users can insert own intents"
      ON daily_intents FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'daily_intents' AND policyname = 'Users can delete own intents'
  ) THEN
    CREATE POLICY "Users can delete own intents"
      ON daily_intents FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Function: Cleanup expired intents
CREATE OR REPLACE FUNCTION cleanup_expired_intents(batch_limit INT DEFAULT 1000)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INT;
BEGIN
  WITH to_delete AS (
    SELECT id FROM daily_intents
    WHERE expires_at < NOW()
    LIMIT batch_limit
  )
  DELETE FROM daily_intents
  WHERE id IN (SELECT id FROM to_delete);

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION cleanup_expired_intents IS 'Deletes expired daily intents (call via cron or manually)';

-- Function: Update companion memory usage stats (called from Edge Functions with service role)
-- This function validates that the memories belong to the specified user before updating
CREATE OR REPLACE FUNCTION update_companion_memory_usage(
  memory_ids UUID[],
  used_at TIMESTAMPTZ,
  for_user_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count INT;
  effective_user_id UUID;
BEGIN
  -- Use provided user_id or fall back to auth.uid() for direct calls
  effective_user_id := COALESCE(for_user_id, auth.uid());

  -- Validate that a user is authenticated
  IF effective_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Only update memories that belong to the specified user (ownership validation)
  UPDATE companion_memory
  SET
    last_used_at = used_at,
    usage_count = usage_count + 1
  WHERE id = ANY(memory_ids)
    AND user_id = effective_user_id;

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;

COMMENT ON FUNCTION update_companion_memory_usage IS 'Updates last_used_at and increments usage_count for companion memories (validates ownership)';

-- Schedule cron job to cleanup expired intents every hour (requires pg_cron extension)
-- This handles automatic cleanup of expired daily intents
DO $$
BEGIN
  -- Check if pg_cron extension is available
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Remove existing job if it exists (idempotent)
    PERFORM cron.unschedule('cleanup_expired_intents_hourly');

    -- Schedule the cleanup to run every hour at minute 0
    PERFORM cron.schedule(
      'cleanup_expired_intents_hourly',
      '0 * * * *',  -- Every hour at minute 0
      $$SELECT cleanup_expired_intents(1000)$$
    );

    RAISE NOTICE 'Scheduled cleanup_expired_intents cron job';
  ELSE
    RAISE NOTICE 'pg_cron extension not available - skipping cron schedule. Call cleanup_expired_intents manually or via Edge Function.';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    -- pg_cron may not be available in all environments
    RAISE NOTICE 'Could not schedule cron job: %', SQLERRM;
END $$;
