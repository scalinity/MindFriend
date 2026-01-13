-- MindFriend Database Schema for Supabase
-- Run this in the Supabase SQL Editor (SQL Editor → New Query → Paste → Run)

-- ============================================
-- EXTENSIONS
-- ============================================
create extension if not exists "uuid-ossp";

-- ============================================
-- ENUMS
-- ============================================
create type ai_tone as enum ('friendly', 'professional', 'casual', 'supportive');
create type privacy_mode as enum ('standard', 'enhanced');
create type subscription_tier as enum ('free', 'premium');
create type quest_status as enum ('available', 'in_progress', 'completed', 'skipped', 'expired');
create type quest_category as enum ('mindfulness', 'gratitude', 'social', 'physical', 'creative', 'reflection');
create type exercise_type as enum ('breathing', 'meditation', 'journaling', 'grounding');
create type message_role as enum ('user', 'assistant', 'system');

-- ============================================
-- USERS TABLE (extends Supabase auth.users)
-- ============================================
create table public.profiles (
    id uuid references auth.users on delete cascade primary key,
    handle text unique,
    display_name text,
    email text,
    avatar_url text,
    timezone text default 'UTC',
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),

    -- Settings
    daily_quest_time_local time default '09:00',
    quiet_hours_start_local time,
    quiet_hours_end_local time,
    reminders_enabled boolean default true,
    nudge_after_days_inactive integer default 3,
    share_mood_in_circles boolean default true,
    ai_tone ai_tone default 'friendly',
    privacy_mode privacy_mode default 'standard',

    -- Stats
    current_streak_days integer default 0,
    longest_streak_days integer default 0,
    total_quests_completed integer default 0,
    total_exercises_completed integer default 0,

    -- Subscription
    subscription_tier subscription_tier default 'free',
    daily_ai_quota integer default 20,
    daily_ai_used integer default 0,
    quota_reset_at timestamp with time zone default now()
);

-- ============================================
-- DEVICES (for push notifications)
-- ============================================
create table public.devices (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    apns_token text not null,
    device_model text,
    os_version text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now(),

    unique(user_id, apns_token)
);

-- ============================================
-- MOODS
-- ============================================
create table public.moods (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    local_date date not null,
    mood_score integer not null check (mood_score >= 1 and mood_score <= 10),
    anxiety_score integer check (anxiety_score >= 1 and anxiety_score <= 10),
    energy_score integer check (energy_score >= 1 and energy_score <= 10),
    note text,
    created_at timestamp with time zone default now(),

    unique(user_id, local_date)
);

-- ============================================
-- QUESTS
-- ============================================
create table public.quest_templates (
    id uuid default uuid_generate_v4() primary key,
    title text not null,
    description text not null,
    category quest_category not null,
    estimated_minutes integer default 5,
    xp_reward integer default 50,
    is_premium boolean default false,
    created_at timestamp with time zone default now()
);

create table public.user_quests (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    quest_template_id uuid references public.quest_templates(id) on delete cascade not null,
    assigned_date date not null,
    status quest_status default 'available',
    reflection_note text,
    rating integer check (rating >= 1 and rating <= 5),
    completed_at timestamp with time zone,
    created_at timestamp with time zone default now(),

    unique(user_id, assigned_date)
);

-- ============================================
-- EXERCISES
-- ============================================
create table public.exercises (
    id uuid default uuid_generate_v4() primary key,
    title text not null,
    description text not null,
    type exercise_type not null,
    duration_minutes integer not null,
    instructions jsonb, -- Array of instruction steps
    is_premium boolean default false,
    created_at timestamp with time zone default now()
);

create table public.exercise_sessions (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    exercise_id uuid references public.exercises(id) on delete cascade not null,
    started_at timestamp with time zone default now(),
    completed_at timestamp with time zone,
    rating integer check (rating >= 1 and rating <= 5),
    note text
);

-- ============================================
-- CHAT CONVERSATIONS
-- ============================================
create table public.conversations (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    title text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

create table public.messages (
    id uuid default uuid_generate_v4() primary key,
    conversation_id uuid references public.conversations(id) on delete cascade not null,
    role message_role not null,
    content text not null,
    created_at timestamp with time zone default now()
);

-- ============================================
-- CIRCLES (Friend Groups)
-- ============================================
create table public.circles (
    id uuid default uuid_generate_v4() primary key,
    name text not null,
    description text,
    invite_code text unique not null,
    owner_id uuid references public.profiles(id) on delete cascade not null,
    created_at timestamp with time zone default now()
);

create table public.circle_members (
    id uuid default uuid_generate_v4() primary key,
    circle_id uuid references public.circles(id) on delete cascade not null,
    user_id uuid references public.profiles(id) on delete cascade not null,
    joined_at timestamp with time zone default now(),

    unique(circle_id, user_id)
);

create table public.circle_checkins (
    id uuid default uuid_generate_v4() primary key,
    circle_id uuid references public.circles(id) on delete cascade not null,
    user_id uuid references public.profiles(id) on delete cascade not null,
    mood_emoji text not null,
    body_text text,
    created_at timestamp with time zone default now()
);

-- ============================================
-- BADGES
-- ============================================
create table public.badges (
    id uuid default uuid_generate_v4() primary key,
    name text not null,
    description text not null,
    icon_name text not null,
    requirement_type text not null, -- 'streak', 'quests_completed', etc.
    requirement_value integer not null
);

create table public.user_badges (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    badge_id uuid references public.badges(id) on delete cascade not null,
    earned_at timestamp with time zone default now(),

    unique(user_id, badge_id)
);

-- ============================================
-- CRISIS RESOURCES
-- ============================================
create table public.crisis_resources (
    id uuid default uuid_generate_v4() primary key,
    country_code text not null,
    name text not null,
    phone text,
    text_line text,
    website text,
    description text,
    is_default boolean default false
);

-- ============================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================

-- Enable RLS on all tables
alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.moods enable row level security;
alter table public.quest_templates enable row level security;
alter table public.user_quests enable row level security;
alter table public.exercises enable row level security;
alter table public.exercise_sessions enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.circle_checkins enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.crisis_resources enable row level security;

-- Profiles: Users can read/update their own profile
create policy "Users can view own profile" on public.profiles
    for select using (auth.uid() = id);
create policy "Users can update own profile" on public.profiles
    for update using (auth.uid() = id);
create policy "Users can insert own profile" on public.profiles
    for insert with check (auth.uid() = id);

-- Devices: Users can manage their own devices
create policy "Users can manage own devices" on public.devices
    for all using (auth.uid() = user_id);

-- Moods: Users can manage their own moods
create policy "Users can manage own moods" on public.moods
    for all using (auth.uid() = user_id);

-- Quest Templates: Everyone can read
create policy "Quest templates are viewable by all" on public.quest_templates
    for select using (true);

-- User Quests: Users can manage their own quests
create policy "Users can manage own quests" on public.user_quests
    for all using (auth.uid() = user_id);

-- Exercises: Everyone can read
create policy "Exercises are viewable by all" on public.exercises
    for select using (true);

-- Exercise Sessions: Users can manage their own sessions
create policy "Users can manage own exercise sessions" on public.exercise_sessions
    for all using (auth.uid() = user_id);

-- Conversations: Users can manage their own conversations
create policy "Users can manage own conversations" on public.conversations
    for all using (auth.uid() = user_id);

-- Messages: Users can view messages in their conversations
create policy "Users can view messages in own conversations" on public.messages
    for select using (
        exists (
            select 1 from public.conversations
            where conversations.id = messages.conversation_id
            and conversations.user_id = auth.uid()
        )
    );
create policy "Users can insert messages in own conversations" on public.messages
    for insert with check (
        exists (
            select 1 from public.conversations
            where conversations.id = messages.conversation_id
            and conversations.user_id = auth.uid()
        )
    );

-- Circles: Members can view circles they belong to
create policy "Circle members can view circle" on public.circles
    for select using (
        auth.uid() = owner_id or
        exists (
            select 1 from public.circle_members
            where circle_members.circle_id = circles.id
            and circle_members.user_id = auth.uid()
        )
    );
create policy "Users can create circles" on public.circles
    for insert with check (auth.uid() = owner_id);
create policy "Owners can update circles" on public.circles
    for update using (auth.uid() = owner_id);
create policy "Owners can delete circles" on public.circles
    for delete using (auth.uid() = owner_id);

-- Circle Members: View members of circles you belong to
create policy "View circle members" on public.circle_members
    for select using (
        exists (
            select 1 from public.circle_members as cm
            where cm.circle_id = circle_members.circle_id
            and cm.user_id = auth.uid()
        )
    );
create policy "Users can join circles" on public.circle_members
    for insert with check (auth.uid() = user_id);
create policy "Users can leave circles" on public.circle_members
    for delete using (auth.uid() = user_id);

-- Circle Checkins: Members can view and post
create policy "Circle members can view checkins" on public.circle_checkins
    for select using (
        exists (
            select 1 from public.circle_members
            where circle_members.circle_id = circle_checkins.circle_id
            and circle_members.user_id = auth.uid()
        )
    );
create policy "Circle members can post checkins" on public.circle_checkins
    for insert with check (
        auth.uid() = user_id and
        exists (
            select 1 from public.circle_members
            where circle_members.circle_id = circle_checkins.circle_id
            and circle_members.user_id = auth.uid()
        )
    );

-- Badges: Everyone can read
create policy "Badges are viewable by all" on public.badges
    for select using (true);

-- User Badges: Users can view their own badges
create policy "Users can view own badges" on public.user_badges
    for select using (auth.uid() = user_id);

-- Crisis Resources: Everyone can read
create policy "Crisis resources are viewable by all" on public.crisis_resources
    for select using (true);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, email, display_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
    );
    return new;
end;
$$ language plpgsql security definer;

-- Trigger to auto-create profile
create or replace trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- Function to generate invite code
create or replace function generate_invite_code()
returns text as $$
declare
    chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result text := '';
    i integer;
begin
    for i in 1..6 loop
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    end loop;
    return result;
end;
$$ language plpgsql;

-- Function to assign daily quest
create or replace function assign_daily_quest(p_user_id uuid)
returns uuid as $$
declare
    v_quest_id uuid;
    v_user_quest_id uuid;
    v_is_premium boolean;
begin
    -- Check if user already has quest for today
    select id into v_user_quest_id
    from public.user_quests
    where user_id = p_user_id and assigned_date = current_date;

    if v_user_quest_id is not null then
        return v_user_quest_id;
    end if;

    -- Get user's subscription tier
    select subscription_tier = 'premium' into v_is_premium
    from public.profiles where id = p_user_id;

    -- Pick a random quest template
    select id into v_quest_id
    from public.quest_templates
    where (not is_premium or v_is_premium)
    order by random()
    limit 1;

    -- Create user quest
    insert into public.user_quests (user_id, quest_template_id, assigned_date)
    values (p_user_id, v_quest_id, current_date)
    returning id into v_user_quest_id;

    return v_user_quest_id;
end;
$$ language plpgsql security definer;

-- Function to reset daily AI quota
create or replace function reset_daily_quota()
returns void as $$
begin
    update public.profiles
    set daily_ai_used = 0, quota_reset_at = now()
    where quota_reset_at < current_date;
end;
$$ language plpgsql security definer;

-- ============================================
-- SEED DATA
-- ============================================

-- Sample Quest Templates
insert into public.quest_templates (title, description, category, estimated_minutes, xp_reward) values
('Morning Gratitude', 'Write down 3 things you are grateful for this morning.', 'gratitude', 5, 50),
('Mindful Breathing', 'Take 5 minutes to practice deep breathing exercises.', 'mindfulness', 5, 50),
('Reach Out', 'Send a kind message to someone you care about.', 'social', 5, 75),
('Nature Walk', 'Take a 10-minute walk outside and notice 5 things in nature.', 'physical', 10, 75),
('Creative Expression', 'Spend 10 minutes drawing, writing, or creating something.', 'creative', 10, 75),
('Evening Reflection', 'Reflect on one thing that went well today and why.', 'reflection', 5, 50),
('Body Scan', 'Practice a 5-minute body scan meditation.', 'mindfulness', 5, 50),
('Acts of Kindness', 'Do one small act of kindness for someone today.', 'social', 10, 75),
('Digital Detox', 'Spend 30 minutes without any screens.', 'mindfulness', 30, 100),
('Journaling', 'Write freely for 10 minutes about how you are feeling.', 'reflection', 10, 75);

-- Sample Exercises
insert into public.exercises (title, description, type, duration_minutes, instructions) values
('Box Breathing', 'A calming breathing technique used by Navy SEALs.', 'breathing', 4,
 '[{"step": 1, "text": "Breathe in for 4 seconds"}, {"step": 2, "text": "Hold for 4 seconds"}, {"step": 3, "text": "Breathe out for 4 seconds"}, {"step": 4, "text": "Hold for 4 seconds"}, {"step": 5, "text": "Repeat 4 times"}]'),
('4-7-8 Breathing', 'A relaxing breath pattern to reduce anxiety.', 'breathing', 3,
 '[{"step": 1, "text": "Breathe in through nose for 4 seconds"}, {"step": 2, "text": "Hold breath for 7 seconds"}, {"step": 3, "text": "Exhale through mouth for 8 seconds"}, {"step": 4, "text": "Repeat 3-4 times"}]'),
('5-4-3-2-1 Grounding', 'Ground yourself using your five senses.', 'grounding', 5,
 '[{"step": 1, "text": "Name 5 things you can SEE"}, {"step": 2, "text": "Name 4 things you can TOUCH"}, {"step": 3, "text": "Name 3 things you can HEAR"}, {"step": 4, "text": "Name 2 things you can SMELL"}, {"step": 5, "text": "Name 1 thing you can TASTE"}]'),
('Body Scan Meditation', 'A guided meditation to release tension.', 'meditation', 10,
 '[{"step": 1, "text": "Close your eyes and take 3 deep breaths"}, {"step": 2, "text": "Focus attention on your feet, notice any sensations"}, {"step": 3, "text": "Slowly move attention up through your legs"}, {"step": 4, "text": "Continue through your torso, arms, and head"}, {"step": 5, "text": "Notice your whole body, then slowly open your eyes"}]'),
('Gratitude Journal', 'Write about what you are thankful for.', 'journaling', 10,
 '[{"step": 1, "text": "Find a quiet space with your journal"}, {"step": 2, "text": "Write 3 things you are grateful for today"}, {"step": 3, "text": "For each, explain WHY you are grateful"}, {"step": 4, "text": "Notice how you feel after writing"}]');

-- Sample Badges
insert into public.badges (name, description, icon_name, requirement_type, requirement_value) values
('First Steps', 'Complete your first quest', 'star.fill', 'quests_completed', 1),
('Week Warrior', 'Maintain a 7-day streak', 'flame.fill', 'streak', 7),
('Consistent', 'Complete 10 quests', 'checkmark.circle.fill', 'quests_completed', 10),
('Dedicated', 'Maintain a 30-day streak', 'flame.fill', 'streak', 30),
('Mindful Master', 'Complete 50 quests', 'brain.head.profile', 'quests_completed', 50),
('Century Club', 'Maintain a 100-day streak', 'trophy.fill', 'streak', 100);

-- Sample Crisis Resources
insert into public.crisis_resources (country_code, name, phone, text_line, website, description, is_default) values
('US', 'National Suicide Prevention Lifeline', '988', 'Text HOME to 741741', 'https://988lifeline.org', '24/7 free and confidential support', true),
('US', 'Crisis Text Line', null, 'Text HOME to 741741', 'https://www.crisistextline.org', 'Free 24/7 text support', false),
('UK', 'Samaritans', '116 123', null, 'https://www.samaritans.org', 'Free 24/7 support', true),
('CA', 'Talk Suicide Canada', '1-833-456-4566', 'Text 45645', 'https://talksuicide.ca', '24/7 crisis support', true),
('AU', 'Lifeline Australia', '13 11 14', 'Text 0477 13 11 14', 'https://www.lifeline.org.au', '24/7 crisis support', true);
