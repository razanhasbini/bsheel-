-- ============================================================
-- MIGRATION 0065: Fix feed N+1 reaction query (L6)
-- Include per-submission reaction count directly in get_feed RPC
-- instead of hardcoded 0, eliminating client-side N+1 queries.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_feed(integer, integer);

CREATE OR REPLACE FUNCTION public.get_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS TABLE (
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
) AS $$
BEGIN
  RETURN QUERY
    SELECT
      s.id AS submission_id,
      s.media_url,
      s.media_type,
      s.caption,
      s.submitted_at,
      p.id AS user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      p.bio,
      q.title AS quest_title,
      q.description AS quest_description,
      q.category AS quest_category,
      q.xp_reward,
      COALESCE(r.cnt, 0)::bigint AS reaction_count
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    LEFT JOIN (
      SELECT submission_id AS sid, count(*) AS cnt
      FROM public.reactions
      GROUP BY submission_id
    ) r ON r.sid = s.id
    WHERE s.status = 'approved'
      AND s.show_in_feed = true
      AND s.visibility = 'visible'
    ORDER BY s.submitted_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
