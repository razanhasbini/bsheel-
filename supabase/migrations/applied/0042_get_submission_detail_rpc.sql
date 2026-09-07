-- Migration 0042: Add get_submission_detail RPC
-- Returns full submission data (profile + quest) for a single post.
-- Avoids PostgREST FK ambiguity by using SQL JOINs directly.

create or replace function public.get_submission_detail(p_submission_id uuid)
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
  xp_reward integer
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
      q.xp_reward
    from public.submissions s
    join public.profiles p on p.id = s.user_id
    join public.user_quests uq on uq.id = s.user_quest_id
    join public.quests q on q.id = uq.quest_id
    where s.id = p_submission_id
    limit 1;
end;
$$ language plpgsql security definer stable;
