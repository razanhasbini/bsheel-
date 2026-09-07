-- Migration 0049: Add feed visibility and soft-delete to submissions
-- show_in_feed: user choice at submission time (show in feed or profile only)
-- visibility: tracks deletion state (visible / hidden_from_feed / deleted)
-- deleted_at: timestamp of soft-delete

alter table public.submissions
  add column if not exists show_in_feed boolean not null default true,
  add column if not exists visibility text not null default 'visible',
  add column if not exists deleted_at timestamptz;

-- Update get_feed RPC to exclude posts hidden from feed or deleted
drop function if exists public.get_feed(integer, integer);

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
  bio text,
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
      p.bio,
      q.title as quest_title,
      q.description as quest_description,
      q.category as quest_category,
      q.xp_reward,
      0::bigint as reaction_count
    from public.submissions s
    join public.profiles p on p.id = s.user_id
    join public.user_quests uq on uq.id = s.user_quest_id
    join public.quests q on q.id = uq.quest_id
    where s.status = 'approved'
      and s.show_in_feed = true
      and s.visibility = 'visible'
    order by s.submitted_at desc
    limit p_limit
    offset p_offset;
end;
$$ language plpgsql security definer stable;
