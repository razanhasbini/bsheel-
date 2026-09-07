-- ============================================================
-- MIGRATION 0001: Profiles
-- Extends Supabase auth.users with app-specific profile data.
-- ============================================================

-- Reusable updated_at trigger function (used by all tables with updated_at)
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql security definer;

-- Profiles table
create table if not exists public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  username    text        unique not null
                          constraint username_length check (char_length(username) between 3 and 30)
                          constraint username_format check (username ~ '^[a-zA-Z0-9_]+$'),
  display_name text       not null
                          constraint display_name_length check (char_length(display_name) between 1 and 50),
  avatar_url  text,
  bio         text        constraint bio_length check (char_length(bio) <= 300),
  xp          integer     not null default 0 constraint xp_non_negative check (xp >= 0),
  level       integer     not null default 1 constraint level_positive check (level >= 1),
  quests_completed integer not null default 0 constraint quests_completed_non_negative check (quests_completed >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

-- Auto-create profile on signup via auth trigger
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'user_' || left(new.id::text, 8)),
    coalesce(new.raw_user_meta_data->>'display_name', 'New User')
  );
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

comment on table public.profiles is 'User profiles extending auth.users. One profile per authenticated user.';
