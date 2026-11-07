-- Additive consent contract: old clients retain their existing completion path.
-- New clients require this receipt; no historical completion is treated as age verification.
-- Keep birth year outside the socially readable profile surface.
create table public.support_onboarding_consent (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  birth_year integer not null check (birth_year between 1900 and 2100),
  age_thirteen_confirmed boolean not null check (age_thirteen_confirmed),
  consent_version text not null,
  accepted_at timestamptz not null default transaction_timestamp()
);
alter table public.support_onboarding_consent enable row level security;
create policy support_consent_owner_read on public.support_onboarding_consent
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.support_onboarding_consent from public, anon, authenticated;
grant select on public.support_onboarding_consent to authenticated;
grant all on public.support_onboarding_consent to service_role;

-- Definer is necessary because clients cannot insert or rewrite consent directly.
-- Expected owner closes an account-switch race before any mutation. The first
-- acknowledged values are immutable; retrying an identical submission is idempotent.
create or replace function public.complete_support_onboarding(
  p_expected_user uuid, p_birth_year integer, p_confirms_thirteen boolean,
  p_accepts_terms boolean, p_consent_version text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  required_version constant text := '2026-11-06';
  saved public.support_onboarding_consent%rowtype;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_expected_user is distinct from owner_id then
    raise exception 'Account changed' using errcode = '42501';
  end if;
  if p_birth_year is null or p_birth_year < 1900 or
     p_birth_year > extract(year from (now() at time zone 'UTC'))::integer - 13 or
     p_confirms_thirteen is distinct from true or p_accepts_terms is distinct from true or
     p_consent_version is distinct from required_version then
    raise exception 'Valid birth year and explicit consent required' using errcode = '22023';
  end if;
  perform 1 from public.profiles where id = owner_id for update;
  if not found then raise exception 'Profile not found' using errcode = 'P0002'; end if;
  insert into public.support_onboarding_consent
    (user_id, birth_year, age_thirteen_confirmed, consent_version)
    values (owner_id, p_birth_year, true, required_version)
    on conflict (user_id) do nothing;
  select * into strict saved from public.support_onboarding_consent where user_id = owner_id;
  if saved.birth_year <> p_birth_year or saved.consent_version <> required_version then
    raise exception 'Consent already recorded with different values' using errcode = '22023';
  end if;
  update public.profiles set onboarding_completed_at = coalesce(onboarding_completed_at, saved.accepted_at)
    where id = owner_id;
  return jsonb_build_object('user_id', saved.user_id, 'consent_version', saved.consent_version,
    'accepted_at', saved.accepted_at);
end;
$$;
revoke all on function public.complete_support_onboarding(uuid, integer, boolean, boolean, text) from public, anon;
grant execute on function public.complete_support_onboarding(uuid, integer, boolean, boolean, text) to authenticated;
