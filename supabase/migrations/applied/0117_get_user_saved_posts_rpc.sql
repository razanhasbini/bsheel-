-- ============================================================
-- MIGRATION 0112: get_user_saved_posts RPC
-- Returns a user's saved (BSHEEEL) posts joined with submission
-- and quest info, in one round-trip. Filters out submissions whose
-- visibility = 'deleted' (admin removed) so they don't surface in the
-- BSHEEEL list as ghost rows. Bypasses the get_submission_detail
-- approval gate so saved posts that were later rejected still appear.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_user_saved_posts(p_user_id uuid)
RETURNS TABLE (
  saved_id uuid,
  saved_at timestamptz,
  submission_id uuid,
  media_url text,
  media_type text,
  visibility text,
  status text,
  quest_id uuid,
  quest_title text,
  quest_description text,
  quest_category text,
  xp_reward integer,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_url text
) AS $$
  SELECT
    sp.id            AS saved_id,
    sp.created_at    AS saved_at,
    s.id             AS submission_id,
    s.media_url,
    s.media_type,
    s.visibility,
    s.status,
    q.id             AS quest_id,
    q.title          AS quest_title,
    q.description    AS quest_description,
    q.category       AS quest_category,
    q.xp_reward,
    p.id             AS author_id,
    p.username       AS author_username,
    p.display_name   AS author_display_name,
    p.avatar_url     AS author_avatar_url
  FROM public.saved_posts sp
  JOIN public.submissions s   ON s.id = sp.submission_id
  JOIN public.user_quests uq  ON uq.id = s.user_quest_id
  JOIN public.quests q        ON q.id = uq.quest_id
  JOIN public.profiles p      ON p.id = s.user_id
  WHERE sp.user_id = p_user_id
    AND s.visibility <> 'deleted'
  ORDER BY sp.created_at DESC;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_user_saved_posts(uuid) TO authenticated;
