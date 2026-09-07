-- Migration 0041: Add quest_description and xp_reward to get_feed RPC
-- Previously missing, causing empty quest info on post detail page.

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
  quest_description text,
  quest_category text,
  xp_reward integer,
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
      q.description as quest_description,
      q.category as quest_category,
      q.xp_reward,
      0::bigint as reaction_count  -- placeholder; Dart layer fetches real counts
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
