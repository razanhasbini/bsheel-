-- Migration 0032: Remove correlated reaction_count sub-query from get_feed RPC.
-- The Dart client re-fetches reaction counts in a separate batch query anyway,
-- so the per-row correlated sub-query was redundant and wasteful.

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
