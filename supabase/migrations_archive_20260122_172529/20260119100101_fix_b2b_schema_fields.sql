-- Fix B2B Schema Fields
-- Adds missing status and seat_delta fields required by tests
-- Created: 2026-01-19

-- ============================================================================
-- 1. Add 'status' field to organizations table
-- ============================================================================

-- The organizations table needs both subscription_status (Stripe status) and
-- status (overall organization status) for proper lifecycle management

ALTER TABLE organizations
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active' CHECK (status IN ('active', 'past_due', 'inactive', 'churned'));

-- Create index for querying by status
CREATE INDEX IF NOT EXISTS idx_organizations_status ON organizations(status);

-- ============================================================================
-- 2. Add 'seat_delta' field to billing_audit_log table
-- ============================================================================

-- Tests expect seat_delta to track seat count changes explicitly
ALTER TABLE billing_audit_log
  ADD COLUMN IF NOT EXISTS seat_delta INTEGER;

-- ============================================================================
-- 3. Add missing test-required columns
-- ============================================================================

-- Tests reference these columns that may be missing from schema
ALTER TABLE organization_invites
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

ALTER TABLE privacy_access_audit
  ADD COLUMN IF NOT EXISTS admin_user_id UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS blocked_at TIMESTAMPTZ DEFAULT NOW();

-- Add index for privacy audit lookups
CREATE INDEX IF NOT EXISTS idx_privacy_access_audit_admin_user ON privacy_access_audit(admin_user_id);

-- ============================================================================
-- 4. Test schema alignment columns
-- ============================================================================

-- Add columns referenced in test files
ALTER TABLE organizations
  ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS seats_used INTEGER DEFAULT 0;

-- Add indexes for commonly queried fields
CREATE INDEX IF NOT EXISTS idx_organizations_slug ON organizations(slug);
CREATE INDEX IF NOT EXISTS idx_organizations_seats_used ON organizations(seats_used);

-- Update constraint to ensure seats_used doesn't exceed seat_count
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'seats_used_valid'
    AND table_name = 'organizations'
  ) THEN
    ALTER TABLE organizations
      ADD CONSTRAINT seats_used_valid CHECK (seats_used >= 0 AND seats_used <= seat_count);
  END IF;
END $$;

-- ============================================================================
-- 5. SAML test columns
-- ============================================================================

-- Add columns for SAML test scenarios
ALTER TABLE saml_assertions
  ADD COLUMN IF NOT EXISTS user_email TEXT,
  ADD COLUMN IF NOT EXISTS not_on_or_after TIMESTAMPTZ;

-- Index for SAML assertion expiry checks
CREATE INDEX IF NOT EXISTS idx_saml_assertions_expiry ON saml_assertions(not_on_or_after);

-- ============================================================================
-- 6. Organization invites test columns
-- ============================================================================

-- Tests expect uses_count, not uses
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'organization_invites'
    AND column_name = 'uses'
  ) THEN
    ALTER TABLE organization_invites RENAME COLUMN uses TO uses_count;
  END IF;
END $$;

-- Add index for active invites
CREATE INDEX IF NOT EXISTS idx_organization_invites_active ON organization_invites(is_active);

-- ============================================================================
-- 7. Audit log metadata field
-- ============================================================================

-- Ensure audit_log has metadata column
-- If changes exists but metadata doesn't, rename; if both exist, drop changes
DO $$
BEGIN
  -- Check if metadata already exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'audit_log' AND column_name = 'metadata'
  ) THEN
    -- If changes exists, rename it to metadata
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'audit_log' AND column_name = 'changes'
    ) THEN
      ALTER TABLE audit_log RENAME COLUMN changes TO metadata;
    ELSE
      -- Neither exists, create metadata
      ALTER TABLE audit_log ADD COLUMN metadata JSONB;
    END IF;
  ELSE
    -- Metadata exists, drop changes if it exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'audit_log' AND column_name = 'changes'
    ) THEN
      ALTER TABLE audit_log DROP COLUMN changes;
    END IF;
  END IF;
END $$;

-- ============================================================================
-- COMPLETION
-- ============================================================================

COMMENT ON COLUMN organizations.status IS 'Overall organization lifecycle status (active, past_due, inactive, churned)';
COMMENT ON COLUMN organizations.subscription_status IS 'Stripe subscription status (active, past_due, canceled, inactive)';
COMMENT ON COLUMN billing_audit_log.seat_delta IS 'Change in seat count for seat_change events';
COMMENT ON COLUMN organizations.seats_used IS 'Number of seats currently occupied by active members';
