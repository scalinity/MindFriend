-- Migration: Monetization Improvements
-- Adds family/couples plans, annual billing, and premium badges
-- Spec: specs/08-monetization.md

-- =============================================================================
-- MARK: - Subscriptions (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  original_transaction_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'cancelled', 'grace_period')),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'subscriptions' AND policyname = 'Users can view own subscription'
  ) THEN
    CREATE POLICY "Users can view own subscription" ON subscriptions
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- PART 1: Extend subscriptions table for plan types
-- =============================================================================

-- Add new columns for plan type tracking
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS plan_type TEXT DEFAULT 'individual';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS billing_period TEXT DEFAULT 'monthly';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS family_id UUID;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS is_family_admin BOOLEAN DEFAULT FALSE;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS seats_used INT DEFAULT 1;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS seats_total INT DEFAULT 1;

-- Add constraint for valid plan types (if not exists, drop and recreate)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_plan_type'
  ) THEN
    ALTER TABLE subscriptions ADD CONSTRAINT valid_plan_type
      CHECK (plan_type IN ('individual', 'couples', 'family'));
  END IF;
END $$;

-- Add constraint for valid billing periods
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_billing_period'
  ) THEN
    ALTER TABLE subscriptions ADD CONSTRAINT valid_billing_period
      CHECK (billing_period IN ('monthly', 'annual'));
  END IF;
END $$;

-- =============================================================================
-- PART 2: Family groups table
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT DEFAULT 'My Family',
  admin_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Reference to auto-created circle for family members
  circle_id UUID REFERENCES circles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_family_groups_admin ON family_groups(admin_user_id);

ALTER TABLE family_groups ENABLE ROW LEVEL SECURITY;

-- Admin can do everything with their family group
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_groups' AND policyname = 'Admin manages family group') THEN
    CREATE POLICY "Admin manages family group" ON family_groups FOR ALL USING (auth.uid() = admin_user_id);
  END IF;
END $$;

-- =============================================================================
-- PART 3: Family members table (MUST come before family_groups member policy)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_email TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'removed')),
  invited_at TIMESTAMPTZ DEFAULT NOW(),
  joined_at TIMESTAMPTZ,
  removed_at TIMESTAMPTZ,
  UNIQUE(family_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_family_members_family_id ON family_members(family_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user_id ON family_members(user_id);
CREATE INDEX IF NOT EXISTS idx_family_members_status ON family_members(status);

ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;

-- Admin can manage all family members
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_members' AND policyname = 'Admin manages family members') THEN
    CREATE POLICY "Admin manages family members" ON family_members FOR ALL USING (
      EXISTS (SELECT 1 FROM family_groups fg WHERE fg.id = family_id AND fg.admin_user_id = auth.uid())
    );
  END IF;
END $$;

-- Members can view other members in their family
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_members' AND policyname = 'View family members') THEN
    CREATE POLICY "View family members" ON family_members FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM family_groups fg
        WHERE fg.id = family_id
        AND (fg.admin_user_id = auth.uid() OR EXISTS (
          SELECT 1 FROM family_members fm WHERE fm.family_id = fg.id AND fm.user_id = auth.uid() AND fm.status = 'active'
        ))
      )
    );
  END IF;
END $$;

-- Users can view their own membership
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_members' AND policyname = 'View own membership') THEN
    CREATE POLICY "View own membership" ON family_members FOR SELECT USING (user_id = auth.uid());
  END IF;
END $$;

-- =============================================================================
-- PART 3b: Family groups member policy (after family_members exists)
-- =============================================================================

-- Members can view their family group (via family_members check)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_groups' AND policyname = 'Members can view family group') THEN
    CREATE POLICY "Members can view family group" ON family_groups FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM family_members fm
        WHERE fm.family_id = id AND fm.user_id = auth.uid() AND fm.status = 'active'
      )
    );
  END IF;
END $$;

-- =============================================================================
-- PART 4: Family invitations table (update existing table from earlier migration)
-- =============================================================================

-- Table already exists from 20260116100000_family_wellness_schema.sql, add missing columns
CREATE TABLE IF NOT EXISTS family_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add columns that may not exist in earlier schema
ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS invite_code TEXT;
ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '7 days';
ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- Add unique constraint on invite_code if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'family_invitations_invite_code_key'
  ) THEN
    ALTER TABLE family_invitations ADD CONSTRAINT family_invitations_invite_code_key UNIQUE (invite_code);
  END IF;
END $$;

-- Drop old columns that don't match new schema
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'family_invitations' AND column_name = 'inviter_id'
  ) THEN
    ALTER TABLE family_invitations DROP COLUMN inviter_id;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'family_invitations' AND column_name = 'invitee_email'
  ) THEN
    ALTER TABLE family_invitations DROP COLUMN invitee_email;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_family_invitations_code ON family_invitations(invite_code);
CREATE INDEX IF NOT EXISTS idx_family_invitations_email ON family_invitations(email);
CREATE INDEX IF NOT EXISTS idx_family_invitations_family_id ON family_invitations(family_id);

ALTER TABLE family_invitations ENABLE ROW LEVEL SECURITY;

-- Admin can manage invitations
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_invitations' AND policyname = 'Admin manages invitations') THEN
    CREATE POLICY "Admin manages invitations" ON family_invitations
      FOR ALL USING (
        EXISTS (
          SELECT 1 FROM family_groups fg
          WHERE fg.id = family_id AND fg.admin_user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Anyone can look up invitations by code (for acceptance)
-- This is needed for the accept-family-invite function
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_invitations' AND policyname = 'Lookup invitation by code') THEN
    CREATE POLICY "Lookup invitation by code" ON family_invitations
      FOR SELECT USING (true);
  END IF;
END $$;

-- =============================================================================
-- PART 5: Gift subscriptions table (V2 feature, schema now)
-- =============================================================================

CREATE TABLE IF NOT EXISTS gift_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchaser_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  gift_code TEXT NOT NULL UNIQUE,
  plan_type TEXT NOT NULL DEFAULT 'individual' CHECK (plan_type IN ('individual', 'couples', 'family')),
  billing_period TEXT NOT NULL DEFAULT 'monthly' CHECK (billing_period IN ('monthly', 'annual')),
  duration_months INT NOT NULL DEFAULT 1,
  redeemed_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  redeemed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '1 year',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gift_subscriptions_code ON gift_subscriptions(gift_code);
CREATE INDEX IF NOT EXISTS idx_gift_subscriptions_purchaser ON gift_subscriptions(purchaser_user_id);

ALTER TABLE gift_subscriptions ENABLE ROW LEVEL SECURITY;

-- Purchaser and recipient can view
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'gift_subscriptions' AND policyname = 'View own gift subscriptions') THEN
    CREATE POLICY "View own gift subscriptions" ON gift_subscriptions
      FOR SELECT USING (
        purchaser_user_id = auth.uid() OR redeemed_by_user_id = auth.uid()
      );
  END IF;
END $$;

-- =============================================================================
-- PART 6: Add foreign key from subscriptions to family_groups
-- =============================================================================

-- Add foreign key constraint (needs to be done after family_groups exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'subscriptions_family_id_fkey'
  ) THEN
    ALTER TABLE subscriptions
      ADD CONSTRAINT subscriptions_family_id_fkey
      FOREIGN KEY (family_id) REFERENCES family_groups(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_subscriptions_family_id ON subscriptions(family_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_plan_type ON subscriptions(plan_type);

-- =============================================================================
-- PART 7: Premium badges
-- =============================================================================

-- Insert premium subscription badges (using ON CONFLICT to avoid duplicates)
-- Note: badges table schema has code, title, description, icon_name, category (no 'name' column)
INSERT INTO badges (code, title, description, icon_name, category) VALUES
  ('premium_supporter', 'Premium Supporter', 'Thanks for supporting MindFriend!', 'star.fill', 'subscription'),
  ('annual_achiever', 'Annual Achiever', 'Committed to a year of growth', 'calendar.badge.checkmark', 'subscription'),
  ('family_champion', 'Family Champion', 'Leading your family''s wellness journey', 'person.3.fill', 'subscription')
ON CONFLICT (code) DO NOTHING;

-- =============================================================================
-- PART 8: Helper function to generate invite codes
-- =============================================================================

CREATE OR REPLACE FUNCTION generate_invite_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result TEXT := '';
  i INT;
BEGIN
  FOR i IN 1..8 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  END LOOP;
  RETURN result;
END;
$$;

-- =============================================================================
-- PART 9: Function to revoke family member premium on admin subscription expiry
-- =============================================================================

CREATE OR REPLACE FUNCTION revoke_family_premium_on_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only act on status changes to expired/cancelled for family admins
  IF NEW.status IN ('expired', 'cancelled')
     AND OLD.status = 'active'
     AND NEW.is_family_admin = TRUE
     AND NEW.family_id IS NOT NULL
  THEN
    -- Revoke premium for all family members (not admin)
    UPDATE subscriptions
    SET status = 'expired',
        updated_at = NOW()
    WHERE family_id = NEW.family_id
      AND user_id != NEW.user_id
      AND status = 'active';

    -- Update family members status
    UPDATE family_members
    SET status = 'removed',
        removed_at = NOW()
    WHERE family_id = NEW.family_id
      AND user_id != NEW.user_id
      AND status = 'active';
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger for subscription expiry
DROP TRIGGER IF EXISTS trigger_revoke_family_premium ON subscriptions;
CREATE TRIGGER trigger_revoke_family_premium
  AFTER UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION revoke_family_premium_on_expiry();

-- =============================================================================
-- PART 10: Update timestamp trigger for family_groups
-- =============================================================================

CREATE OR REPLACE FUNCTION update_family_groups_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_family_groups_timestamp ON family_groups;
CREATE TRIGGER trigger_update_family_groups_timestamp
  BEFORE UPDATE ON family_groups
  FOR EACH ROW
  EXECUTE FUNCTION update_family_groups_updated_at();

-- =============================================================================
-- PART 11: Add premium badge display to profiles (optional column)
-- =============================================================================

-- Add column for displaying premium badge type
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS premium_badge TEXT;

-- Comment for documentation
COMMENT ON COLUMN profiles.premium_badge IS 'Type of premium badge to display: premium_supporter, annual_achiever, or family_champion';
