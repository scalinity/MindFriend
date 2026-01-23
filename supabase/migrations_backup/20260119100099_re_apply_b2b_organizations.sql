-- Workplace Wellness (B2B) — Organization Schema Migration
-- Phase 1: Core Infrastructure
-- Created: 2026-01-19

-- ============================================================================
-- 1. ORGANIZATIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  domain TEXT UNIQUE,  -- For email domain matching (optional)
  logo_url TEXT,
  plan TEXT NOT NULL DEFAULT 'business' CHECK (plan IN ('business', 'enterprise')),
  seat_count INTEGER NOT NULL DEFAULT 10,
  max_seats INTEGER,  -- Plan limit (100 for business, NULL for enterprise = unlimited)

  -- Billing (Stripe integration)
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  billing_email TEXT NOT NULL,
  subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'past_due', 'canceled', 'inactive')),
  grace_period_ends_at TIMESTAMPTZ,

  -- SSO (SAML 2.0)
  saml_org_id TEXT UNIQUE,  -- For SAML configuration matching
  saml_entity_id TEXT,
  saml_acs_url TEXT,
  saml_sso_url TEXT,
  saml_certificate_fingerprint TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_seat_count CHECK (
    seat_count > 0 AND (seat_count <= max_seats OR max_seats IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_organizations_billing_email ON organizations(billing_email);
CREATE INDEX IF NOT EXISTS idx_organizations_domain ON organizations(domain);
CREATE INDEX IF NOT EXISTS idx_organizations_saml_org_id ON organizations(saml_org_id);
CREATE INDEX IF NOT EXISTS idx_organizations_stripe_customer ON organizations(stripe_customer_id);

-- ============================================================================
-- 2. ORGANIZATION ADMINS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS organization_admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'viewer')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_organization_admins_org ON organization_admins(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_admins_user ON organization_admins(user_id);

-- ============================================================================
-- 3. ORGANIZATION MEMBERS TABLE (Employees)
-- ============================================================================

CREATE TABLE IF NOT EXISTS organization_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  removed_at TIMESTAMPTZ,  -- When admin removes member
  finalized_at TIMESTAMPTZ,  -- When 24-hour grace period ends
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_organization_members_org ON organization_members(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_members_user ON organization_members(user_id);
CREATE INDEX IF NOT EXISTS idx_organization_members_is_active ON organization_members(is_active);
CREATE INDEX IF NOT EXISTS idx_organization_members_removed_at ON organization_members(removed_at);

-- ============================================================================
-- 4. ORGANIZATION INVITES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS organization_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  invite_code TEXT NOT NULL UNIQUE,
  max_uses INTEGER,  -- NULL = unlimited uses
  uses INTEGER DEFAULT 0,
  expires_at TIMESTAMPTZ,
  created_by_admin_id UUID NOT NULL REFERENCES organization_admins(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (uses >= 0 AND (max_uses IS NULL OR uses <= max_uses))
);

CREATE INDEX IF NOT EXISTS idx_organization_invites_code ON organization_invites(invite_code);
CREATE INDEX IF NOT EXISTS idx_organization_invites_org ON organization_invites(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_invites_expires ON organization_invites(expires_at);

-- ============================================================================
-- 5. ORGANIZATION METRICS TABLE (Aggregated, Privacy-Protected)
-- ============================================================================

CREATE TABLE IF NOT EXISTS organization_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  metric_date DATE NOT NULL,

  -- Engagement (no user identifiers)
  active_users INTEGER NOT NULL CHECK (active_users >= 5),
  total_sessions INTEGER DEFAULT 0,
  total_exercise_minutes INTEGER DEFAULT 0,

  -- Mood (aggregated with privacy threshold enforced)
  mood_contributor_count INTEGER CHECK (mood_contributor_count IS NULL OR mood_contributor_count >= 5),
  avg_mood_score DECIMAL(3,1),
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining', NULL)),

  -- Challenges (aggregated)
  challenge_participants INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, metric_date)
);

CREATE INDEX IF NOT EXISTS idx_organization_metrics_org_date ON organization_metrics(organization_id, metric_date);

-- ============================================================================
-- 6. PRIVACY ACCESS AUDIT TABLE (Tracks Forbidden Table Access Attempts)
-- ============================================================================

CREATE TABLE IF NOT EXISTS privacy_access_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES auth.users(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  attempted_table TEXT,  -- Which forbidden table was accessed
  query_type TEXT CHECK (query_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),
  status TEXT CHECK (status IN ('blocked', 'logged')),
  reason TEXT,  -- Why blocked
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_privacy_access_audit_admin ON privacy_access_audit(admin_id);
CREATE INDEX IF NOT EXISTS idx_privacy_access_audit_org ON privacy_access_audit(organization_id);
CREATE INDEX IF NOT EXISTS idx_privacy_access_audit_created ON privacy_access_audit(created_at);

-- ============================================================================
-- 7. BILLING AUDIT LOG TABLE (Tracks Stripe Events)
-- ============================================================================

CREATE TABLE IF NOT EXISTS billing_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  event_type TEXT,  -- 'seat_added', 'seat_removed', 'payment_received', 'payment_failed'
  message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_billing_audit_log_org ON billing_audit_log(organization_id);
CREATE INDEX IF NOT EXISTS idx_billing_audit_log_event ON billing_audit_log(event_type);
CREATE INDEX IF NOT EXISTS idx_billing_audit_log_created ON billing_audit_log(created_at);

-- ============================================================================
-- 8. SAML ASSERTIONS TABLE (Replay Prevention)
-- ============================================================================

CREATE TABLE IF NOT EXISTS saml_assertions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assertion_id TEXT NOT NULL UNIQUE,  -- CRITICAL: Uniqueness prevents replay attacks
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  processed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_saml_assertions_org ON saml_assertions(organization_id);
CREATE INDEX IF NOT EXISTS idx_saml_assertions_user ON saml_assertions(user_id);
CREATE INDEX IF NOT EXISTS idx_saml_assertions_processed ON saml_assertions(processed_at);

-- ============================================================================
-- 9. AUDIT LOG TABLE (General)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  event_type TEXT,  -- 'member_joined', 'member_removed', 'report_viewed', 'invite_created'
  actor_id UUID NOT NULL REFERENCES auth.users(id),
  target_user_id UUID REFERENCES auth.users(id),
  changes JSONB,  -- Detailed change data
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_org ON audit_log(organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_event ON audit_log(event_type);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at);

-- ============================================================================
-- 10. UPDATE SUBSCRIPTIONS TABLE FOR B2B SUPPORT
-- ============================================================================

-- Add B2B fields to existing subscriptions table
ALTER TABLE IF EXISTS subscriptions
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS access_source TEXT DEFAULT 'personal' CHECK (access_source IN ('personal', 'organization_sponsored')),
  ADD COLUMN IF NOT EXISTS organization_sponsor_created_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_subscriptions_organization ON subscriptions(organization_id);

-- ============================================================================
-- COMPLETION
-- ============================================================================

-- Grant necessary permissions on public schema
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;

-- Enable RLS on all new B2B tables (policies will be added in next migration)
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy_access_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE saml_assertions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;