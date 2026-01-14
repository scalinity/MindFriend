-- Migration: Tighten RLS on family_invitations
-- Issue: P3-S5 - SELECT policy allows any authenticated user to read invitations by code
-- Fix: Restrict reading to family admins or the invited user, code validation handled by Edge Function

-- Drop existing overly permissive policy if it exists
DROP POLICY IF EXISTS "Users can read invitations by code" ON family_invitations;

-- Create more restrictive policy:
-- Family admins can see their family's invitations
-- Users can see invitations for their email (to show "you have a pending invite" UI)
-- Invite code validation is handled server-side in accept-family-invite Edge Function
CREATE POLICY "Family admins can read their invitations"
    ON family_invitations FOR SELECT
    USING (
        -- User is admin of the family
        family_id IN (
            SELECT id FROM family_groups WHERE admin_user_id = auth.uid()
        )
        OR
        -- User is looking up their own email's invitations
        invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
    );

-- Ensure admins can still insert invitations via Edge Function
-- Note: Actual insert is done by service role in send-family-invite
DROP POLICY IF EXISTS "Family admins can create invitations" ON family_invitations;
CREATE POLICY "Family admins can create invitations"
    ON family_invitations FOR INSERT
    WITH CHECK (
        family_id IN (
            SELECT id FROM family_groups WHERE admin_user_id = auth.uid()
        )
    );

-- Ensure admins can update/revoke invitations
DROP POLICY IF EXISTS "Family admins can update invitations" ON family_invitations;
CREATE POLICY "Family admins can update invitations"
    ON family_invitations FOR UPDATE
    USING (
        family_id IN (
            SELECT id FROM family_groups WHERE admin_user_id = auth.uid()
        )
    );

-- Add index for email lookup performance
CREATE INDEX IF NOT EXISTS idx_family_invitations_email
    ON family_invitations(invited_email)
    WHERE accepted_at IS NULL;

-- Add composite index for family + status queries
CREATE INDEX IF NOT EXISTS idx_family_invitations_family_pending
    ON family_invitations(family_id, expires_at)
    WHERE accepted_at IS NULL;

-- Add comment explaining the security model
COMMENT ON TABLE family_invitations IS
'Family plan invitations. RLS restricts reading to admins and invited users.
Invite code validation is done server-side in accept-family-invite Edge Function
using service role (bypasses RLS) to prevent enumeration attacks.';
