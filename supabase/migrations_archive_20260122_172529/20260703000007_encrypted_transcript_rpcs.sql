-- MindFriend: Encrypted Transcript RPC Functions
-- Purpose: Handle encryption/decryption transparently for Edge Functions
-- Created: 2026-01-22

-- Helper: Get decrypted transcript for a session
CREATE OR REPLACE FUNCTION get_decrypted_transcript(p_session_id UUID, p_user_id UUID)
RETURNS TABLE (transcript TEXT, success BOOLEAN, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_encrypted_transcript BYTEA;
  v_decrypted_text TEXT;
BEGIN
  -- Only allow users to decrypt their own transcripts
  SELECT transcript INTO v_encrypted_transcript
  FROM rehearsal_sessions
  WHERE id = p_session_id
    AND user_id = p_user_id;

  IF v_encrypted_transcript IS NULL THEN
    RETURN QUERY SELECT NULL::TEXT, FALSE::BOOLEAN, 'Session not found'::TEXT;
    RETURN;
  END IF;

  -- Decrypt the transcript
  v_decrypted_text := pgp_sym_decrypt(
    v_encrypted_transcript,
    current_setting('app.encryption_key'),
    'cipher-algo=aes256'
  );

  RETURN QUERY SELECT v_decrypted_text::TEXT, TRUE::BOOLEAN, NULL::TEXT;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT NULL::TEXT, FALSE::BOOLEAN, 'Decryption failed: ' || SQLERRM::TEXT;
END;
$$;

-- Helper: Update encrypted transcript atomically
CREATE OR REPLACE FUNCTION update_encrypted_transcript(
  p_session_id UUID,
  p_user_id UUID,
  p_transcript_json TEXT,
  p_total_exchanges INTEGER
)
RETURNS TABLE (success BOOLEAN, error_message TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_exists BOOLEAN;
  v_encrypted_transcript BYTEA;
BEGIN
  -- Check if session exists and belongs to user (with row lock)
  SELECT EXISTS(
    SELECT 1 FROM rehearsal_sessions
    WHERE id = p_session_id
      AND user_id = p_user_id
      AND status = 'active'
    FOR UPDATE
  ) INTO v_session_exists;

  IF NOT v_session_exists THEN
    RETURN QUERY SELECT FALSE::BOOLEAN, 'Session not found or not active'::TEXT;
    RETURN;
  END IF;

  -- Encrypt the new transcript
  v_encrypted_transcript := pgp_sym_encrypt(
    p_transcript_json,
    current_setting('app.encryption_key'),
    'cipher-algo=aes256'
  );

  -- Update transcript atomically within same transaction
  UPDATE rehearsal_sessions
  SET
    transcript = v_encrypted_transcript,
    total_exchanges = p_total_exchanges,
    updated_at = NOW()
  WHERE id = p_session_id
    AND user_id = p_user_id;

  RETURN QUERY SELECT TRUE::BOOLEAN, NULL::TEXT;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE::BOOLEAN, SQLERRM::TEXT;
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_decrypted_transcript(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_encrypted_transcript(UUID, UUID, TEXT, INTEGER) TO authenticated;

COMMENT ON FUNCTION get_decrypted_transcript IS
'Decrypts and returns transcript for a session. Only accessible to session owner.';

COMMENT ON FUNCTION update_encrypted_transcript IS
'Atomically updates encrypted transcript with row-level locking to prevent race conditions.';
