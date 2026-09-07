-- ============================================================
-- MIGRATION 0004: Submissions
-- Proof submissions for quest completion with media attachments.
-- ============================================================

create table if not exists public.submissions (
  id            uuid        primary key default gen_random_uuid(),
  user_quest_id uuid        not null references public.user_quests(id) on delete cascade,
  user_id       uuid        not null references public.profiles(id) on delete cascade,
  media_url     text        not null,
  media_type    text        not null default 'image'
                            check (media_type in ('image', 'video')),
  caption       text        constraint caption_length check (char_length(caption) <= 500),
  status        text        not null default 'pending'
                            check (status in ('pending', 'approved', 'rejected')),
  reviewed_by   uuid        references public.profiles(id),
  review_note   text        constraint review_note_length check (char_length(review_note) <= 500),
  submitted_at  timestamptz not null default now(),
  reviewed_at   timestamptz,

  -- One submission per user_quest
  constraint one_submission_per_quest unique (user_quest_id)
);

-- Auto-update user_quest status when submission is created
create or replace function public.handle_submission_created()
returns trigger as $$
begin
  update public.user_quests
    set status = 'submitted'
    where id = new.user_quest_id
      and status = 'assigned';
  return new;
end;
$$ language plpgsql security definer;

create trigger on_submission_created
  after insert on public.submissions
  for each row execute function public.handle_submission_created();

-- Auto-update profile stats when submission is approved
create or replace function public.handle_submission_approved()
returns trigger as $$
declare
  quest_xp integer;
begin
  if new.status = 'approved' and (old.status is null or old.status != 'approved') then
    -- Update user_quest
    update public.user_quests
      set status = 'approved', completed_at = now()
      where id = new.user_quest_id;

    -- Get XP reward
    select q.xp_reward into quest_xp
      from public.quests q
      join public.user_quests uq on uq.quest_id = q.id
      where uq.id = new.user_quest_id;

    -- Award XP and increment quests_completed
    update public.profiles
      set xp = xp + coalesce(quest_xp, 10),
          quests_completed = quests_completed + 1,
          level = greatest(1, (xp + coalesce(quest_xp, 10)) / 100 + 1)
      where id = new.user_id;

    -- Create approval notification
    insert into public.notifications (user_id, title, body, type, reference_id)
    values (
      new.user_id,
      'Submission Approved!',
      'Your submission was approved! +' || coalesce(quest_xp, 10) || ' XP',
      'submission_approved',
      new.id::text
    );
  end if;

  if new.status = 'rejected' and (old.status is null or old.status != 'rejected') then
    -- Update user_quest
    update public.user_quests
      set status = 'rejected'
      where id = new.user_quest_id;

    -- Create rejection notification
    insert into public.notifications (user_id, title, body, type, reference_id)
    values (
      new.user_id,
      'Submission Rejected',
      coalesce('Reason: ' || new.review_note, 'Your submission was not approved. Try again!'),
      'submission_rejected',
      new.id::text
    );
  end if;

  return new;
end;
$$ language plpgsql security definer;

create trigger on_submission_status_change
  after update of status on public.submissions
  for each row execute function public.handle_submission_approved();

comment on table public.submissions is 'Proof submissions for quest completion. One submission per user_quest.';
comment on column public.submissions.media_type is 'One of: image, video.';
