-- 20260426120000_create_ai_consents.sql
-- AI consent state per (user, feature). Enforces App Store Guidelines 5.1.1(i)/5.1.2(i).

create table public.ai_consents (
  user_id        uuid not null references auth.users(id) on delete cascade,
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
  primary key (user_id, feature)
);

create index ai_consents_user_idx on public.ai_consents(user_id);

alter table public.ai_consents enable row level security;

create policy ai_consents_self_select on public.ai_consents
  for select using (auth.uid() = user_id);

create policy ai_consents_self_insert on public.ai_consents
  for insert with check (auth.uid() = user_id);

create policy ai_consents_self_update on public.ai_consents
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy ai_consents_self_delete on public.ai_consents
  for delete using (auth.uid() = user_id);

-- Auto-update updated_at on every row change
create or replace function public.touch_ai_consents_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger ai_consents_touch_updated_at
  before update on public.ai_consents
  for each row execute function public.touch_ai_consents_updated_at();

comment on table public.ai_consents is
  'Per-user, per-feature AI consent state. Required by App Store guideline 5.1.1(i)/5.1.2(i).';
