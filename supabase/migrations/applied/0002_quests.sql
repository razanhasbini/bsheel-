-- ============================================================
-- MIGRATION 0002: Quests
-- Quest definitions created and managed by admins.
-- ============================================================

create table if not exists public.quests (
  id          uuid        primary key default gen_random_uuid(),
  title       text        not null constraint title_length check (char_length(title) between 3 and 100),
  description text        not null constraint description_length check (char_length(description) between 10 and 500),
  category    text        not null check (category in ('fitness', 'creativity', 'social', 'learning', 'adventure')),
  difficulty  text        not null check (difficulty in ('easy', 'medium', 'hard')),
  xp_reward   integer     not null default 10 constraint xp_reward_range check (xp_reward between 5 and 100),
  is_active   boolean     not null default true,
  created_by  uuid        references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);

create trigger quests_updated_at
  before update on public.quests
  for each row execute function public.handle_updated_at();

comment on table public.quests is 'Quest definitions. Managed by admins, assigned randomly to users.';
comment on column public.quests.xp_reward is 'XP awarded on quest completion. Range: 5-100.';
comment on column public.quests.category is 'One of: fitness, creativity, social, learning, adventure.';
comment on column public.quests.difficulty is 'One of: easy, medium, hard.';
