-- Migration: Advanced Integrations Schema
-- Created: 2026-01-20
-- Purpose: Adds database support for calendar, travel, notes, smart home, wearable, and healthcare integrations

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- INTEGRATIONS TABLE
-- Stores connected third-party integrations
-- ============================================
CREATE TABLE IF NOT EXISTS integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    integration_type VARCHAR(50) NOT NULL,
    provider_id VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    scopes JSONB DEFAULT '[]'::jsonb,
    last_sync_at TIMESTAMPTZ,
    sync_error TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_user_integration UNIQUE (user_id, integration_type)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_integrations_user_id ON integrations(user_id);
CREATE INDEX IF NOT EXISTS idx_integrations_type ON integrations(integration_type);
CREATE INDEX IF NOT EXISTS idx_integrations_status ON integrations(status);

-- ============================================
-- INTEGRATION TOKENS TABLE (Encrypted)
-- Stores OAuth tokens (encrypted at application layer)
-- Note: Actual tokens stored encrypted in iOS Keychain,
-- this table tracks token metadata only
-- ============================================
CREATE TABLE IF NOT EXISTS integration_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    token_type VARCHAR(50) NOT NULL,
    encrypted_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- CALENDAR EVENTS TABLE
-- Cached calendar events for stress analysis
-- ============================================
CREATE TABLE IF NOT EXISTS calendar_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    integration_type VARCHAR(50) NOT NULL,
    provider_event_id VARCHAR(255) NOT NULL,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    is_all_day BOOLEAN DEFAULT FALSE,
    location VARCHAR(500),
    attendees_count INTEGER DEFAULT 0,
    meeting_type VARCHAR(50),
    stress_score DECIMAL(3,2),
    is_private BOOLEAN DEFAULT FALSE,
    raw_data JSONB DEFAULT '{}'::jsonb,
    synced_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_provider_event UNIQUE (user_id, provider_event_id)
);

CREATE INDEX IF NOT EXISTS idx_calendar_events_user_id ON calendar_events(user_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_start_time ON calendar_events(start_time);
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_date ON calendar_events(user_id, start_time);

-- ============================================
-- TRAVEL ITINERARIES TABLE
-- Cached travel data from TripIt, FlightAware
-- ============================================
CREATE TABLE IF NOT EXISTS travel_itineraries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    integration_type VARCHAR(50) NOT NULL,
    provider_trip_id VARCHAR(255) NOT NULL,
    confirmation_number VARCHAR(100),
    origin_code VARCHAR(10),
    origin_city VARCHAR(255),
    origin_timezone VARCHAR(50),
    destination_code VARCHAR(10),
    destination_city VARCHAR(255),
    destination_timezone VARCHAR(50),
    departure_time TIMESTAMPTZ,
    arrival_time TIMESTAMPTZ,
    flight_number VARCHAR(50),
    carrier VARCHAR(100),
    status VARCHAR(50) DEFAULT 'scheduled',
    raw_data JSONB DEFAULT '{}'::jsonb,
    synced_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_provider_trip UNIQUE (user_id, provider_trip_id)
);

CREATE INDEX IF NOT EXISTS idx_travel_itineraries_user_id ON travel_itineraries(user_id);
CREATE INDEX IF NOT EXISTS idx_travel_itineraries_departure ON travel_itineraries(departure_time);

-- ============================================
-- NOTE EXPORTS TABLE
-- Tracks journal exports to note-taking apps
-- ============================================
CREATE TABLE IF NOT EXISTS note_exports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    journal_entry_id UUID NOT NULL,
    target_app VARCHAR(50) NOT NULL,
    provider_note_id VARCHAR(255),
    content TEXT NOT NULL,
    tags JSONB DEFAULT '[]'::jsonb,
    mood_score DECIMAL(3,2),
    sync_status VARCHAR(20) DEFAULT 'pending',
    synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_note_exports_user_id ON note_exports(user_id);
CREATE INDEX IF NOT EXISTS idx_note_exports_journal ON note_exports(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_note_exports_status ON note_exports(sync_status);

-- ============================================
-- SMART HOME SCENES TABLE
-- User's smart home automation preferences
-- ============================================
CREATE TABLE IF NOT EXISTS smart_home_scenes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scene_type VARCHAR(50) NOT NULL,
    scene_name VARCHAR(255) NOT NULL,
    actions JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_enabled BOOLEAN DEFAULT TRUE,
    trigger_time TIME,
    trigger_days INTEGER[], -- Array of days (1=Monday, 7=Sunday)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_smart_home_scenes_user_id ON smart_home_scenes(user_id);

-- ============================================
-- WEARABLE DATA TABLE
-- Cached wearable device data
-- ============================================
CREATE TABLE IF NOT EXISTS wearable_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_type VARCHAR(50) NOT NULL,
    data_type VARCHAR(50) NOT NULL,
    value DECIMAL(10,2),
    unit VARCHAR(20),
    recorded_at TIMESTAMPTZ NOT NULL,
    synced_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wearable_data_user_id ON wearable_data(user_id);
CREATE INDEX IF NOT EXISTS idx_wearable_data_recorded ON wearable_data(recorded_at);
CREATE INDEX IF NOT EXISTS idx_wearable_data_type ON wearable_data(data_type);

-- ============================================
-- FHIR RESOURCES TABLE
-- Stores FHIR-formatted health data exports
-- ============================================
CREATE TABLE IF NOT EXISTS fhir_resources (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    resource_type VARCHAR(50) NOT NULL, -- Observation, QuestionnaireResponse, etc.
    fhir_id VARCHAR(255) NOT NULL,
    resource_json JSONB NOT NULL,
    source_table VARCHAR(50), -- Original table that generated this
    source_id UUID, -- Original record ID
    shared_with_provider BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fhir_resources_user_id ON fhir_resources(user_id);
CREATE INDEX IF NOT EXISTS idx_fhir_resources_type ON fhir_resources(resource_type);
CREATE INDEX IF NOT EXISTS idx_fhir_resources_shared ON fhir_resources(shared_with_provider);

-- ============================================
-- HIPAA AUDIT LOG TABLE
-- Tracks all access to PHI for compliance
-- ============================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    resource_id VARCHAR(255),
    actor_type VARCHAR(50) NOT NULL, -- 'user', 'provider', 'system', 'api'
    actor_id VARCHAR(255),
    ip_address INET,
    user_agent TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON audit_logs(resource_type, resource_id);

-- ============================================
-- API RATE LIMITS TABLE
-- Tracks API usage for rate limiting
-- ============================================
CREATE TABLE IF NOT EXISTS api_rate_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    api_tier VARCHAR(50) NOT NULL DEFAULT 'free',
    requests_count INTEGER DEFAULT 0,
    period_start TIMESTAMPTZ DEFAULT NOW(),
    period_end TIMESTAMPTZ,
    last_request_at TIMESTAMPTZ,

    CONSTRAINT unique_user_period UNIQUE (user_id, period_start)
);

CREATE INDEX IF NOT EXISTS idx_api_rate_limits_user_id ON api_rate_limits(user_id);

-- ============================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================

ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE integration_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE travel_itineraries ENABLE ROW LEVEL SECURITY;
ALTER TABLE note_exports ENABLE ROW LEVEL SECURITY;
ALTER TABLE smart_home_scenes ENABLE ROW LEVEL SECURITY;
ALTER TABLE wearable_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE fhir_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_rate_limits ENABLE ROW LEVEL SECURITY;

-- Users can only access their own integration data
CREATE POLICY "Users can view own integrations" ON integrations
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own integrations" ON integrations
    FOR ALL USING (auth.uid() = user_id);

-- Calendar events - private by default
CREATE POLICY "Users can view own calendar events" ON calendar_events
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own calendar events" ON calendar_events
    FOR ALL USING (auth.uid() = user_id);

-- Travel itineraries
CREATE POLICY "Users can view own travel data" ON travel_itineraries
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own travel data" ON travel_itineraries
    FOR ALL USING (auth.uid() = user_id);

-- Note exports
CREATE POLICY "Users can view own note exports" ON note_exports
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own note exports" ON note_exports
    FOR ALL USING (auth.uid() = user_id);

-- Smart home scenes
CREATE POLICY "Users can view own smart home scenes" ON smart_home_scenes
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own smart home scenes" ON smart_home_scenes
    FOR ALL USING (auth.uid() = user_id);

-- Wearable data
CREATE POLICY "Users can view own wearable data" ON wearable_data
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own wearable data" ON wearable_data
    FOR ALL USING (auth.uid() = user_id);

-- FHIR resources - can be shared with providers
CREATE POLICY "Users can view own FHIR resources" ON fhir_resources
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own FHIR resources" ON fhir_resources
    FOR ALL USING (auth.uid() = user_id);

-- Audit logs - users can only see their own, providers see shared access
CREATE POLICY "Users can view own audit logs" ON audit_logs
    FOR SELECT USING (auth.uid() = user_id);

-- API rate limits
CREATE POLICY "Users can view own rate limits" ON api_rate_limits
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own rate limits" ON api_rate_limits
    FOR ALL USING (auth.uid() = user_id);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers
CREATE TRIGGER update_integrations_updated_at
    BEFORE UPDATE ON integrations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_smart_home_scenes_updated_at
    BEFORE UPDATE ON smart_home_scenes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to log audit events
CREATE OR REPLACE FUNCTION log_audit_event(
    p_user_id UUID,
    p_action VARCHAR,
    p_resource_type VARCHAR,
    p_resource_id VARCHAR,
    p_actor_type VARCHAR,
    p_actor_id VARCHAR,
    p_details JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO audit_logs (
        user_id, action, resource_type, resource_id,
        actor_type, actor_id, details
    ) VALUES (
        p_user_id, p_action, p_resource_type, p_resource_id,
        p_actor_type, p_actor_id, p_details
    );
END;
$$ language 'plpgsql' SECURITY DEFINER;

-- ============================================
-- SAMPLE DATA
-- ============================================

-- Insert default smart home scene templates
INSERT INTO smart_home_scenes (user_id, scene_type, scene_name, actions, is_enabled)
VALUES
    ('00000000-0000-0000-0000-000000000000', 'wind_down', 'Evening Wind Down', '[{"device_type": "light", "action": "dim", "value": "10"}, {"device_type": "thermostat", "action": "set_temp", "value": "68"}]', TRUE),
    ('00000000-0000-0000-0000-000000000000', 'sleep', 'Bedtime', '[{"device_type": "thermostat", "action": "set_temp", "value": "66"}, {"device_type": "light", "action": "off"}, {"device_type": "lock", "action": "lock"}]', TRUE),
    ('00000000-0000-0000-0000-000000000000', 'wake_up', 'Morning Wake Up', '[{"device_type": "light", "action": "dim", "value": "50"}, {"device_type": "thermostat", "action": "set_temp", "value": "70"}]', TRUE)
ON CONFLICT DO NOTHING;
