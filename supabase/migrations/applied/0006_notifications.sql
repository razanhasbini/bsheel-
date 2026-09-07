-- ============================================================
-- MIGRATION 0006: Notifications
-- In-app notification system for quest events, reactions, etc.
-- ============================================================

create table if not exists public.notifications (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references public.profiles(id) on delete cascade,
  title        text        not null constraint title_length check (char_length(title) between 1 and 100),
  body         text        not null constraint body_length check (char_length(body) between 1 and 500),
  type         text        not null
                           check (type in ('quest_assigned', 'submission_approved', 'submission_rejected', 'reaction_received', 'level_up')),
  reference_id text,
  is_read      boolean     not null default false,
  created_at   timestamptz not null default now()
);

-- Auto-delete notifications older than 90 days (run via cron or pg_cron)
-- select cron.schedule('cleanup-old-notifications', '0 3 * * *',
--   $$delete from public.notifications where created_at < now() - interval '90 days'$$
-- );

comment on table public.notifications is 'In-app notifications. Auto-created by triggers on submissions and reactions.';
comment on column public.notifications.type is 'One of: quest_assigned, submission_approved, submission_rejected, reaction_received, level_up.';
comment on column public.notifications.reference_id is 'Optional FK-like reference to the related entity (submission id, quest id, etc).';
