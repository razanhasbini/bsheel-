-- Canonical body for get_feed(p_limit, p_offset, p_sort, p_scope).
-- Authoritative since migration 0149 (previous: 0135).
--
-- 0149 restored the blocked-users anti-join that 0069 added and every
-- reissue from 0073 onward silently dropped, and floored p_offset.
-- p_limit has been clamped to [1,50] since 0135 — that is NOT new.
--
-- When you next change this, edit THIS file + add a migration that
-- INLINES the body (\i cannot resolve — see README).
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
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_uid uuid := auth.uid();
  -- Unchanged from 0135:58. The p_limit cap is NOT new.
  v_limit integer := LEAST(GREATEST(coalesce(p_limit, 20), 1), 50);
  -- 0149: floor only, no ceiling. See header.
  v_offset integer := GREATEST(coalesce(p_offset, 0), 0);
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
      -- 0149 REGRESSION FIX — restores applied/0069:226-230. Backed by
      -- 0069's `CONSTRAINT unique_block UNIQUE (blocker_id, blocked_id)`,
      -- so this is a cheap anti-join. Applied BEFORE LIMIT, so
      -- `hasMore: raw.length >= _pageSize` (feed_provider.dart:214) is
      -- unaffected.
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users bu
        WHERE bu.blocker_id = v_uid
          AND bu.blocked_id = s.user_id
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
    OFFSET v_offset;
END;
$$;

-- 0135:174 revoked from `anon` only. Because 0135:20 DROPped and 0135:22
-- CREATEd a NEW function object, it received Postgres's default
-- EXECUTE-to-PUBLIC and anon inherited through PUBLIC — 0135 alone did
-- NOT close the hole; 0143:103 did. Always name PUBLIC.
-- (CREATE OR REPLACE preserves the ACL, so this is belt-and-braces.)
REVOKE EXECUTE ON FUNCTION public.get_feed(integer, integer, text, text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_feed(integer, integer, text, text) TO authenticated;
