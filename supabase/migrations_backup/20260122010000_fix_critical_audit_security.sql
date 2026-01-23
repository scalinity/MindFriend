-- Fix critical audit table security issues (Security Audit P0-P1 findings)
-- Addresses CRITICAL audit INSERT policy vulnerability allowing data poisoning

-- 1. Replace permissive INSERT policy with user-restricted policy
DROP POLICY IF EXISTS "System can insert audit logs" ON pattern_access_audit;

CREATE POLICY "Users can insert own audit logs" ON pattern_access_audit
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 2. Add explicit UPDATE policy (deny all - immutable logs)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'pattern_access_audit' AND policyname = 'Audit logs are immutable'
  ) THEN
    CREATE POLICY "Audit logs are immutable" ON pattern_access_audit
      FOR UPDATE USING (false);
  END IF;
END $$;

-- 3. Add explicit DELETE policy (deny all - TTL cleanup only)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'pattern_access_audit' AND policyname = 'Audit logs cannot be manually deleted'
  ) THEN
    CREATE POLICY "Audit logs cannot be manually deleted" ON pattern_access_audit
      FOR DELETE USING (false);
  END IF;
END $$;

-- 4. Update table comment
COMMENT ON TABLE pattern_access_audit IS 'Immutable security audit log for pattern access.
- INSERT: Users can only insert their own logs (enforced by RLS)
- UPDATE: Blocked (logs are immutable)
- DELETE: Blocked (automatic TTL cleanup via expires_at)
- Retention: 90 days (configurable via expires_at default)
- PII: Anonymized (counts only, no pattern details)';

-- 5. Add rate limiting check function
CREATE OR REPLACE FUNCTION check_signature_fetch_rate_limit(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_recent_count INT;
BEGIN
  -- Allow max 10 fetches per minute
  SELECT COUNT(*)
  INTO v_recent_count
  FROM pattern_access_audit
  WHERE user_id = p_user_id
    AND access_type = 'signature_fetch'
    AND accessed_at > NOW() - INTERVAL '1 minute';

  RETURN v_recent_count < 10;
END;
$$;

GRANT EXECUTE ON FUNCTION check_signature_fetch_rate_limit(UUID) TO authenticated;

COMMENT ON FUNCTION check_signature_fetch_rate_limit IS 'Rate limiting check: max 10 signature fetches per minute per user.';

-- 6. Update get_stress_signature with rate limiting
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

  -- Rate limiting check
  IF NOT check_signature_fetch_rate_limit(p_user_id) THEN
    RAISE EXCEPTION 'Rate limit exceeded: Maximum 10 requests per minute';
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
$$;

COMMENT ON FUNCTION get_stress_signature IS 'Fetch user stress signature patterns with rate limiting (10/min).
Security: SECURITY DEFINER with auth check, search_path protection, rate limiting.
Audit: Logs access count (anonymized) to pattern_access_audit.';
