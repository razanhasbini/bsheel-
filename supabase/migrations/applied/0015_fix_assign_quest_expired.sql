-- ============================================================
-- MIGRATION 0013: Fix assign_random_quest to auto-expire overdue quests
-- The RPC now expires any assigned quests past their expires_at
-- before checking for active quests, preventing false "already active" errors.
-- ============================================================

create or replace function public.assign_random_quest(p_user_id uuid)
returns public.user_quests as $$
declare
  v_quest_id uuid;
  v_result public.user_quests;
begin
  -- First, expire any overdue assigned quests for this user
  update public.user_quests
    set status = 'expired'
    where user_id = p_user_id
      and status = 'assigned'
      and expires_at is not null
      and expires_at < now();

  -- Check no active quest exists (after expiring overdue ones)
  if exists (
    select 1 from public.user_quests
    where user_id = p_user_id and status in ('assigned', 'submitted')
  ) then
    raise exception 'User already has an active quest';
  end if;

  -- Pick a random active quest not recently completed by this user
  select id into v_quest_id
    from public.quests
    where is_active = true
      and id not in (
        select quest_id from public.user_quests
        where user_id = p_user_id
          and status = 'approved'
          and completed_at > now() - interval '7 days'
      )
    order by random()
    limit 1;

  if v_quest_id is null then
    raise exception 'No available quests';
  end if;

  -- Create the assignment
  insert into public.user_quests (user_id, quest_id)
  values (p_user_id, v_quest_id)
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
