var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
let FeedRepository = class FeedRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async list(viewerId, query) {
        const result = await this.database.query(`SELECT
         s.id AS submission_id, s.media_url, s.media_type::text, s.caption, s.submitted_at,
         p.id AS user_id, p.username::text, p.display_name, p.avatar_url, p.bio,
         q.id AS quest_id, q.title AS quest_title, q.description AS quest_description,
         q.category AS quest_category, q.xp_reward,
         COALESCE(r.total, 0)::bigint AS reaction_count,
         COALESCE(r.ups, 0)::bigint AS upvote_count,
         COALESCE(r.downs, 0)::bigint AS downvote_count,
         (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::bigint AS net_score,
         (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision /
           power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5) AS hot_score,
         (gm.group_id IS NOT NULL) AS is_collab, gm.group_id AS collab_group_id,
         g.mode::text AS collab_mode, COALESCE(mc.cnt, 0)::bigint AS collab_member_count,
         CASE WHEN gm.group_id IS NOT NULL THEN (
           SELECT json_agg(json_build_object(
             'user_id', mp.id, 'username', mp.username::text, 'display_name', mp.display_name,
             'avatar_url', mp.avatar_url, 'bio', mp.bio, 'submission_id', ms.id,
             'media_url', ms.media_url, 'media_type', ms.media_type::text,
             'submission_status', ms.status::text, 'caption', ms.caption,
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
         ) ELSE NULL END AS collab_members,
         uq.expires_at
       FROM submissions s JOIN profiles p ON p.id = s.user_id
       JOIN user_quests uq ON uq.id = s.user_quest_id JOIN quests q ON q.id = uq.quest_id
       LEFT JOIN LATERAL (
         SELECT count(*) AS total,
           count(*) FILTER (WHERE rx.type = 'upvote') AS ups,
           count(*) FILTER (WHERE rx.type = 'downvote') AS downs
         FROM reactions rx WHERE rx.submission_id = s.id
       ) r ON true
       LEFT JOIN collab_group_members gm ON gm.user_quest_id = uq.id
       LEFT JOIN collab_groups g ON g.id = gm.group_id
       LEFT JOIN (SELECT group_id, count(*) AS cnt FROM collab_group_members GROUP BY group_id) mc ON mc.group_id = gm.group_id
       WHERE s.status = 'approved' AND s.show_in_feed AND s.visibility = 'visible' AND s.deleted_at IS NULL
         AND (gm.group_id IS NULL OR gm.user_id = g.creator_id)
         AND ($5 <> 'following' OR EXISTS (
           SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.following_id = s.user_id
         ))
         AND NOT EXISTS (
           SELECT 1 FROM blocked_users bu
           WHERE (bu.blocker_id = $1 AND bu.blocked_id = s.user_id)
              OR (bu.blocker_id = s.user_id AND bu.blocked_id = $1)
         )
       ORDER BY
         CASE WHEN $4 = 'top' THEN COALESCE(r.ups, 0) - COALESCE(r.downs, 0) END DESC NULLS LAST,
         CASE WHEN $4 = 'hot' THEN (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision /
           power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5) END DESC NULLS LAST,
         CASE WHEN $4 = 'bottom' THEN COALESCE(r.ups, 0) - COALESCE(r.downs, 0) END ASC NULLS LAST,
         CASE WHEN $4 = 'graveyard' THEN (COALESCE(r.ups, 0) - COALESCE(r.downs, 0))::double precision /
           power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5) END ASC NULLS LAST,
         s.submitted_at DESC, s.id DESC
       LIMIT $2 OFFSET $3`, [viewerId, query.limit, query.offset, query.sort, query.scope]);
        return result.rows;
    }
};
FeedRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], FeedRepository);
export { FeedRepository };
//# sourceMappingURL=feed.repository.js.map