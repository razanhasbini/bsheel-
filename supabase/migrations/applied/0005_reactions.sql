-- ============================================================
-- MIGRATION 0005: Reactions
-- Emoji reactions on approved submissions (social feed).
-- ============================================================

create table if not exists public.reactions (
  id            uuid        primary key default gen_random_uuid(),
  submission_id uuid        not null references public.submissions(id) on delete cascade,
  user_id       uuid        not null references public.profiles(id) on delete cascade,
  type          text        not null check (type in ('fire', 'clap', 'heart', 'wow')),
  created_at    timestamptz not null default now(),

  -- One reaction of each type per user per submission
  constraint unique_reaction unique (submission_id, user_id, type)
);

-- Auto-create notification when someone reacts to a submission
create or replace function public.handle_reaction_created()
returns trigger as $$
declare
  submission_owner uuid;
  reactor_name text;
begin
  -- Get submission owner
  select user_id into submission_owner
    from public.submissions
    where id = new.submission_id;

  -- Don't notify if user reacted to own submission
  if submission_owner = new.user_id then
    return new;
  end if;

  -- Get reactor display name
  select display_name into reactor_name
    from public.profiles
    where id = new.user_id;

  insert into public.notifications (user_id, title, body, type, reference_id)
  values (
    submission_owner,
    'New Reaction!',
    coalesce(reactor_name, 'Someone') || ' reacted ' || new.type || ' to your post',
    'reaction_received',
    new.submission_id::text
  );

  return new;
end;
$$ language plpgsql security definer;

create trigger on_reaction_created
  after insert on public.reactions
  for each row execute function public.handle_reaction_created();

comment on table public.reactions is 'Emoji reactions on approved submissions. One of each type per user per submission.';
