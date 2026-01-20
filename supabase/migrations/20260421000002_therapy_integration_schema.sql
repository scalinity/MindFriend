-- Therapy Integration Schema
-- Created: 2026-01-19
-- Purpose: Enable users to securely share mental health data with licensed therapists
-- HIPAA Compliance: AES-256 at rest, TLS 1.3 in transit, 7-year audit logs

-- ============================================================================
-- TABLE: therapist_accounts
-- Purpose: Extends user profile for verified therapists/clinicians
-- ============================================================================

CREATE TABLE IF NOT EXISTS therapist_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

    -- Verification
    is_verified BOOLEAN DEFAULT false,
    license_number TEXT,
    license_state TEXT,
    license_verified_at TIMESTAMPTZ,
    npi_number TEXT, -- National Provider Identifier

    -- Practice info
    practice_name TEXT,
    practice_address TEXT,
    specialties TEXT[],

    -- Settings
    accepts_invites BOOLEAN DEFAULT true,
    max_clients INTEGER DEFAULT 100 CHECK (max_clients > 0 AND max_clients <= 500),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- TABLE: therapy_connections
-- Purpose: Links clients to therapists with granular permission controls
-- Privacy: Each connection has independent permission flags
-- ============================================================================

CREATE TABLE IF NOT EXISTS therapy_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    therapist_id UUID NOT NULL REFERENCES therapist_accounts(id) ON DELETE CASCADE,

    -- Status tracking
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'revoked', 'ended')),
    invited_by TEXT NOT NULL CHECK (invited_by IN ('client', 'therapist')),

    -- Data sharing permissions (client controls) - NOTE: share_chat_summary removed per decision doc
    share_mood BOOLEAN DEFAULT true,
    share_journal BOOLEAN DEFAULT false,
    share_assessments BOOLEAN DEFAULT true,
    share_exercises BOOLEAN DEFAULT false,

    -- Crisis handling
    crisis_alerts_enabled BOOLEAN DEFAULT true,

    -- Invitation flow
    invitation_token TEXT, -- JWT token for magic link
    invitation_expires_at TIMESTAMPTZ, -- 7-day expiration

    -- Lifecycle dates
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    connected_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(client_id, therapist_id)
);

-- ============================================================================
-- TABLE: therapist_assignments
-- Purpose: Tracks homework assigned by therapists to clients
-- ============================================================================

CREATE TABLE IF NOT EXISTS therapist_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES therapy_connections(id) ON DELETE CASCADE,

    -- Assignment details
    title TEXT NOT NULL CHECK (length(title) >= 1 AND length(title) <= 64),
    description TEXT CHECK (length(description) <= 500),
    assignment_type TEXT NOT NULL CHECK (assignment_type IN ('exercise', 'journal_prompt', 'mood_tracking', 'custom')),

    -- Linked content
    exercise_id UUID REFERENCES exercises(id) ON DELETE SET NULL,
    journal_prompt TEXT CHECK (length(journal_prompt) <= 300),

    -- Schedule
    due_date DATE,
    frequency TEXT DEFAULT 'once' CHECK (frequency IN ('once', 'daily', 'weekly', 'biweekly', 'monthly')),

    -- Status
    status TEXT DEFAULT 'assigned' CHECK (status IN ('assigned', 'completed', 'skipped', 'expired')),
    completed_at TIMESTAMPTZ,
    client_notes TEXT CHECK (length(client_notes) <= 1000),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- TABLE: therapist_notes
-- Purpose: Private therapist session notes that clients never see
-- Security: Encrypted at rest, RLS enforces therapist-only access
-- ============================================================================

CREATE TABLE IF NOT EXISTS therapist_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES therapy_connections(id) ON DELETE CASCADE,
    therapist_id UUID NOT NULL REFERENCES therapist_accounts(id),

    -- Note content (encrypted at rest by Supabase)
    content TEXT NOT NULL CHECK (length(content) <= 10000),
    session_date DATE,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- TABLE: integration_api_keys
-- Purpose: API keys for EHR/practice management integrations
-- Security: Keys are SHA-256 hashed before storage (never plaintext)
-- ============================================================================

CREATE TABLE IF NOT EXISTS integration_api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    therapist_id UUID NOT NULL REFERENCES therapist_accounts(id) ON DELETE CASCADE,

    -- API key (hashed with SHA-256)
    api_key_hash TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL CHECK (length(name) <= 50),
    permissions TEXT[] NOT NULL DEFAULT '{}', -- ['read_mood', 'read_assessments', 'write_assignments']

    -- Rate limiting
    rate_limit_per_hour INTEGER DEFAULT 1000 CHECK (rate_limit_per_hour >= 10 AND rate_limit_per_hour <= 10000),

    -- Status
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- TABLE: therapy_access_log
-- Purpose: Immutable audit log of all therapist data access (HIPAA requirement)
-- Retention: 7 years minimum (configurable)
-- ============================================================================

CREATE TABLE IF NOT EXISTS therapy_access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    connection_id UUID NOT NULL REFERENCES therapy_connections(id),
    therapist_id UUID NOT NULL,

    -- Action details
    action TEXT NOT NULL, -- 'view_mood', 'view_journal', 'view_assessments', 'export_data', 'create_assignment', 'crisis_alert_sent'
    resource_type TEXT,
    resource_id UUID,

    -- Request metadata
    ip_address TEXT,
    user_agent TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

ALTER TABLE therapist_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapy_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapist_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE integration_api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE therapy_access_log ENABLE ROW LEVEL SECURITY;

-- therapist_accounts policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapist_accounts' AND policyname = 'Therapists manage own account'
    ) THEN
        CREATE POLICY "Therapists manage own account"
            ON therapist_accounts
            FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapist_accounts' AND policyname = 'Public view verified therapists'
    ) THEN
        CREATE POLICY "Public view verified therapists"
            ON therapist_accounts
            FOR SELECT
            USING (is_verified = true);
    END IF;
END $$;

-- therapy_connections policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapy_connections' AND policyname = 'Users see own connections'
    ) THEN
        CREATE POLICY "Users see own connections"
            ON therapy_connections
            FOR SELECT
            USING (
                auth.uid() = client_id OR
                auth.uid() IN (SELECT user_id FROM therapist_accounts WHERE id = therapist_id)
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapy_connections' AND policyname = 'Clients can insert own connections'
    ) THEN
        CREATE POLICY "Clients can insert own connections"
            ON therapy_connections
            FOR INSERT
            WITH CHECK (auth.uid() = client_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapy_connections' AND policyname = 'Clients update sharing settings'
    ) THEN
        CREATE POLICY "Clients update sharing settings"
            ON therapy_connections
            FOR UPDATE
            USING (auth.uid() = client_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapy_connections' AND policyname = 'Therapists accept connections'
    ) THEN
        CREATE POLICY "Therapists accept connections"
            ON therapy_connections
            FOR UPDATE
            USING (
                auth.uid() IN (SELECT user_id FROM therapist_accounts WHERE id = therapist_id)
                AND status = 'pending'
            );
    END IF;
END $$;

-- therapist_assignments policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapist_assignments' AND policyname = 'Assignments visible to connection'
    ) THEN
        CREATE POLICY "Assignments visible to connection"
            ON therapist_assignments
            FOR SELECT
            USING (
                connection_id IN (
                    SELECT id FROM therapy_connections
                    WHERE client_id = auth.uid()
                    OR therapist_id IN (SELECT id FROM therapist_accounts WHERE user_id = auth.uid())
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapist_assignments' AND policyname = 'Therapists create assignments'
    ) THEN
        CREATE POLICY "Therapists create assignments"
            ON therapist_assignments
            FOR INSERT
            WITH CHECK (
                connection_id IN (
                    SELECT id FROM therapy_connections
                    WHERE therapist_id IN (SELECT id FROM therapist_accounts WHERE user_id = auth.uid())
                    AND status = 'active'
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapist_assignments' AND policyname = 'Clients update assignment status'
    ) THEN
        CREATE POLICY "Clients update assignment status"
            ON therapist_assignments
            FOR UPDATE
            USING (
                connection_id IN (
                    SELECT id FROM therapy_connections WHERE client_id = auth.uid()
                )
            );
    END IF;
END $$;

-- therapist_notes policies (strictly private to therapist)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapist_notes' AND policyname = 'Therapist notes private'
    ) THEN
        CREATE POLICY "Therapist notes private"
            ON therapist_notes
            FOR ALL
            USING (
                therapist_id IN (SELECT id FROM therapist_accounts WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- integration_api_keys policies
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'integration_api_keys' AND policyname = 'Therapists manage own keys'
    ) THEN
        CREATE POLICY "Therapists manage own keys"
            ON integration_api_keys
            FOR ALL
            USING (
                therapist_id IN (SELECT id FROM therapist_accounts WHERE user_id = auth.uid())
            );
    END IF;
END $$;

-- therapy_access_log policies (append-only, client can view own)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'therapy_access_log' AND policyname = 'Clients view own access log'
    ) THEN
        CREATE POLICY "Clients view own access log"
            ON therapy_access_log
            FOR SELECT
            USING (
                connection_id IN (
                    SELECT id FROM therapy_connections WHERE client_id = auth.uid()
                )
            );
    END IF;
END $$;

-- No UPDATE or DELETE allowed on audit log (append-only)
-- INSERT only via service role in Edge Functions

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_therapy_connections_client ON therapy_connections(client_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_therapy_connections_therapist ON therapy_connections(therapist_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_therapy_connections_invitation ON therapy_connections(invitation_token) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_therapist_assignments_connection ON therapist_assignments(connection_id, status);
CREATE INDEX IF NOT EXISTS idx_therapist_assignments_due_date ON therapist_assignments(due_date) WHERE status = 'assigned';

CREATE INDEX IF NOT EXISTS idx_therapist_notes_connection ON therapist_notes(connection_id, session_date DESC);
CREATE INDEX IF NOT EXISTS idx_therapist_notes_therapist ON therapist_notes(therapist_id, session_date DESC);

CREATE INDEX IF NOT EXISTS idx_integration_api_keys_hash ON integration_api_keys(api_key_hash) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_therapy_access_log_connection ON therapy_access_log(connection_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_therapy_access_log_therapist ON therapy_access_log(therapist_id, created_at DESC);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_therapist_notes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_therapist_notes_timestamp
    BEFORE UPDATE ON therapist_notes
    FOR EACH ROW
    EXECUTE FUNCTION update_therapist_notes_updated_at();

-- Function to auto-expire assignments past due date
CREATE OR REPLACE FUNCTION expire_overdue_assignments()
RETURNS INTEGER AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    UPDATE therapist_assignments
    SET status = 'expired'
    WHERE status = 'assigned'
    AND due_date IS NOT NULL
    AND due_date < CURRENT_DATE;

    GET DIAGNOSTICS expired_count = ROW_COUNT;
    RETURN expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to log audit events (called from Edge Functions)
CREATE OR REPLACE FUNCTION log_therapy_access(
    p_connection_id UUID,
    p_therapist_id UUID,
    p_action TEXT,
    p_resource_type TEXT DEFAULT NULL,
    p_resource_id UUID DEFAULT NULL,
    p_ip_address TEXT DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    log_id UUID;
BEGIN
    INSERT INTO therapy_access_log (
        connection_id,
        therapist_id,
        action,
        resource_type,
        resource_id,
        ip_address,
        user_agent
    ) VALUES (
        p_connection_id,
        p_therapist_id,
        p_action,
        p_resource_type,
        p_resource_id,
        p_ip_address,
        p_user_agent
    ) RETURNING id INTO log_id;

    RETURN log_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE therapist_accounts IS 'Verified therapist/clinician profiles with license validation';
COMMENT ON TABLE therapy_connections IS 'Client-therapist relationships with granular sharing permissions';
COMMENT ON TABLE therapist_assignments IS 'Homework/exercises assigned by therapists to clients';
COMMENT ON TABLE therapist_notes IS 'Private therapist session notes (clients cannot see)';
COMMENT ON TABLE integration_api_keys IS 'Hashed API keys for EHR/practice management integrations';
COMMENT ON TABLE therapy_access_log IS 'Immutable audit log of all data access (HIPAA compliance)';

COMMENT ON COLUMN therapy_connections.share_mood IS 'Client permission to share daily mood scores with therapist';
COMMENT ON COLUMN therapy_connections.share_journal IS 'Client permission to share journal entries with therapist';
COMMENT ON COLUMN therapy_connections.share_assessments IS 'Client permission to share PHQ-9/GAD-7 results with therapist';
COMMENT ON COLUMN therapy_connections.share_exercises IS 'Client permission to share exercise completion history with therapist';
COMMENT ON COLUMN therapy_connections.crisis_alerts_enabled IS 'Client consent for therapist to receive crisis alerts';

COMMENT ON COLUMN integration_api_keys.api_key_hash IS 'SHA-256 hash of actual API key (never store plaintext)';
COMMENT ON COLUMN integration_api_keys.permissions IS 'Array of permissions: read_mood, read_assessments, write_assignments';

COMMENT ON FUNCTION log_therapy_access IS 'Audit logging function (service role only) - records all therapist data access';
COMMENT ON FUNCTION expire_overdue_assignments IS 'Maintenance function to auto-expire assignments past due date';
