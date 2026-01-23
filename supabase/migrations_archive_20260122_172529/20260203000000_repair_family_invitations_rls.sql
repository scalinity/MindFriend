-- Migration: Repair family_invitations RLS and apply pending items
-- Repairs issues from failed 20260127000000 migration

-- Drop potentially incomplete policies
DROP POLICY IF EXISTS "Family admins can read their invitations" ON family_invitations;
DROP POLICY IF EXISTS "Family admins can create invitations" ON family_invitations;
DROP POLICY IF EXISTS "Family admins can update invitations" ON family_invitations;

-- Recreate the SELECT policy with correct column name
CREATE POLICY "Family admins can read their invitations"
    ON family_invitations FOR SELECT
    USING (
        -- User is admin of the family
        family_id IN (
            SELECT id FROM family_groups WHERE admin_user_id = auth.uid()
        )
        OR
        -- User is looking up their own email's invitations
        email = (SELECT email FROM auth.users WHERE id = auth.uid())
    );

-- Recreate INSERT policy
CREATE POLICY "Family admins can create invitations"
    ON family_invitations FOR INSERT
    WITH CHECK (
        family_id IN (
            SELECT id FROM family_groups WHERE admin_user_id = auth.uid()
        )
    );

-- Recreate UPDATE policy
CREATE POLICY "Family admins can update invitations"
    ON family_invitations FOR UPDATE
    USING (
        family_id IN (
            SELECT id FROM family_groups WHERE admin_user_id = auth.uid()
        )
    );

-- Add composite index (safe with IF NOT EXISTS)
CREATE INDEX IF NOT EXISTS idx_family_invitations_family_pending
    ON family_invitations(family_id, expires_at)
    WHERE accepted_at IS NULL;

-- Add table comment
COMMENT ON TABLE family_invitations IS
'Family plan invitations. RLS restricts reading to admins and invited users.
Invite code validation is done server-side in accept-family-invite Edge Function
using service role (bypasses RLS) to prevent enumeration attacks.';
