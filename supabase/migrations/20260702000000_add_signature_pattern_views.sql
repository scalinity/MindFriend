-- Add RPC function to aggregate user patterns into stress signature format
-- This enables efficient client-side fetching of pattern summaries for visualization

-- RPC Function: get_stress_signature
-- Purpose: Aggregate user_patterns into signature pattern summaries for UI rendering
-- Security: SECURITY DEFINER with auth check (users can only see their own data)
CREATE OR REPLACE FUNCTION get_stress_signature(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
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
        'confidenceScore', confidence_score,
        'evidenceCount', evidence_count,
        'firstDetected', first_detected_at,
        'lastDetected', last_detected_at,
        'data', pattern_data
      )
      ORDER BY confidence_score DESC, evidence_count DESC
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM user_patterns
  WHERE user_id = p_user_id
    AND pattern_type LIKE 'signature_%'
    AND confidence_score >= 0.5  -- Only show confident patterns
    AND is_active = TRUE;

  RETURN COALESCE(v_result, jsonb_build_object(
    'userId', p_user_id,
    'generatedAt', NOW(),
    'patterns', '[]'::jsonb
  ));
END;
$$;

-- Grant access to authenticated users
GRANT EXECUTE ON FUNCTION get_stress_signature(UUID) TO authenticated;

-- Add comment explaining pattern_data JSONB schema for signature patterns
COMMENT ON COLUMN user_patterns.pattern_data IS 'JSONB data specific to pattern type.

For signature patterns (pattern_type LIKE ''signature_%''):
{
  "category": "User-friendly category name (e.g., ''Work Stress'', ''Breathing Techniques'')",
  "frequency": "Patterns per week (float)",
  "timeline": [
    {
      "date": "ISO8601 date string",
      "count": "Number of pattern occurrences (integer)"
    }
  ],
  "topExercises": ["Exercise names"] (optional, for coping strategies),
  "peakTimes": ["HH:MM time strings"] (optional, for time patterns)
}

For other pattern types, see existing pattern-detector documentation.';
