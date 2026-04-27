-- Drop the self-delete RLS policy.
-- Why: App Store guideline 5.1.1 / GDPR Art. 7.1 require an audit trail of consent.
-- Hard-deleting consent rows from the client erases that record.
-- Revocation is via UPDATE state='denied' + revoked_at, which the existing update policy permits.
-- Account-deletion still wipes consent rows via the FK ON DELETE CASCADE from auth.users.
drop policy if exists ai_consents_self_delete on public.ai_consents;
-- Strengthen the update policy: prevent clients from writing a future policy_version that
-- would auto-satisfy a later CURRENT_POLICY_VERSION bump and bypass re-consent.
-- The existing update policy is replaced with one that adds a WITH CHECK clause.
drop policy if exists ai_consents_self_update on public.ai_consents;
create policy ai_consents_self_update on public.ai_consents
  for update using (auth.uid() = user_id)
  with check (auth.uid() = user_id and policy_version <= 1);
-- Same upper-bound check on insert, so a fresh row cannot be inserted with a pre-bumped version.
drop policy if exists ai_consents_self_insert on public.ai_consents;
create policy ai_consents_self_insert on public.ai_consents
  for insert with check (auth.uid() = user_id and policy_version <= 1);
