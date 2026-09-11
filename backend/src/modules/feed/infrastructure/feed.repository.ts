import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { FeedQueryDto } from '../presentation/feed.dto.js';
import { decodeCursor, encodeCursor } from '../../../common/pagination/keyset-cursor.js';

@Injectable()
export class FeedRepository {
  constructor(private readonly database: DatabaseService) {}

  async list(viewerId: string, query: FeedQueryDto): Promise<readonly Record<string, unknown>[]> {
    const context = `feed:${viewerId}:${query.scope}:${query.sort}`;
    const cursor = decodeCursor(query.cursor, context);
    const asOf = cursor?.asOf ?? new Date().toISOString();
    // SQL fragments come only from this closed set, never from user-provided SQL.
    const timeWeighted = query.sort === 'hot' || query.sort === 'graveyard';
    const ranked = query.sort !== 'recent';
    const ascending = query.sort === 'bottom' || query.sort === 'graveyard';
    const score = timeWeighted
      ? 's.net_score::double precision / power(GREATEST(EXTRACT(EPOCH FROM ($4::timestamptz - s.submitted_at)) / 3600.0, 0) + 2.0, 1.5)'
      : 's.net_score';
    const order = `${ranked ? `${score} ${ascending ? 'ASC' : 'DESC'}, ` : ''}s.submitted_at DESC, s.id DESC`;
    const seek = cursor
      ? ranked
        ? `AND (${score} ${ascending ? '>' : '<'} $7::double precision OR (${score} = $7::double precision AND (s.submitted_at, s.id) < ($5::timestamptz, $6::uuid)))`
        : 'AND (s.submitted_at, s.id) < ($5::timestamptz, $6::uuid)'
      : '';
    const values: unknown[] = [viewerId, query.limit, cursor ? 0 : query.offset, asOf];
    if (cursor) values.push(cursor.at, cursor.id, ...(ranked ? [cursor.score ?? 0] : []));
    const result = await this.database.query(
      `WITH ranked AS MATERIALIZED (
         SELECT s.id, ${score} AS rank_score, s.submitted_at,
                row_number() OVER (ORDER BY ${order}) AS position
         FROM submissions s
         WHERE s.status = 'approved' AND s.show_in_feed AND s.visibility = 'visible' AND s.deleted_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM collab_group_members member JOIN collab_groups grp ON grp.id = member.group_id
                           WHERE member.user_quest_id = s.user_quest_id AND member.user_id <> grp.creator_id)
           ${query.scope === 'following' ? 'AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.following_id = s.user_id)' : ''}
           AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = $1 AND b.blocked_id = s.user_id)
           AND NOT EXISTS (SELECT 1 FROM blocked_users b WHERE b.blocker_id = s.user_id AND b.blocked_id = $1)
           ${seek}
         ORDER BY ${order} LIMIT $2 OFFSET $3
       ) SELECT
         ranked.rank_score AS pagination_score,
         to_char(s.submitted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS pagination_at,
         s.id AS submission_id, s.media_url, s.media_type::text, s.caption, s.submitted_at,
         p.id AS user_id, p.username::text, p.display_name, p.avatar_url, p.bio,
         q.id AS quest_id, q.title AS quest_title, q.description AS quest_description,
         q.category AS quest_category, q.xp_reward,
         -- Where the quest actually is, for the share card. The authoritative
         -- source is the quest's reviewed destination — never anything a
         -- caption or a vision model guessed. Null for a quest with no
         -- destination, which is most of them.
         dc.name AS quest_country_name, dc.code AS quest_country_code,
         COALESCE(r.total, 0)::bigint AS reaction_count,
         COALESCE(r.ups, 0)::bigint AS upvote_count,
         COALESCE(r.downs, 0)::bigint AS downvote_count,
         r.viewer_vote,
         COALESCE(sv.viewer_saved, false) AS viewer_saved,
         COALESCE(cc.cnt, 0)::bigint AS comment_count,
         s.net_score,
         s.net_score::double precision /
           power(GREATEST(EXTRACT(EPOCH FROM ($4::timestamptz - s.submitted_at)) / 3600.0, 0) + 2.0, 1.5) AS hot_score,
         (gm.group_id IS NOT NULL) AS is_collab, gm.group_id AS collab_group_id,
         g.mode::text AS collab_mode, COALESCE(mc.cnt, 0)::bigint AS collab_member_count,
         -- The roster stays complete so the client can draw a "waiting" slot
         -- for a member whose proof is not public yet, but the BYTES and the
         -- caption are withheld unless the viewer is allowed to see them.
         --
         -- This subquery used to expose ms.media_url and ms.caption for every
         -- member with no status, visibility, deleted_at or block predicate at
         -- all, while the outer "ranked" CTE filtered all four correctly. That
         -- served pending and moderator-REJECTED proof to any signed-in user,
         -- and POST /media/sign turned the leaked key into the image.
         CASE WHEN gm.group_id IS NOT NULL THEN (
           SELECT json_agg(json_build_object(
             'user_id', mp.id, 'username', mp.username::text, 'display_name', mp.display_name,
             'avatar_url', mp.avatar_url, 'bio', mp.bio, 'submission_id', ms.id,
             'media_url', CASE WHEN ms.user_id = $1
                                 OR (ms.status = 'approved' AND ms.visibility = 'visible' AND ms.deleted_at IS NULL)
                            THEN ms.media_url END,
             'media_type', ms.media_type::text,
             'submission_status', ms.status::text,
             'caption', CASE WHEN ms.user_id = $1
                               OR (ms.status = 'approved' AND ms.visibility = 'visible' AND ms.deleted_at IS NULL)
                          THEN ms.caption END,
             'show_in_feed', ms.show_in_feed, 'vote_count', COALESCE(vc.cnt, 0),
             'viewer_voted', COALESCE(mv.voted, false)
           ) ORDER BY m2.joined_at)
           FROM collab_group_members m2 JOIN profiles mp ON mp.id = m2.user_id
           LEFT JOIN submissions ms ON ms.user_quest_id = m2.user_quest_id
           LEFT JOIN (
             SELECT cv.submission_id AS sid, count(*) AS cnt FROM collab_votes cv
             WHERE cv.group_id = gm.group_id GROUP BY cv.submission_id
           ) vc ON vc.sid = ms.id
           LEFT JOIN (
             SELECT cv.submission_id AS sid, true AS voted FROM collab_votes cv
             WHERE cv.group_id = gm.group_id AND cv.voter_id = $1
           ) mv ON mv.sid = ms.id
           WHERE m2.group_id = gm.group_id
             -- Same bidirectional block predicate the outer CTE applies to the
             -- post's author, so a blocked account does not reappear inside a
             -- group roster.
             AND NOT EXISTS (SELECT 1 FROM blocked_users b
                             WHERE (b.blocker_id = $1 AND b.blocked_id = mp.id)
                                OR (b.blocker_id = mp.id AND b.blocked_id = $1))
         ) ELSE NULL END AS collab_members,
         uq.expires_at
       FROM ranked JOIN submissions s ON s.id = ranked.id JOIN profiles p ON p.id = s.user_id
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       LEFT JOIN quest_destinations qd ON qd.quest_id = q.id
       LEFT JOIN map_places dp ON dp.id = qd.place_id AND dp.is_published
       LEFT JOIN map_countries dc ON dc.code = dp.country_code
       LEFT JOIN LATERAL (
         SELECT count(*) AS total,
           count(*) FILTER (WHERE rx.type = 'upvote') AS ups,
           count(*) FILTER (WHERE rx.type = 'downvote') AS downs,
           -- The viewer's own vote, so the client stops asking per card.
           max(rx.type::text) FILTER (WHERE rx.user_id = $1) AS viewer_vote
         FROM reactions rx WHERE rx.submission_id = s.id
       ) r ON true
       -- Whether the viewer saved this, and how many comments it has.
       --
       -- Both used to be per-card round trips: myVoteProvider,
       -- isPostSavedProvider and feedCommentCountProvider each fired for
       -- every post, so one 20-post page cost 1 + 60 requests — and the
       -- comment count was obtained by downloading the entire comment list
       -- in a 200-per-page loop just to render one integer.
       LEFT JOIN LATERAL (
         SELECT EXISTS (
           SELECT 1 FROM saved_posts sp
           WHERE sp.submission_id = s.id AND sp.user_id = $1
         ) AS viewer_saved
       ) sv ON true
       LEFT JOIN LATERAL (
         SELECT count(*) AS cnt FROM comments c WHERE c.submission_id = s.id
       ) cc ON true
       LEFT JOIN collab_group_members gm ON gm.user_quest_id = uq.id
       LEFT JOIN collab_groups g ON g.id = gm.group_id
       LEFT JOIN LATERAL (SELECT count(*) AS cnt FROM collab_group_members WHERE group_id = gm.group_id) mc ON true
       ORDER BY ranked.position`,
      values,
    );
    return result.rows.map(({ pagination_at, pagination_score, ...row }) => ({
      ...row,
      next_cursor: encodeCursor({ context, at: pagination_at as string, id: row.submission_id as string, score: Number(pagination_score), asOf }),
    }));
  }
}
