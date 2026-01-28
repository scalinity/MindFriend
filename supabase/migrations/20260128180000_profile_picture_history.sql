-- Profile Picture History Table
-- Migration: 20260128180000_profile_picture_history
-- Purpose: Store previously used profile pictures to reduce AI generation costs

CREATE TABLE IF NOT EXISTS profile_picture_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    storage_path TEXT NOT NULL,
    public_url TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('upload', 'ai_generated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Ensure no duplicate paths for same user
    CONSTRAINT unique_user_picture UNIQUE (user_id, storage_path)
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_profile_picture_history_user 
    ON profile_picture_history(user_id);
CREATE INDEX IF NOT EXISTS idx_profile_picture_history_user_created 
    ON profile_picture_history(user_id, created_at DESC);

-- Enable RLS
ALTER TABLE profile_picture_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own history
CREATE POLICY "Users can read own picture history"
    ON profile_picture_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own picture history"
    ON profile_picture_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own picture history"
    ON profile_picture_history FOR DELETE
    USING (auth.uid() = user_id);

-- Add comment
COMMENT ON TABLE profile_picture_history IS 'Stores previously used profile pictures to allow reuse and reduce AI generation costs';
COMMENT ON COLUMN profile_picture_history.source IS 'Source of the picture: upload or ai_generated';
