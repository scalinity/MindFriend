-- Migration: Create partner_links table with RLS policies
-- Purpose: Store partnerships with asymmetric per-user sharing settings
-- Status: CRITICAL PATH - Foundation

CREATE TABLE IF NOT EXISTS partner_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_1 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_id_2 UUID NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    invite_code VARCHAR(8) NULL UNIQUE,
    invite_code_hash VARCHAR(64) NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
    status VARCHAR(16) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'ended', 'expired')),
    activated_at TIMESTAMPTZ NULL,
    ended_at TIMESTAMPTZ NULL,
    user_1_share_mood BOOLEAN NOT NULL DEFAULT false,
    user_1_share_exercises BOOLEAN NOT NULL DEFAULT false,
    user_2_share_mood BOOLEAN NOT NULL DEFAULT false,
    user_2_share_exercises BOOLEAN NOT NULL DEFAULT false,
    notes TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT no_self_partnering CHECK (user_id_1 != COALESCE(user_id_2, user_id_1)),
    CONSTRAINT user_order CHECK (user_id_1 < COALESCE(user_id_2, user_id_1))
);

-- Critical: Enforce one active partner per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_partner_user1 ON partner_links(user_id_1) WHERE status = 'active' AND user_id_2 IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_partner_user2 ON partner_links(user_id_2) WHERE status = 'active' AND user_id_2 IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_code_hash ON partner_links(invite_code_hash) WHERE status = 'pending';

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_partner_links_status ON partner_links(status);
CREATE INDEX IF NOT EXISTS idx_partner_links_created_by ON partner_links(created_by);

-- Enable RLS
ALTER TABLE partner_links ENABLE ROW LEVEL SECURITY;

-- RLS Policy 1: Users can read their own pending invites (sent by them)
CREATE POLICY "Users read own sent invites"
  ON partner_links FOR SELECT
  USING (auth.uid() = created_by AND status = 'pending' AND user_id_2 IS NULL);

-- RLS Policy 2: Users can read active partnerships they're in (as user_id_1)
CREATE POLICY "Users read own active partnerships as user_1"
  ON partner_links FOR SELECT
  USING (auth.uid() = user_id_1 AND status = 'active' AND user_id_2 IS NOT NULL);

-- RLS Policy 3: Users can read active partnerships they're in (as user_id_2)
CREATE POLICY "Users read own active partnerships as user_2"
  ON partner_links FOR SELECT
  USING (auth.uid() = user_id_2 AND status = 'active' AND user_id_2 IS NOT NULL);

-- RLS Policy 4: Users can read ended partnerships (for history)
CREATE POLICY "Users read own ended partnerships"
  ON partner_links FOR SELECT
  USING ((auth.uid() = user_id_1 OR auth.uid() = user_id_2) AND status IN ('ended', 'expired'));

-- RLS Policy 5: Users can insert pending invite (create partnership)
CREATE POLICY "Users insert pending invites"
  ON partner_links FOR INSERT
  WITH CHECK (auth.uid() = created_by AND status = 'pending' AND user_id_2 IS NULL);

-- RLS Policy 6: Edge Functions can update via service role
CREATE POLICY "Service role updates partnerships"
  ON partner_links FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- RLS Policy 7: Deletions only via cascade on account deletion
CREATE POLICY "Users cannot directly delete"
  ON partner_links FOR DELETE
  USING (false);
