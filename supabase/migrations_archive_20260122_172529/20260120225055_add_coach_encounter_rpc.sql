-- Create RPC function for atomic coach encounter logging
-- This ensures encounter creation is transactional and handles errors gracefully

CREATE OR REPLACE FUNCTION log_coach_encounter(
  p_user_id UUID,
  p_distortion_code TEXT,
  p_conversation_id UUID,
  p_original_message_preview TEXT,
  p_reframe_text TEXT,
  p_confidence NUMERIC,
  p_encounter_type TEXT DEFAULT 'chat'
)
RETURNS TABLE (
  encounter_id UUID,
  success BOOLEAN,
  error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_encounter_id UUID;
BEGIN
  -- Validate inputs
  IF p_user_id IS NULL OR p_distortion_code IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, FALSE, 'Missing required fields';
    RETURN;
  END IF;

  -- Check if distortion code exists
  IF NOT EXISTS (
    SELECT 1 FROM cognitive_distortions WHERE code = p_distortion_code
  ) THEN
    RETURN QUERY SELECT NULL::UUID, FALSE, 'Invalid distortion code';
    RETURN;
  END IF;

  -- Insert encounter atomically
  BEGIN
    INSERT INTO distortion_encounters (
      user_id,
      distortion_code,
      conversation_id,
      original_message_preview,
      reframe_offered,
      reframe_text,
      confidence,
      encounter_type,
      occurred_at
    ) VALUES (
      p_user_id,
      p_distortion_code,
      p_conversation_id,
      p_original_message_preview,
      TRUE,
      p_reframe_text,
      p_confidence,
      p_encounter_type,
      NOW()
    )
    RETURNING id INTO v_encounter_id;

    -- Also record shown interaction
    INSERT INTO coach_interactions (
      user_id,
      encounter_id,
      distortion_code,
      action,
      confidence,
      occurred_at
    ) VALUES (
      p_user_id,
      v_encounter_id,
      p_distortion_code,
      'shown',
      p_confidence,
      NOW()
    );

    RETURN QUERY SELECT v_encounter_id, TRUE, NULL::TEXT;

  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::UUID, FALSE, SQLERRM;
  END;
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION log_coach_encounter TO service_role;

-- Add comment for documentation
COMMENT ON FUNCTION log_coach_encounter IS 
  'Atomically logs a cognitive bias coach encounter with error handling. Returns encounter_id and success status.';
