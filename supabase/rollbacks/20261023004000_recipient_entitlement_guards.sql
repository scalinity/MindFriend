-- Roll back the join-organization handler with this function removal.
-- Existing users, memberships, subscriptions and invitations are retained.
DROP FUNCTION IF EXISTS public.join_organization_with_invite(uuid, text);
DROP TRIGGER IF EXISTS guard_organization_sponsorship_fields ON public.organizations;
DROP FUNCTION IF EXISTS public.guard_organization_sponsorship_fields();
