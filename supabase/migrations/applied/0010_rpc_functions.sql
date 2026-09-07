-- ============================================================
-- MIGRATION 0010: RPC Functions
-- Server-side functions called from the client via supabase.rpc().
-- ============================================================

-- Assign a random active quest to a user
create or replace function public.assign_random_quest(p_user_id uuid)
returns public.user_quests as $$
declare
  v_quest_id uuid;
  v_result public.user_quests;
begin
  -- Check no active quest exists
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

-- Get leaderboard (top users by XP)
create or replace function public.get_leaderboard(p_limit integer default 50)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  xp integer,
  level integer,
  quests_completed integer
) as $$
begin
  return query
    select
      row_number() over (order by p.xp desc) as rank,
      p.id as user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      p.xp,
      p.level,
      p.quests_completed
    from public.profiles p
    where p.xp > 0
    order by p.xp desc
    limit p_limit;
end;
$$ language plpgsql security definer stable;

-- Get user XP stats
create or replace function public.get_user_xp_stats(p_user_id uuid)
returns table (
  total_xp integer,
  current_level integer,
  xp_to_next_level integer,
  total_quests integer,
  rank bigint
) as $$
begin
  return query
    select
      p.xp as total_xp,
      p.level as current_level,
      (p.level * 100) - p.xp as xp_to_next_level,
      p.quests_completed as total_quests,
      (select count(*) + 1 from public.profiles p2 where p2.xp > p.xp) as rank
    from public.profiles p
    where p.id = p_user_id;
end;
$$ language plpgsql security definer stable;

-- Atomically increment XP (used by triggers, but available via RPC)
create or replace function public.increment_xp(p_user_id uuid, p_amount integer)
returns void as $$
begin
  update public.profiles
    set xp = xp + p_amount,
        level = greatest(1, (xp + p_amount) / 100 + 1)
    where id = p_user_id;

  -- Check for level up notification
  if (select level from public.profiles where id = p_user_id) >
     (select greatest(1, (xp - p_amount) / 100 + 1) from public.profiles where id = p_user_id) then
    insert into public.notifications (user_id, title, body, type)
    values (
      p_user_id,
      'Level Up!',
      'You reached level ' || (select level from public.profiles where id = p_user_id) || '!',
      'level_up'
    );
  end if;
end;
$$ language plpgsql security definer;

-- Expire overdue quests (run via cron)
create or replace function public.expire_overdue_quests()
returns void as $$
begin
  update public.user_quests
    set status = 'expired'
    where status = 'assigned'
      and expires_at < now();
end;
$$ language plpgsql security definer;

-- Get feed (approved submissions with user and quest info)
create or replace function public.get_feed(p_limit integer default 20, p_offset integer default 0)
returns table (
  submission_id uuid,
  media_url text,
  media_type text,
  caption text,
  submitted_at timestamptz,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  quest_title text,
  quest_category text,
  reaction_count bigint
) as $$
begin
  return query
    select
      s.id as submission_id,
      s.media_url,
      s.media_type,
      s.caption,
      s.submitted_at,
      p.id as user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      q.title as quest_title,
      q.category as quest_category,
      (select count(*) from public.reactions r where r.submission_id = s.id) as reaction_count
    from public.submissions s
    join public.profiles p on p.id = s.user_id
    join public.user_quests uq on uq.id = s.user_quest_id
    join public.quests q on q.id = uq.quest_id
    where s.status = 'approved'
    order by s.submitted_at desc
    limit p_limit
    offset p_offset;
end;
$$ language plpgsql security definer stable;
