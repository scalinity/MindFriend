-- Fix critical schema mismatches for stress signature patterns
-- Addresses P0 issues found in code review

-- 1. Add evidence_count column (used for sorting and filtering)
ALTER TABLE user_patterns
ADD COLUMN IF NOT EXISTS evidence_count INT NOT NULL DEFAULT 0;

-- 2. Update CHECK constraint to allow signature pattern types
ALTER TABLE user_patterns
DROP CONSTRAINT IF EXISTS user_patterns_pattern_type_check;

ALTER TABLE user_patterns
ADD CONSTRAINT user_patterns_pattern_type_check
CHECK (pattern_type IN (
  'day_of_week', 'time_of_day', 'exercise_correlation',
  'sleep_proxy', 'quest_preference', 'streak_recovery', 'custom',
  -- Signature pattern types
  'signature_stress_trigger', 'signature_coping_strategy', 'signature_time_pattern'
));

-- 3. Add composite index for efficient signature queries
CREATE INDEX IF NOT EXISTS idx_user_patterns_signature_query
ON user_patterns(user_id, pattern_type, is_active, confidence DESC)
WHERE pattern_type LIKE 'signature_%';

-- 4. Update RPC function to use correct column names
CREATE OR REPLACE FUNCTION get_stress_signature(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp  -- Protection against search_path attacks
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Verify caller owns the data (RLS-style check in function)
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access patterns for other users';
  END IF;

  -- Aggregate patterns into signature format
  SELECT jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'category', pattern_key,
        'type', pattern_type,
        'confidenceScore', confidence,           -- Fixed: was confidence_score
        'evidenceCount', evidence_count,         -- Now exists as column
        'firstDetected', first_detected_at,
        'lastDetected', last_confirmed_at,       -- Fixed: was last_detected_at
        'data', pattern_data
      )
      ORDER BY confidence DESC, evidence_count DESC
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM user_patterns
  WHERE user_id = p_user_id
    AND pattern_type LIKE 'signature_%'
    AND confidence >= 0.5  -- Fixed: was confidence_score
    AND is_active = TRUE;

  RETURN COALESCE(v_result, jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', '[]'::jsonb
  ));
END;
$$;

-- 5. Add audit logging function for security tracking
CREATE TABLE IF NOT EXISTS pattern_access_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  access_type TEXT NOT NULL,
  pattern_count INT
);

CREATE INDEX IF NOT EXISTS idx_pattern_access_audit_user
ON pattern_access_audit(user_id, accessed_at DESC);

ALTER TABLE pattern_access_audit ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'pattern_access_audit' AND policyname = 'Users can view own audit logs'
  ) THEN
    CREATE POLICY "Users can view own audit logs" ON pattern_access_audit
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- 6. Update RPC function to log access for security monitoring
CREATE OR REPLACE FUNCTION get_stress_signature(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result JSONB;
  v_pattern_count INT;
BEGIN
  -- Verify caller owns the data
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access patterns for other users';
  END IF;

  -- Aggregate patterns into signature format
  SELECT jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'category', pattern_key,
        'type', pattern_type,
        'confidenceScore', confidence,
        'evidenceCount', evidence_count,
        'firstDetected', first_detected_at,
        'lastDetected', last_confirmed_at,
        'data', pattern_data
      )
      ORDER BY confidence DESC, evidence_count DESC
    ), '[]'::jsonb)
  ),
  COUNT(*)
  INTO v_result, v_pattern_count
  FROM user_patterns
  WHERE user_id = p_user_id
    AND pattern_type LIKE 'signature_%'
    AND confidence >= 0.5
    AND is_active = TRUE;

  -- Audit log (anonymized - only count, no pattern details)
  INSERT INTO pattern_access_audit (user_id, access_type, pattern_count)
  VALUES (p_user_id, 'signature_fetch', v_pattern_count);

  RETURN COALESCE(v_result, jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', '[]'::jsonb
  ));
END;
$$;

COMMENT ON COLUMN user_patterns.evidence_count IS 'Number of data points supporting this pattern (mood logs, exercise sessions, etc.)';
COMMENT ON TABLE pattern_access_audit IS 'Security audit log for pattern access (anonymized - counts only, no PII)';
