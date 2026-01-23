-- Fix critical schema mismatches for stress signature patterns
-- Addresses P0 issues found in code review
-- Note: user_patterns table is created in later migration (20260219000000_proactive_intelligence.sql)

DO $$
BEGIN
  -- Only proceed if user_patterns table exists
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_patterns'
  ) THEN
    -- 1. Add evidence_count column (used for sorting and filtering)
    ALTER TABLE user_patterns
    ADD COLUMN IF NOT EXISTS evidence_count INT NOT NULL DEFAULT 0;

    -- Backfill evidence_count from existing data for current users
    UPDATE user_patterns
    SET evidence_count = GREATEST(times_surfaced, 1)
    WHERE evidence_count = 0;

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
  END IF;
END $$;

-- 4. Add audit logging table for security tracking (always create this)
CREATE TABLE IF NOT EXISTS pattern_access_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  access_type TEXT NOT NULL CHECK (access_type IN ('signature_fetch')),
  pattern_count INT NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '90 days')
);

CREATE INDEX IF NOT EXISTS idx_pattern_access_audit_user
ON pattern_access_audit(user_id, accessed_at DESC);

CREATE INDEX IF NOT EXISTS idx_pattern_access_audit_expires
ON pattern_access_audit(expires_at);

ALTER TABLE pattern_access_audit ENABLE ROW LEVEL SECURITY;

-- RLS policies for audit table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'pattern_access_audit' AND policyname = 'Users can view own audit logs'
  ) THEN
    CREATE POLICY "Users can view own audit logs" ON pattern_access_audit
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'pattern_access_audit' AND policyname = 'System can insert audit logs'
  ) THEN
    CREATE POLICY "System can insert audit logs" ON pattern_access_audit
      FOR INSERT WITH CHECK (true);
  END IF;
END $$;

-- 5. RPC function to aggregate user patterns (with audit logging)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_patterns'
  ) THEN
    EXECUTE $func$
      CREATE OR REPLACE FUNCTION get_stress_signature(p_user_id UUID)
      RETURNS JSONB
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $body$
      DECLARE
        v_result JSONB;
        v_pattern_count INT;
      BEGIN
        -- Verify caller owns the data
        IF auth.uid() != p_user_id THEN
          RAISE EXCEPTION 'Unauthorized: Cannot access patterns for other users';
        END IF;

        -- Count matching patterns separately for accurate audit log
        SELECT COUNT(*)
        INTO v_pattern_count
        FROM user_patterns
        WHERE user_id = p_user_id
          AND pattern_type LIKE 'signature_%'
          AND confidence >= 0.5
          AND is_active = TRUE;

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
        )
        INTO v_result
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
      $body$
    $func$;

    -- Grant access to authenticated users
    EXECUTE 'GRANT EXECUTE ON FUNCTION get_stress_signature(UUID) TO authenticated';

    -- Add comments
    EXECUTE 'COMMENT ON COLUMN user_patterns.evidence_count IS ''Number of data points supporting this pattern (mood logs, exercise sessions, etc.)''';
    EXECUTE 'COMMENT ON TABLE pattern_access_audit IS ''Security audit log for pattern access (anonymized - counts only, no PII). Auto-purges after 90 days.''';
    
    RAISE NOTICE 'Fixed signature pattern schema';
  ELSE
    RAISE NOTICE 'user_patterns table does not exist yet, skipping schema fixes';
  END IF;
END $$;
