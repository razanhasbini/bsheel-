-- ============================================================
-- MIGRATION 0062: Fix leaderboard to include 0-XP users (L7)
-- New users with 0 XP should appear on the leaderboard.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_leaderboard(p_limit integer DEFAULT 50)
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
    ORDER BY p.xp DESC, p.created_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
