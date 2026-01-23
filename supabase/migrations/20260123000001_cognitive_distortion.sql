-- =====================================================
-- Cognitive Distortion Detector Migration
-- =====================================================
-- Description: Creates tables for distortion event tracking and prompt management
-- Security: RLS enabled, encrypted sensitive data, 90-day retention policy
-- Dependencies: auth.users (existing), pgcrypto extension
-- Author: MindFriend Dev Team
-- Date: 2026-01-23
-- =====================================================

-- Enable pgcrypto for encryption
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Distortion event storage with encrypted transcripts
CREATE TABLE IF NOT EXISTS distortion_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    distortion_type TEXT NOT NULL CHECK (distortion_type IN (
        'all_or_nothing',
        'overgeneralization',
        'mental_filter',
        'disqualifying_positive',
        'jumping_to_conclusions',
        'magnification_minimization',
        'emotional_reasoning',
        'should_statements',
        'labeling',
        'personalization'
    )),
    -- SECURITY: Encrypted sensitive mental health data (GDPR Article 32)
    transcript_text_encrypted BYTEA NOT NULL,
    confidence DECIMAL(3,2) CHECK (confidence BETWEEN 0 AND 1),
    detection_method TEXT NOT NULL CHECK (detection_method IN ('llm', 'pattern')),
    user_acknowledged BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_distortion_events_user_date
    ON distortion_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_distortion_events_session
    ON distortion_events(session_id);

-- Prompt display tracking (for rate limiting audit)
CREATE TABLE IF NOT EXISTS distortion_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    -- SECURITY FIX: NOT NULL prevents orphaned prompts
    distortion_event_id UUID NOT NULL REFERENCES distortion_events(id) ON DELETE CASCADE,
    shown_at TIMESTAMPTZ DEFAULT NOW(),
    dismissed BOOLEAN DEFAULT FALSE,
    acknowledged BOOLEAN DEFAULT FALSE,
    dismissed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_distortion_prompts_user_session
    ON distortion_prompts(user_id, session_id, shown_at DESC);

-- Enable RLS
ALTER TABLE distortion_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE distortion_prompts ENABLE ROW LEVEL SECURITY;

-- RLS Policies with conditional creation to avoid duplicates
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_events'
        AND policyname = 'Users read own distortion events'
    ) THEN
        CREATE POLICY "Users read own distortion events"
            ON distortion_events FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_events'
        AND policyname = 'Users insert own distortion events'
    ) THEN
        CREATE POLICY "Users insert own distortion events"
            ON distortion_events FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_events'
        AND policyname = 'Users update own distortion events'
    ) THEN
        CREATE POLICY "Users update own distortion events"
            ON distortion_events FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);  -- SECURITY: Prevent privilege escalation
    END IF;
END $$;

-- GDPR Right to Erasure (Article 17)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_events'
        AND policyname = 'Users delete own distortion events'
    ) THEN
        CREATE POLICY "Users delete own distortion events"
            ON distortion_events FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_prompts'
        AND policyname = 'Users read own prompts'
    ) THEN
        CREATE POLICY "Users read own prompts"
            ON distortion_prompts FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_prompts'
        AND policyname = 'Users insert own prompts'
    ) THEN
        CREATE POLICY "Users insert own prompts"
            ON distortion_prompts FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_prompts'
        AND policyname = 'Users update own prompts'
    ) THEN
        CREATE POLICY "Users update own prompts"
            ON distortion_prompts FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);  -- SECURITY: Prevent privilege escalation
    END IF;
END $$;

-- GDPR Right to Erasure (Article 17)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'distortion_prompts'
        AND policyname = 'Users delete own prompts'
    ) THEN
        CREATE POLICY "Users delete own prompts"
            ON distortion_prompts FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- =====================================================
-- Data Retention & Cleanup (GDPR Article 5)
-- =====================================================

-- Cleanup Function: Delete distortion records older than 90 days
-- SECURITY: GDPR compliance for sensitive mental health data
CREATE OR REPLACE FUNCTION cleanup_old_distortion_events()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM distortion_events
    WHERE created_at < now() - INTERVAL '90 days';

    DELETE FROM distortion_prompts
    WHERE shown_at < now() - INTERVAL '90 days';
END;
$$;

COMMENT ON FUNCTION cleanup_old_distortion_events() IS 'Deletes distortion records older than 90 days (GDPR compliance - runs daily at 2 AM UTC)';

-- Schedule cleanup via pg_cron (requires pg_cron extension)
-- Run daily at 2 AM UTC
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'cleanup-old-distortion-events',
            '0 2 * * *',
            'SELECT cleanup_old_distortion_events()'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Ignore if pg_cron not available
        NULL;
END $$;

-- =====================================================
-- Helper Functions for Encryption/Decryption
-- =====================================================

-- Encrypt transcript text using AES-256
-- Usage: encrypt_transcript('sensitive text', 'encryption-key')
CREATE OR REPLACE FUNCTION encrypt_transcript(
    p_plaintext TEXT,
    p_key TEXT
)
RETURNS BYTEA
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN pgp_sym_encrypt(p_plaintext, p_key, 'cipher-algo=aes256');
END;
$$;

-- Decrypt transcript text
-- Usage: decrypt_transcript(encrypted_data, 'encryption-key')
CREATE OR REPLACE FUNCTION decrypt_transcript(
    p_ciphertext BYTEA,
    p_key TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    RETURN pgp_sym_decrypt(p_ciphertext, p_key);
END;
$$;

COMMENT ON FUNCTION encrypt_transcript IS 'Encrypts transcript text using AES-256 (GDPR Article 32 compliance)';
COMMENT ON FUNCTION decrypt_transcript IS 'Decrypts transcript text';

-- =====================================================
-- Edge Function Integration
-- =====================================================

-- Function to encrypt and store distortion event (called by Edge Function)
-- SECURITY FIX: Removed p_user_id parameter to prevent privilege escalation
CREATE OR REPLACE FUNCTION encrypt_and_store_distortion(
    p_session_id TEXT,
    p_distortion_type TEXT,
    p_transcript_text TEXT,
    p_confidence DECIMAL,
    p_detection_method TEXT,
    p_encryption_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_event_id UUID;
    v_encrypted_text BYTEA;
BEGIN
    -- SECURITY: Verify user is authenticated
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Must be authenticated';
    END IF;

    -- SECURITY: Encrypt sensitive transcript text
    v_encrypted_text := encrypt_transcript(p_transcript_text, p_encryption_key);

    -- Insert distortion event using authenticated user's ID
    INSERT INTO distortion_events (
        user_id,
        session_id,
        distortion_type,
        transcript_text_encrypted,
        confidence,
        detection_method
    ) VALUES (
        auth.uid(),  -- SECURITY FIX: Use caller's ID, not parameter
        p_session_id,
        p_distortion_type,
        v_encrypted_text,
        p_confidence,
        p_detection_method
    ) RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$;

COMMENT ON FUNCTION encrypt_and_store_distortion IS 'Encrypts transcript text and stores distortion event using authenticated user ID (prevents privilege escalation)';

-- Function to get decrypted distortion events for a user
-- SECURITY FIX: Removed p_user_id parameter, added max limit enforcement
CREATE OR REPLACE FUNCTION get_user_distortion_events(
    p_decryption_key TEXT,
    p_limit INT DEFAULT 50
)
RETURNS TABLE(
    id UUID,
    user_id UUID,
    session_id TEXT,
    distortion_type TEXT,
    transcript_text TEXT,
    confidence DECIMAL,
    detection_method TEXT,
    user_acknowledged BOOLEAN,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- SECURITY: Verify user is authenticated
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Must be authenticated';
    END IF;

    -- SECURITY: Enforce maximum limit to prevent resource exhaustion
    IF p_limit > 100 THEN
        RAISE EXCEPTION 'Limit cannot exceed 100';
    END IF;

    RETURN QUERY
    SELECT
        de.id,
        de.user_id,
        de.session_id,
        de.distortion_type,
        decrypt_transcript(de.transcript_text_encrypted, p_decryption_key) AS transcript_text,
        de.confidence,
        de.detection_method,
        de.user_acknowledged,
        de.created_at
    FROM distortion_events de
    WHERE de.user_id = auth.uid()  -- SECURITY FIX: Only authenticated user's data
    ORDER BY de.created_at DESC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION get_user_distortion_events IS 'Returns decrypted distortion events for authenticated user only (prevents unauthorized access)';

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON distortion_events TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON distortion_prompts TO authenticated;

-- =====================================================
-- SECURITY IMPLEMENTATION NOTES
-- =====================================================
-- 1. Encryption Key: Store in Supabase Edge Function secrets as DISTORTION_ENCRYPTION_KEY
-- 2. Client Flow:
--    - Client sends plaintext transcript_text to Edge Function
--    - Edge Function encrypts using encrypt_transcript() before INSERT
--    - Edge Function decrypts using decrypt_transcript() before SELECT
--    - Clients never handle encryption keys or encrypted data directly
-- 3. Database stores only encrypted data (transcript_text_encrypted BYTEA)
-- 4. RLS policies prevent unauthorized access to encrypted data
-- 5. 90-day retention ensures minimal data exposure window (GDPR Article 5)
-- 6. Users can delete their own data (GDPR Article 17 - Right to Erasure)
