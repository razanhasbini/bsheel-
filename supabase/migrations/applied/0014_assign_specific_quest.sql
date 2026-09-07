-- ============================================================
-- MIGRATION 0014: Assign a specific quest by ID
-- Allows the client to pick a quest from 3 options and assign
-- that exact quest rather than a random one.
-- ============================================================

create or replace function public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
returns public.user_quests as $$
declare
  v_result public.user_quests;
begin
  -- First, expire any overdue assigned quests for this user
  update public.user_quests
    set status = 'expired'
    where user_id = p_user_id
      and status = 'assigned'
      and expires_at is not null
      and expires_at < now();

  -- Check no active quest exists
  if exists (
    select 1 from public.user_quests
    where user_id = p_user_id and status in ('assigned', 'submitted')
  ) then
    raise exception 'User already has an active quest';
  end if;

  -- Verify the quest exists and is active
  if not exists (
    select 1 from public.quests
    where id = p_quest_id and is_active = true
  ) then
    raise exception 'Quest not found or inactive';
  end if;

  -- Create the assignment with the specific quest
  insert into public.user_quests (user_id, quest_id)
  values (p_user_id, p_quest_id)
  returning * into v_result;

  -- Notify user
  insert into public.notifications (user_id, title, body, type, reference_id)
  values (
    p_user_id,
    'New Quest!',
    'You have a new quest! Complete it within 4 hours.',
    'quest_assigned',
    v_result.id::text
  );

  return v_result;
end;
$$ language plpgsql security definer;
