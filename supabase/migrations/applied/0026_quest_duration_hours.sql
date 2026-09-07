-- Configurable quest duration (in hours) managed from admin.
-- Makes assignment expiry depend on each quest instead of a fixed 4-hour window.

alter table public.quests
  add column if not exists duration_hours integer;

update public.quests
set duration_hours = 4
where duration_hours is null or duration_hours < 1;

alter table public.quests
  alter column duration_hours set default 4;

alter table public.quests
  alter column duration_hours set not null;

alter table public.quests
  drop constraint if exists quests_duration_hours_range;

alter table public.quests
  add constraint quests_duration_hours_range check (duration_hours between 1 and 168);

comment on column public.quests.duration_hours is 'Quest time limit in hours. Used to compute user_quests.expires_at on assignment.';
comment on column public.user_quests.expires_at is 'Assignment deadline timestamp. Set when assigned based on quest.duration_hours.';

create or replace function public.assign_random_quest(p_user_id uuid)
returns public.user_quests as $$
declare
  v_quest_id uuid;
  v_duration_hours integer;
  v_result public.user_quests;
begin
  -- Expire overdue assigned quests
  update public.user_quests
    set status = 'expired'
    where user_id = p_user_id
      and status = 'assigned'
      and expires_at is not null
      and expires_at < now();

  -- Only block if there is an assigned (in-progress) quest
  if exists (
    select 1 from public.user_quests
    where user_id = p_user_id and status = 'assigned'
  ) then
    raise exception 'User already has an active quest';
  end if;

  select id, coalesce(duration_hours, 4)
    into v_quest_id, v_duration_hours
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

  insert into public.user_quests (user_id, quest_id, expires_at)
  values (
    p_user_id,
    v_quest_id,
    now() + make_interval(hours => v_duration_hours)
  )
  returning * into v_result;

  insert into public.notifications (user_id, title, body, type, reference_id)
  values (
    p_user_id,
    'New Quest!',
    format(
      'You have a new quest! Complete it within %s.',
      case
        when v_duration_hours = 1 then '1 hour'
        else v_duration_hours::text || ' hours'
      end
    ),
    'quest_assigned',
    v_result.id::text
  );

  return v_result;
end;
$$ language plpgsql security definer;

create or replace function public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
returns public.user_quests as $$
declare
  v_duration_hours integer;
  v_result public.user_quests;
begin
  update public.user_quests
    set status = 'expired'
    where user_id = p_user_id
      and status = 'assigned'
      and expires_at is not null
      and expires_at < now();

  -- Only block if there is an assigned (in-progress) quest
  if exists (
    select 1 from public.user_quests
    where user_id = p_user_id and status = 'assigned'
  ) then
    raise exception 'User already has an active quest';
  end if;

  select coalesce(duration_hours, 4)
    into v_duration_hours
    from public.quests
    where id = p_quest_id and is_active = true;

  if not found then
    raise exception 'Quest not found or inactive';
  end if;

  insert into public.user_quests (user_id, quest_id, expires_at)
  values (
    p_user_id,
    p_quest_id,
    now() + make_interval(hours => v_duration_hours)
  )
  returning * into v_result;

  insert into public.notifications (user_id, title, body, type, reference_id)
  values (
    p_user_id,
    'New Quest!',
    format(
      'You have a new quest! Complete it within %s.',
      case
        when v_duration_hours = 1 then '1 hour'
        else v_duration_hours::text || ' hours'
      end
    ),
    'quest_assigned',
    v_result.id::text
  );

  return v_result;
end;
$$ language plpgsql security definer;
