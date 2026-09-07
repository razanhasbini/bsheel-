-- ============================================================
-- MIGRATION 0081: get_following_leaderboard RPC
--
-- Leaderboard filtered to only people the caller follows.
-- Same return shape as get_leaderboard so the client can reuse
-- the same model.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_following_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE (
  rank bigint,
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  xp integer,
  level integer,
  quests_completed integer
) AS $$
BEGIN
  RETURN QUERY
    SELECT
      row_number() OVER (ORDER BY p.xp DESC, p.created_at ASC) AS rank,
      p.id AS user_id,
      p.username,
      p.display_name,
      p.avatar_url,
      p.xp,
      p.level,
      p.quests_completed
    FROM public.profiles p
    WHERE p.username IS NOT NULL
      AND (
        p.id IN (SELECT f.following_id FROM public.follows f WHERE f.follower_id = auth.uid())
        OR p.id = auth.uid()
      )
    ORDER BY p.xp DESC, p.created_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
