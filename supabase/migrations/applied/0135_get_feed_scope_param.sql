-- ============================================================
-- MIGRATION 0135: Add `p_scope` to get_feed (ARC-011) +
-- LATERAL-ize the reactions aggregate (same fix as 0134 for
-- get_submission_detail).
--
-- Previously the client-side `loadMore()` for `scope == 'following'`
-- relied on a heuristic offset trick because the RPC didn't know
-- about following. The result was that pagination skipped or
-- duplicated posts depending on how dense the followed-set was in
-- a given window.
--
-- Server-side scope filtering puts the responsibility back on the
-- DB, which can apply the filter and pagination consistently.
--
-- The new param has DEFAULT 'all' so existing 3-arg callers keep
-- working unchanged. We also clamp p_limit to 50 inline to honor
-- the comment added in 0120's COMMENT block.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_feed(integer, integer, text);

CREATE OR REPLACE FUNCTION public.get_feed(
  p_limit integer,
  p_offset integer,
  p_sort text,
  p_scope text DEFAULT 'all'
)
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
  quest_id uuid,
  quest_title text,
  quest_description text,
  quest_category text,
  xp_reward integer,
  reaction_count bigint,
  upvote_count bigint,
  downvote_count bigint,
  net_score bigint,
  hot_score double precision,
  is_collab boolean,
  collab_group_id uuid,
  collab_mode text,
  collab_member_count bigint,
  collab_members json,
  expires_at timestamptz
) AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(coalesce(p_limit, 20), 1), 50);
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
      q.id AS quest_id,
      q.title AS quest_title,
      q.description AS quest_description,
      q.category AS quest_category,
      q.xp_reward,
      COALESCE(r.total, 0)::bigint AS reaction_count,
      COALESCE(r.ups, 0)::bigint   AS upvote_count,
      COALESCE(r.downs, 0)::bigint AS downvote_count,
      (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::bigint AS net_score,
      (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision
        / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5)
        AS hot_score,
      (gm.group_id IS NOT NULL) AS is_collab,
      gm.group_id AS collab_group_id,
      g.mode AS collab_mode,
      COALESCE(mc.cnt, 0)::bigint AS collab_member_count,
      CASE WHEN gm.group_id IS NOT NULL THEN (
        SELECT json_agg(json_build_object(
          'user_id',           mp.id,
          'username',          mp.username,
          'display_name',      mp.display_name,
          'avatar_url',        mp.avatar_url,
          'bio',               mp.bio,
          'submission_id',     ms.id,
          'media_url',         ms.media_url,
          'media_type',        ms.media_type,
          'submission_status', ms.status,
          'caption',           ms.caption,
          'show_in_feed',      ms.show_in_feed,
          'vote_count',        COALESCE(vc.cnt, 0),
          'viewer_voted',      COALESCE(mv.voted, false)
        ) ORDER BY m2.joined_at)
        FROM public.collab_group_members m2
        JOIN public.profiles mp ON mp.id = m2.user_id
        LEFT JOIN public.submissions ms ON ms.user_quest_id = m2.user_quest_id
        LEFT JOIN (
          SELECT cv.submission_id AS sid, count(*) AS cnt
          FROM public.collab_votes cv
          WHERE cv.group_id = gm.group_id
          GROUP BY cv.submission_id
        ) vc ON vc.sid = ms.id
        LEFT JOIN (
          SELECT cv.submission_id AS sid, true AS voted
          FROM public.collab_votes cv
          WHERE cv.group_id = gm.group_id
            AND cv.voter_id = v_uid
        ) mv ON mv.sid = ms.id
        WHERE m2.group_id = gm.group_id
      ) ELSE NULL END AS collab_members,
      uq.expires_at AS expires_at
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    -- ARC-018 sibling: per-row LATERAL aggregate instead of global.
    LEFT JOIN LATERAL (
      SELECT
        count(*) AS total,
        count(*) FILTER (WHERE rx.type = 'upvote')   AS ups,
        count(*) FILTER (WHERE rx.type = 'downvote') AS downs
      FROM public.reactions rx
      WHERE rx.submission_id = s.id
    ) r ON true
    LEFT JOIN public.collab_group_members gm ON gm.user_quest_id = uq.id
    LEFT JOIN public.collab_groups g ON g.id = gm.group_id
    LEFT JOIN (
      SELECT group_id, count(*) AS cnt
      FROM public.collab_group_members GROUP BY group_id
    ) mc ON mc.group_id = gm.group_id
    WHERE s.status = 'approved'
      AND s.show_in_feed = true
      AND s.visibility = 'visible'
      AND (
        gm.group_id IS NULL
        OR gm.user_id = g.creator_id
      )
      -- ARC-011: scope filter. 'following' only shows posts from
      -- users the caller follows; 'all' (default) is the global feed.
      AND (
        p_scope IS DISTINCT FROM 'following'
        OR s.user_id IN (
          SELECT f.following_id FROM public.follows f
          WHERE f.follower_id = v_uid
        )
      )
    ORDER BY
      CASE WHEN p_sort = 'top' THEN (COALESCE(r.ups, 0) - COALESCE(r.downs, 0)) END DESC NULLS LAST,
      CASE WHEN p_sort = 'hot' THEN
        (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision
        / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5)
      END DESC NULLS LAST,
      CASE WHEN p_sort = 'bottom' THEN (COALESCE(r.ups, 0) - COALESCE(r.downs, 0)) END ASC NULLS LAST,
      CASE WHEN p_sort = 'graveyard' THEN
        (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision
        / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5)
      END ASC NULLS LAST,
      s.submitted_at DESC
    LIMIT v_limit
    OFFSET coalesce(p_offset, 0);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION public.get_feed(integer, integer, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_feed(integer, integer, text, text) TO authenticated;
