-- ============================================================
-- MIGRATION 0064: Fix 0-XP rank inconsistency in get_user_xp_stats (L13)
-- Was counting only users with xp > current user's xp.
-- Now counts all users with a username (matching leaderboard).
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_user_xp_stats(p_user_id uuid)
RETURNS TABLE (
  total_xp integer,
  current_level integer,
  xp_to_next_level integer,
  total_quests integer,
  rank bigint
) AS $$
BEGIN
  RETURN QUERY
    SELECT
      p.xp AS total_xp,
      p.level AS current_level,
      (p.level * 100) - p.xp AS xp_to_next_level,
      p.quests_completed AS total_quests,
      (SELECT count(*) + 1 FROM public.profiles p2
       WHERE p2.username IS NOT NULL
         AND (p2.xp > p.xp OR (p2.xp = p.xp AND p2.created_at < p.created_at))
      ) AS rank
    FROM public.profiles p
    WHERE p.id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
