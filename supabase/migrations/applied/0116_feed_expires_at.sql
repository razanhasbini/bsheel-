-- ============================================================
-- MIGRATION 0116: surface user_quests.expires_at on get_feed +
--                 get_submission_detail so the client can render
--                 "DIDN'T POST" for members who never submitted
--                 once the quest deadline has passed.
-- ============================================================
--
-- Source of truth:
--   user_quests.expires_at — the deadline of the post-owner's quest.
--   For coop/versus this is the creator's deadline, which the rest of
--   the team shares (they joined into the same active window).
-- ============================================================

DROP FUNCTION IF EXISTS public.get_feed(integer, integer, text);

CREATE OR REPLACE FUNCTION public.get_feed(
  p_limit  integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_sort   text    DEFAULT 'recent'
)
RETURNS TABLE (
  submission_id        uuid,
  media_url            text,
  media_type           text,
  caption              text,
  submitted_at         timestamptz,
  user_id              uuid,
  username             text,
  display_name         text,
  avatar_url           text,
  bio                  text,
  quest_id             uuid,
  quest_title          text,
  quest_description    text,
  quest_category       text,
  xp_reward            integer,
  reaction_count       bigint,
  upvote_count         bigint,
  downvote_count       bigint,
  net_score            bigint,
  hot_score            double precision,
  is_collab            boolean,
  collab_group_id      uuid,
  collab_mode          text,
  collab_member_count  bigint,
  collab_members       json,
  expires_at           timestamptz
) AS $$
DECLARE
  v_uid uuid := auth.uid();
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
    LEFT JOIN (
      SELECT
        rx.submission_id AS sid,
        count(*) AS total,
        count(*) FILTER (WHERE rx.type = 'upvote')   AS ups,
        count(*) FILTER (WHERE rx.type = 'downvote') AS downs
      FROM public.reactions rx
      GROUP BY rx.submission_id
    ) r ON r.sid = s.id
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
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.get_feed(integer, integer, text) TO authenticated, anon;

-- ── get_submission_detail ──────────────────────────────────
-- Drop first because Postgres won't let CREATE OR REPLACE change the
-- function's return-row shape (we're adding a new `expires_at` column).
DROP FUNCTION IF EXISTS public.get_submission_detail(uuid);

CREATE OR REPLACE FUNCTION public.get_submission_detail(p_submission_id uuid)
RETURNS TABLE (
  submission_id        uuid,
  media_url            text,
  media_type           text,
  caption              text,
  submitted_at         timestamptz,
  user_id              uuid,
  username             text,
  display_name         text,
  avatar_url           text,
  bio                  text,
  quest_id             uuid,
  quest_title          text,
  quest_description    text,
  quest_category       text,
  xp_reward            integer,
  show_in_feed         boolean,
  visibility           text,
  is_collab            boolean,
  collab_group_id      uuid,
  collab_mode          text,
  collab_member_count  bigint,
  collab_members       json,
  upvote_count         bigint,
  downvote_count       bigint,
  net_score            bigint,
  expires_at           timestamptz
) AS $$
DECLARE
  v_group_id uuid;
  v_leader_submission_id uuid;
  v_uid uuid := auth.uid();
BEGIN
  SELECT gm.group_id INTO v_group_id
  FROM public.submissions s
  JOIN public.collab_group_members gm ON gm.user_quest_id = s.user_quest_id
  WHERE s.id = p_submission_id
  LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    SELECT ms.id INTO v_leader_submission_id
    FROM public.collab_groups g
    JOIN public.collab_group_members gm
      ON gm.group_id = g.id AND gm.user_id = g.creator_id
    JOIN public.submissions ms ON ms.user_quest_id = gm.user_quest_id
    WHERE g.id = v_group_id
    LIMIT 1;
  END IF;

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
      s.show_in_feed,
      s.visibility,
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
      COALESCE(r.ups, 0)::bigint AS upvote_count,
      COALESCE(r.downs, 0)::bigint AS downvote_count,
      (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::bigint AS net_score,
      uq.expires_at AS expires_at
    FROM public.submissions s
    JOIN public.profiles p ON p.id = s.user_id
    JOIN public.user_quests uq ON uq.id = s.user_quest_id
    JOIN public.quests q ON q.id = uq.quest_id
    LEFT JOIN public.collab_group_members gm ON gm.user_quest_id = uq.id
    LEFT JOIN public.collab_groups g ON g.id = gm.group_id
    LEFT JOIN (
      SELECT group_id, count(*) AS cnt
      FROM public.collab_group_members GROUP BY group_id
    ) mc ON mc.group_id = gm.group_id
    LEFT JOIN (
      SELECT
        rx.submission_id AS sid,
        count(*) FILTER (WHERE rx.type = 'upvote')   AS ups,
        count(*) FILTER (WHERE rx.type = 'downvote') AS downs
      FROM public.reactions rx
      GROUP BY rx.submission_id
    ) r ON r.sid = s.id
    WHERE s.id = COALESCE(v_leader_submission_id, p_submission_id)
      AND (s.status = 'approved' OR s.user_id = auth.uid())
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.get_submission_detail(uuid) TO authenticated, anon;
