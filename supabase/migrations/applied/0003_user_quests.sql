-- ============================================================
-- MIGRATION 0003: User Quests
-- Tracks quest assignments to users. One active quest at a time.
-- ============================================================

create table if not exists public.user_quests (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references public.profiles(id) on delete cascade,
  quest_id     uuid        not null references public.quests(id) on delete cascade,
  status       text        not null default 'assigned'
                           check (status in ('assigned', 'submitted', 'approved', 'rejected', 'expired')),
  assigned_at  timestamptz not null default now(),
  completed_at timestamptz,
  expires_at   timestamptz not null default (now() + interval '4 hours'),

  -- Prevent duplicate active assignments of the same quest
  constraint unique_active_user_quest unique (user_id, quest_id, status)
);

-- Ensure only one active (assigned/submitted) quest per user
create unique index if not exists idx_one_active_quest_per_user
  on public.user_quests (user_id)
  where status in ('assigned', 'submitted');

comment on table public.user_quests is 'Quest assignments. Users get one active quest at a time with a 4-hour deadline.';
comment on column public.user_quests.expires_at is 'Defaults to 4 hours after assignment.';
