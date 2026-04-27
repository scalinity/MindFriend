-- 20260426120000_create_ai_consents.sql
-- AI consent state per (user, feature). Enforces App Store Guidelines 5.1.1(i)/5.1.2(i).

create table public.ai_consents (
  user_id        uuid not null references auth.users(id) on delete cascade,
  -- Adding a new feature: update this CHECK, the iOS AIFeature enum, and the Edge Function AIFeature type together.
  feature        text not null check (feature in (
                     'chat',
                     'journal_ai',
                     'voice_journal_ai',
                     'image_gen',
                     'insights',
                     'tts_voice'
                   )),
  state          text not null default 'unknown'
                   check (state in ('granted','denied','unknown')),
  granted_at     timestamptz,
  revoked_at     timestamptz,
  policy_version int  not null default 1,
  updated_at     timestamptz not null default now(),
  constraint ai_consents_timestamps_consistent check (
    (state = 'granted' and granted_at is not null) or
    (state = 'denied'  and revoked_at is not null) or
    (state = 'unknown')
  ),
  primary key (user_id, feature)
);
alter table public.ai_consents enable row level security;
create policy ai_consents_self_select on public.ai_consents
  for select using (auth.uid() = user_id);
create policy ai_consents_self_insert on public.ai_consents
  for insert with check (auth.uid() = user_id);
create policy ai_consents_self_update on public.ai_consents
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy ai_consents_self_delete on public.ai_consents
  for delete using (auth.uid() = user_id);
drop trigger if exists update_ai_consents_updated_at on public.ai_consents;
create trigger update_ai_consents_updated_at
  before update on public.ai_consents
  for each row execute function public.update_updated_at_column();
comment on table public.ai_consents is
  'Per-user, per-feature AI consent state. Required by App Store guideline 5.1.1(i)/5.1.2(i).';
