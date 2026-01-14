-- AI Memory Feature: memory_fragments table
-- Stores extracted facts from user conversations for personalization
-- Schema aligned with specs/01-ai-memory.md

CREATE TABLE IF NOT EXISTS memory_fragments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fragment_type TEXT NOT NULL CHECK (fragment_type IN ('person', 'event', 'preference', 'fact')),
  key TEXT NOT NULL,              -- e.g., 'dog_name', 'upcoming_presentation', 'favorite_exercise'
  value TEXT NOT NULL CHECK (char_length(value) <= 500), -- e.g., 'Max', 'Friday presentation at work'
  confidence FLOAT NOT NULL DEFAULT 0.8 CHECK (confidence >= 0 AND confidence <= 1),
  extracted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source_conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  source_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  expires_at TIMESTAMPTZ,         -- NULL for permanent memories, set for events
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Prevent duplicate memories - upsert will update existing
  UNIQUE(user_id, fragment_type, key)
);

-- Add table comments
COMMENT ON TABLE memory_fragments IS 'AI-extracted facts from user conversations for personalization';
COMMENT ON COLUMN memory_fragments.fragment_type IS 'Type: person (names), event (upcoming/past), preference (likes/dislikes), fact (job/location/hobbies)';
COMMENT ON COLUMN memory_fragments.key IS 'Short identifier for the memory (e.g., dog_name, work_location)';
COMMENT ON COLUMN memory_fragments.value IS 'The actual content/value of the memory';
COMMENT ON COLUMN memory_fragments.confidence IS 'Extraction confidence score (0.0-1.0), higher = more certain';
COMMENT ON COLUMN memory_fragments.expires_at IS 'NULL for permanent types (person/preference/fact), set to event date + 7 days for events';

-- Indexes for efficient retrieval
CREATE INDEX IF NOT EXISTS idx_memory_fragments_user ON memory_fragments(user_id);
CREATE INDEX IF NOT EXISTS idx_memory_fragments_type ON memory_fragments(user_id, fragment_type);
CREATE INDEX IF NOT EXISTS idx_memory_fragments_confidence ON memory_fragments(user_id, confidence DESC);
CREATE INDEX IF NOT EXISTS idx_memory_fragments_expires ON memory_fragments(expires_at)
  WHERE expires_at IS NOT NULL;

-- Enable Row Level Security
ALTER TABLE memory_fragments ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own memories
CREATE POLICY "Users can view own memories"
  ON memory_fragments FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own memories"
  ON memory_fragments FOR DELETE
  USING (auth.uid() = user_id);

-- Explicit DENY policies for INSERT/UPDATE by authenticated users
-- Memory insertion is only done via Edge Function using service role key
-- This prevents any client-side attempts to insert/modify memories
CREATE POLICY "Deny direct user inserts"
  ON memory_fragments FOR INSERT
  WITH CHECK (false);

CREATE POLICY "Deny direct user updates"
  ON memory_fragments FOR UPDATE
  USING (false)
  WITH CHECK (false);

-- Trigger to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_memory_fragments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER memory_fragments_updated_at
  BEFORE UPDATE ON memory_fragments
  FOR EACH ROW
  EXECUTE FUNCTION update_memory_fragments_updated_at();

-- Function to clean up expired memories (with batch limit to prevent DOS)
-- Can be called via pg_cron job or manually
CREATE OR REPLACE FUNCTION cleanup_expired_memories(batch_limit INT DEFAULT 1000)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INT;
BEGIN
  -- Delete in batches to prevent locking issues and DOS
  WITH to_delete AS (
    SELECT id FROM memory_fragments
    WHERE expires_at IS NOT NULL AND expires_at < NOW()
    LIMIT batch_limit
  )
  DELETE FROM memory_fragments
  WHERE id IN (SELECT id FROM to_delete);

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION cleanup_expired_memories IS 'Removes expired memory fragments in batches (default 1000). Call repeatedly if more need cleanup.';

-- Scheduled cleanup job (runs daily at 3am UTC)
-- Note: Requires pg_cron extension to be enabled in Supabase Dashboard
-- SELECT cron.schedule('cleanup-expired-memories', '0 3 * * *', 'SELECT cleanup_expired_memories(1000)');
