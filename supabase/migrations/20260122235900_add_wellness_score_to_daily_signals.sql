-- Add wellness score columns to existing daily_signals table
-- This extends the risk-scoring data with wellness-specific calculations
--
-- Wellness Score = 0-100 metric synthesizing mood, quest completion,
-- social engagement, activity, and sleep quality
--
-- Unlike risk scores (which detect negative patterns), wellness scores
-- celebrate positive patterns and user progress

-- Add columns
ALTER TABLE daily_signals
ADD COLUMN IF NOT EXISTS wellness_score INTEGER CHECK (wellness_score >= 0 AND wellness_score <= 100),
ADD COLUMN IF NOT EXISTS wellness_confidence INTEGER CHECK (wellness_confidence >= 0 AND wellness_confidence <= 100),
ADD COLUMN IF NOT EXISTS wellness_components JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS wellness_calculated_at TIMESTAMPTZ;

-- Add comments for documentation
COMMENT ON COLUMN daily_signals.wellness_score IS
  'Daily wellness score (0-100). Weighted average of: mood (30%), quest (25%), social (15%), activity (15%), sleep (15%). Calculated nightly at 3 AM UTC by Edge Function.';

COMMENT ON COLUMN daily_signals.wellness_confidence IS
  'Confidence level (0-100) based on data availability. 100 = all components have data, 0 = no data available.';

COMMENT ON COLUMN daily_signals.wellness_components IS
  'JSON breakdown of component scores: {
    "mood": {"value": 0-100, "weight": 0.30, "confidence": 0-100, "reason": "..."},
    "quest": {"value": 0-100, "weight": 0.25, "confidence": 0-100, "reason": "..."},
    "social": {"value": 0-100, "weight": 0.15, "confidence": 0-100, "reason": "..."},
    "activity": {"value": 0-100, "weight": 0.15, "confidence": 0-100, "reason": "..."},
    "sleep": {"value": 0-100, "weight": 0.15, "confidence": 0-100, "reason": "..."}
  }';

COMMENT ON COLUMN daily_signals.wellness_calculated_at IS
  'Timestamp when wellness score was last calculated. NULL if not yet calculated.';

-- Create index for fast wellness score queries
CREATE INDEX IF NOT EXISTS idx_daily_signals_wellness_score
ON daily_signals(user_id, signal_date DESC)
WHERE wellness_score IS NOT NULL;

-- Grant permissions (match existing RLS policies)
-- Note: RLS policies on daily_signals already restrict access to user's own rows
